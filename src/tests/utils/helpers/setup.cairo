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
                test_accounts::{liquidity_providers_get, option_bidders_get, bystander},
                variables::{weth_owner, week_duration, vault_manager, decimals},
            },
            helpers::event_helpers::{clear_event_logs},
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
fn deploy_vault(vault_type: VaultType) -> IVaultDispatcher {
    let mut calldata = array![];
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

    // Supply eth to test accounts
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
    eth_dispatcher.transfer(bystander(), 100000 * decimals());

    // Clear eth transfer events
    clear_event_logs(array![eth_dispatcher.contract_address]);

    return (VaultFacade { vault_dispatcher }, eth_dispatcher);
}

