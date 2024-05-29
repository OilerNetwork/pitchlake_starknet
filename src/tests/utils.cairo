use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, contract_address_try_from_felt252, testing,
    testing::{set_block_timestamp, set_contract_address}
};
use openzeppelin::{
    utils::serde::SerializedAppend,
    token::erc20::{
        ERC20Component,
        interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,}
    }
};
use pitch_lake_starknet::{
    eth::Eth,
    pitch_lake::{
        IPitchLakeDispatcher, IPitchLakeSafeDispatcher, IPitchLakeDispatcherTrait, PitchLake,
        IPitchLakeSafeDispatcherTrait
    },
    market_aggregator::{
        MarketAggregator, IMarketAggregator, IMarketAggregatorDispatcher,
        IMarketAggregatorDispatcherTrait, IMarketAggregatorSafeDispatcher,
        IMarketAggregatorSafeDispatcherTrait
    },
    vault::{IVaultDispatcher, IVaultDispatcherTrait, Vault, VaultType}, option_round,
    option_round::{
        OptionRound, StartAuctionParams, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,
        IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundState,
    },
    tests::{
        utils_new::{
            structs::{OptionRoundParams}, event_helpers::{clear_event_logs},
            test_accounts::{liquidity_providers_get, option_bidders_get}
        },
        option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
        vault_facade::{VaultFacade, VaultFacadeTrait},
        mocks::mock_market_aggregator::{
            MockMarketAggregator, IMarketAggregatorSetterDispatcher,
            IMarketAggregatorSetterDispatcherTrait
        },
    },
};
use debug::PrintTrait;

const DECIMALS: u8 = 18_u8;
const SUPPLY: u256 = 99999999999999999999999999999999;

// Deploy eth contract for testing
fn deploy_eth() -> IERC20Dispatcher {
    let mut calldata = array![];

    calldata.append_serde(SUPPLY);
    calldata.append_serde(weth_owner());

    let (contract_address, _): (ContractAddress, Span<felt252>) = deploy_syscall(
        Eth::TEST_CLASS_HASH.try_into().unwrap(), 'some salt', calldata.span(), false
    )
        .unwrap();

    // Clear the event log
    clear_event_logs(array![contract_address]);
    return IERC20Dispatcher { contract_address };
}

// Deploy market aggregator for testing
fn deploy_market_aggregator() -> IMarketAggregatorDispatcher {
    let mut calldata = array![];

    let (contract_address, _) = deploy_syscall(
        MockMarketAggregator::TEST_CLASS_HASH.try_into().unwrap(),
        'some salt',
        calldata.span(),
        true
    )
        .expect('DEPLOY_MARKET_AGGREGATOR_FAILED');

    // Clear the event log
    clear_event_logs(array![contract_address]);
    return IMarketAggregatorDispatcher { contract_address };
}

// Deploy the vault and market aggregator
fn deploy_vault(vault_type: VaultType) -> IVaultDispatcher {
    let mut calldata = array![];
    calldata.append_serde(vault_manager());
    calldata.append_serde(vault_type);
    calldata.append_serde(deploy_market_aggregator().contract_address); // needed ?
    calldata.append_serde(OptionRound::TEST_CLASS_HASH);

    let (contract_address, _) = deploy_syscall(
        Vault::TEST_CLASS_HASH.try_into().unwrap(), 'some salt', calldata.span(), true
    )
        .expect('DEPLOY_VAULT_FAILED');

    // Clear the event log
    clear_event_logs(array![contract_address]);

    return IVaultDispatcher { contract_address };
}

fn deploy_pitch_lake() -> IPitchLakeDispatcher {
    let mut calldata = array![];

    let ITM: IVaultDispatcher = deploy_vault(VaultType::InTheMoney);
    let OTM: IVaultDispatcher = deploy_vault(VaultType::OutOfMoney);
    let ATM: IVaultDispatcher = deploy_vault(VaultType::AtTheMoney);
    let mkagg = deploy_market_aggregator();

    calldata.append_serde(ITM.contract_address);
    calldata.append_serde(OTM.contract_address);
    calldata.append_serde(ATM.contract_address);
    calldata.append_serde(mkagg.contract_address);

    let (contract_address, _) = deploy_syscall(
        PitchLake::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .expect('DEPLOY_AD_FAILED');

    // Clear event logs
    clear_event_logs(
        array![
            ITM.contract_address,
            OTM.contract_address,
            ATM.contract_address,
            mkagg.contract_address,
            contract_address
        ]
    );

    return IPitchLakeDispatcher { contract_address };
}

fn setup_facade() -> (VaultFacade, IERC20Dispatcher) {
    let eth_dispatcher: IERC20Dispatcher = deploy_eth();
    let vault_dispatcher: IVaultDispatcher = deploy_vault(VaultType::InTheMoney);

    // Supply eth to test users
    set_contract_address(weth_owner());
    let mut lps = liquidity_providers_get(5);
    loop {
        match lps.pop_front() {
            Option::Some(lp) => {
                let lp_amount_wei: u256 = 1000000 * decimals(); // 1,000,000 ETH
                eth_dispatcher.transfer(lp, lp_amount_wei);
            },
            Option::None => { break (); },
        };
    };

    // Give OBs eth
    let mut obs = option_bidders_get(5);
    loop {
        match obs.pop_front() {
            Option::Some(ob) => {
                let ob_amount_wei: u256 = 100000 * decimals(); // 100,000 ETH

                eth_dispatcher.transfer(ob, ob_amount_wei);
            },
            Option::None => { break; },
        };
    };

    // Clear eth transfer events
    clear_event_logs(array![eth_dispatcher.contract_address]);

    return (VaultFacade { vault_dispatcher }, eth_dispatcher);
}

fn decimals() -> u256 {
    //10  ** 18
    1000000000000000000
}

fn mock_option_params() -> OptionRoundParams {
    let total_unallocated_liquidity: u256 = 10000 * decimals(); // from LPs ?
    let option_reserve_price_: u256 = 6 * decimals(); // from market aggregator (fossil) ?
    let average_basefee: u256 = 20; // from market aggregator (fossil) ?
    let standard_deviation: u256 = 30; // from market aggregator (fossil) ?
    let cap_level: u256 = average_basefee
        + (3
            * standard_deviation); //per notes from tomasz, we set cap level at 3 standard deviation (captures 99.7% of the data points)

    let in_the_money_strike_price: u256 = average_basefee + standard_deviation;
    //let at_the_money_strike_price: u256 = average_basefee;
    //let out_the_money_strike_price: u256 = average_basefee - standard_deviation;

    let collateral_level: u256 = cap_level - in_the_money_strike_price; // per notes from tomasz
    let total_options_available: u256 = total_unallocated_liquidity / collateral_level;

    let option_reserve_price: u256 = option_reserve_price_; // just an assumption

    // option_expiry_time:u64, // OptionRound cannot settle before this time
    // auction_end_time:u64, // auction cannot settle before this time
    // minimum_bid_amount:u256,  // to prevent a dos vector
    // minimum_collateral_required:u256 // the option round will not start until this much collateral is deposited

    let tmp = OptionRoundParams {
        current_average_basefee: average_basefee,
        strike_price: in_the_money_strike_price,
        standard_deviation: standard_deviation,
        cap_level: cap_level,
        collateral_level: collateral_level,
        reserve_price: option_reserve_price,
        total_options_available: total_options_available,
        // start_time:timestamp_start_month(),
        option_expiry_time: 'todo'.try_into().unwrap(),
        auction_end_time: week_duration(),
        minimum_collateral_required: 10000,
    };
    return tmp;
}

fn vault_manager() -> ContractAddress {
    contract_address_const::<'vault_manager'>()
}

fn weth_owner() -> ContractAddress {
    contract_address_const::<'weth_owner'>()
}

fn minute_duration() -> u64 {
    60
}

fn hour_duration() -> u64 {
    60 * minute_duration()
}

fn day_duration() -> u64 {
    24 * hour_duration()
}

fn week_duration() -> u64 {
    7 * day_duration()
}

fn month_duration() -> u64 {
    30 * day_duration()
}

fn zero_address() -> ContractAddress {
    contract_address_const::<0>()
}

