use core::starknet::SyscallResultTrait;
use core::traits::Into;
use core::array::ArrayTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, contract_address_try_from_felt252, testing,
    get_block_timestamp, testing::{set_block_timestamp, set_contract_address}
};
use openzeppelin::{
    utils::serde::SerializedAppend,
    token::erc20::{ERC20Component, interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait,}}
};
use pitch_lake_starknet::{
    types::{StartAuctionParams, OptionRoundState, VaultType}, library::{eth::Eth},
    vault::{contract::Vault, interface::{IVaultDispatcher, IVaultDispatcherTrait}},
    option_round::{
        contract::OptionRound,
        interface::{
            IOptionRoundDispatcher, IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher,
            IOptionRoundSafeDispatcherTrait,
        },
    },
    contracts::{
        pitch_lake::{
            IPitchLakeDispatcher, IPitchLakeSafeDispatcher, IPitchLakeDispatcherTrait, PitchLake,
            IPitchLakeSafeDispatcherTrait
        },
        market_aggregator::{
            MarketAggregator, IMarketAggregator, IMarketAggregatorDispatcher,
            IMarketAggregatorDispatcherTrait, IMarketAggregatorSafeDispatcher,
            IMarketAggregatorSafeDispatcherTrait
        },
    },
    tests::{
        option_round::rb_tree::{
            rb_tree_mock_contract::{
                RBTreeMockContract, IRBTreeMockContractDispatcher,
                IRBTreeMockContractDispatcherTrait
            }
        },
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
fn deploy_eth() -> ERC20ABIDispatcher {
    let mut calldata = array![];

    calldata.append_serde(SUPPLY);
    calldata.append_serde(weth_owner());

    let (contract_address, _): (ContractAddress, Span<felt252>) = deploy_syscall(
        Eth::TEST_CLASS_HASH.try_into().unwrap(), 'some salt', calldata.span(), false
    )
        .unwrap();

    // Clear the event log
    clear_event_logs(array![contract_address]);
    return ERC20ABIDispatcher { contract_address };
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
    calldata.append_serde('rtp');
    calldata.append_serde('art');
    calldata.append_serde('ort');
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
    let eth_dispatcher = deploy_eth();
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

fn setup_rb_tree_test() -> IRBTreeMockContractDispatcher {
    let (address, _) = deploy_syscall(
        RBTreeMockContract::TEST_CLASS_HASH.try_into().unwrap(), 0, array![].span(), false
    )
        .unwrap_syscall();
    IRBTreeMockContractDispatcher { contract_address: address }
}

fn setup_facade() -> (VaultFacade, ERC20ABIDispatcher) {
    let eth_dispatcher: ERC20ABIDispatcher = deploy_eth();
    let vault_dispatcher: IVaultDispatcher = deploy_vault(
        VaultType::InTheMoney, eth_dispatcher.contract_address
    );

    // Supply eth to test accounts and approve vault to transfer lp eth
    eth_supply_and_approve_all_providers(
        vault_dispatcher.contract_address, eth_dispatcher.contract_address
    );

    //Supply and approve option_bidders
    let current_round_address = vault_dispatcher
        .get_option_round_address(vault_dispatcher.current_option_round_id());
    eth_supply_and_approve_all_bidders(current_round_address, eth_dispatcher.contract_address);

    // Supply eth to test accounts and approve option round 1 to spend ob eth
    // Supply bystander with eth and approve vault to transfer eth
    set_contract_address(weth_owner());
    eth_dispatcher.transfer(bystander(), 100000 * decimals());
    set_contract_address(bystander());
    eth_dispatcher.approve(vault_dispatcher.contract_address, 100000 * decimals());

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

    let vault_dispatcher = IVaultDispatcher { contract_address: vault_address };
    eth_supply_and_approve_all_bidders(contract_address, vault_dispatcher.eth_address());
    // Clear the event log
    clear_event_logs(array![contract_address]);

    OptionRoundFacade { option_round_dispatcher: IOptionRoundDispatcher { contract_address } }
}

fn setup_test_auctioning_bidders(
    number_of_option_buyers: u32
) -> (VaultFacade, ERC20ABIDispatcher, Span<ContractAddress>, u256) {
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
) -> (VaultFacade, ERC20ABIDispatcher, Span<ContractAddress>, u256) {
    let (mut vault, eth) = setup_facade();
    let mut liquidity_providers = liquidity_providers_get(number_of_option_buyers).span();
    // Amounts to deposit: [100, 200, 300, 400]
    let total_options_available = accelerate_to_auctioning_custom(
        ref vault, liquidity_providers, deposit_amounts
    );
    (vault, eth, liquidity_providers, total_options_available)
}

//Eth setup helpers

fn eth_supply_and_approve_all(
    contract_address: ContractAddress,
    eth_address: ContractAddress,
    addresses: Span<ContractAddress>
) {
    eth_supply(eth_address, addresses);
    eth_approval(contract_address, eth_address, addresses);
}
fn eth_supply_and_approve_all_providers(
    contract_address: ContractAddress, eth_address: ContractAddress
) {
    let mut liquidity_providers = liquidity_providers_get(6);
    eth_supply_and_approve_all(contract_address, eth_address, liquidity_providers.span());
}

fn eth_supply_and_approve_all_bidders(
    contract_address: ContractAddress, eth_address: ContractAddress
) {
    let option_biddders = option_bidders_get(6);
    eth_supply_and_approve_all(contract_address, eth_address, option_biddders.span());
}

fn eth_supply(eth_address: ContractAddress, mut receivers: Span<ContractAddress>) {
    let eth_dispatcher = ERC20ABIDispatcher { contract_address: eth_address };
    loop {
        match receivers.pop_front() {
            Option::Some(receiver) => {
                set_contract_address(weth_owner());
                let ob_amount_wei: u256 = 100000 * decimals(); // 100,000 ETH

                eth_dispatcher.transfer(*receiver, ob_amount_wei);
            },
            Option::None => { break; },
        };
    };
}
fn eth_approval(
    contract_address: ContractAddress,
    eth_address: ContractAddress,
    mut approvers: Span<ContractAddress>
) {
    let eth_dispatcher = ERC20ABIDispatcher { contract_address: eth_address };
    loop {
        match approvers.pop_front() {
            Option::Some(approver) => {
                set_contract_address(weth_owner());
                let ob_amount_wei: u256 = 100000 * decimals(); // 100,000 ETH

                //Debug
                // let felt_ca: felt252 = contract_address.into();
                // let felt_eth: felt252 = eth_address.into();
                // let app: ContractAddress = *approver;
                // let felt_app: felt252 = app.into();

                set_contract_address(*approver);
                eth_dispatcher.approve(contract_address, ob_amount_wei);
            },
            Option::None => { break; },
        };
    };
}
