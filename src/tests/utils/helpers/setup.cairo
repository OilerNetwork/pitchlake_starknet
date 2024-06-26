use core::array::ArrayTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, contract_address_try_from_felt252, testing,
    get_block_timestamp, testing::{set_block_timestamp, set_contract_address}
};
use openzeppelin::{
    utils::serde::SerializedAppend,
    token::erc20::{
        ERC20Component,
        interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,}
    }
};
use pitch_lake_starknet::{
    contracts::{
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
    },
    tests::{
        utils::{
            lib::{
                structs::{OptionRoundParams},
                test_accounts::{
                    weth_owner, vault_manager, liquidity_providers_get, option_bidders_get,
                    bystander
                },
                variables::{week_duration, decimals},
            },
            helpers::{
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_auctioning_custom, accelerate_to_running
                },
                event_helpers::{clear_event_logs}
            },
            facades::{
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
                vault_facade::{VaultFacade, VaultFacadeTrait},
            },
            mocks::mock_market_aggregator::{
                MockMarketAggregator, IMarketAggregatorSetterDispatcher,
                IMarketAggregatorSetterDispatcherTrait
            },
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
fn deploy_vault(vault_type: VaultType, eth_address: ContractAddress) -> IVaultDispatcher {
    let mut calldata = array![];
    calldata.append_serde(eth_address);
    calldata.append_serde(vault_manager());
    calldata.append_serde(vault_type);
    calldata.append_serde(deploy_market_aggregator().contract_address); // needed ?
    calldata.append_serde(OptionRound::TEST_CLASS_HASH);
    // @dev Making salt timestamp dependent so we can easily deploy new instances for testing
    let now = get_block_timestamp();
    let salt = 'some salt' + now.into();

    let (contract_address, _) = deploy_syscall(
        Vault::TEST_CLASS_HASH.try_into().unwrap(), salt, calldata.span(), true
    )
        .expect('DEPLOY_VAULT_FAILED');

    // Clear the event log
    clear_event_logs(array![contract_address]);

    return IVaultDispatcher { contract_address };
}

fn deploy_pitch_lake() -> IPitchLakeDispatcher {
    let mut calldata = array![];
    let eth_dispatcher: IERC20Dispatcher = deploy_eth();
    let eth_address = eth_dispatcher.contract_address;

    let ITM: IVaultDispatcher = deploy_vault(VaultType::InTheMoney, eth_address);
    let OTM: IVaultDispatcher = deploy_vault(VaultType::OutOfMoney, eth_address);
    let ATM: IVaultDispatcher = deploy_vault(VaultType::AtTheMoney, eth_address);
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
    let vault_dispatcher: IVaultDispatcher = deploy_vault(
        VaultType::InTheMoney, eth_dispatcher.contract_address
    );

    // Supply eth to test accounts
    let mut liquidity_providers = liquidity_providers_get(5);
    loop {
        match liquidity_providers.pop_front() {
            Option::Some(liquidity_provider) => {
                set_contract_address(weth_owner());
                let lp_amount_wei: u256 = 1000000 * decimals(); // 1,000,000 ETH
                // make the lps as the caller 
                // then call approve, in order to make vault to set bid
                eth_dispatcher.transfer(liquidity_provider, lp_amount_wei);
                set_contract_address(liquidity_provider);
                eth_dispatcher.approve(vault_dispatcher.contract_address, lp_amount_wei);
            },
            Option::None => { break (); },
        };
    };
    let mut option_bidders = option_bidders_get(5);
    loop {
        match option_bidders.pop_front() {
            Option::Some(ob) => {
                set_contract_address(weth_owner());
                let ob_amount_wei: u256 = 100000 * decimals(); // 100,000 ETH

                eth_dispatcher.transfer(ob, ob_amount_wei);
                set_contract_address(ob);
                eth_dispatcher.approve(vault_dispatcher.get_option_round_address(1), ob_amount_wei);
            },
            Option::None => { break; },
        };
    };
    eth_dispatcher.transfer(bystander(), 100000 * decimals());

    // Clear eth transfer events
    clear_event_logs(array![eth_dispatcher.contract_address]);

    return (VaultFacade { vault_dispatcher }, eth_dispatcher);
}

fn deploy_custom_option_round(
    vault_address: ContractAddress,
    option_round_id: u256,
    auction_start_date: u64,
    auction_end_date: u64,
    option_settlement_date: u64,
    reserve_price: u256,
    cap_level: u256,
    strike_price: u256
) -> OptionRoundFacade {
    let mut calldata = array![];
    calldata.append_serde(vault_address);
    calldata.append_serde(option_round_id);
    calldata.append_serde(auction_start_date);
    calldata.append_serde(auction_end_date);
    calldata.append_serde(option_settlement_date);
    calldata.append_serde(reserve_price);
    calldata.append_serde(cap_level);
    calldata.append_serde(strike_price);

    let now = get_block_timestamp();
    let salt = 'some salt' + now.into();

    let (contract_address, _) = deploy_syscall(
        OptionRound::TEST_CLASS_HASH.try_into().unwrap(), salt, calldata.span(), true
    )
        .expect('DEPLOY_VAULT_FAILED');

    // Clear the event log
    clear_event_logs(array![contract_address]);

    OptionRoundFacade { option_round_dispatcher: IOptionRoundDispatcher { contract_address } }
}

fn setup_test_auctioning_bidders(
    number_of_option_buyers: u32
) -> (VaultFacade, IERC20Dispatcher, Span<ContractAddress>, u256) {
    let (mut vault, eth) = setup_facade();

    // Auction participants
    let mut option_bidders = option_bidders_get(number_of_option_buyers);

    // Start auction
    let total_options_available = accelerate_to_auctioning(ref vault);

    (vault, eth, option_bidders.span(), total_options_available)
}

fn setup_test_running() -> (VaultFacade, OptionRoundFacade) {
    let (mut vault, _) = setup_facade();

    accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();
    accelerate_to_running(ref vault);
    (vault, current_round)
}

fn setup_test_auctioning_providers(
    number_of_option_buyers: u32, deposit_amounts: Span<u256>
) -> (VaultFacade, IERC20Dispatcher, Span<ContractAddress>, u256) {
    let (mut vault, eth) = setup_facade();
    let mut liquidity_providers = liquidity_providers_get(number_of_option_buyers).span();
    // Amounts to deposit: [100, 200, 300, 400]
    let total_options_available = accelerate_to_auctioning_custom(
        ref vault, liquidity_providers, deposit_amounts
    );
    (vault, eth, liquidity_providers, total_options_available)
}
