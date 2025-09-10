use core::num::traits::Zero;
use core::starknet::SyscallResultTrait;
use openzeppelin_token::erc20::ERC20Component;
use openzeppelin_token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use openzeppelin_utils::serde::SerializedAppend;
use pitch_lake::library::constants::{DAY, HOUR, MINUTE};
use pitch_lake::library::eth::Eth;
use pitch_lake::option_round::contract::OptionRound;
use pitch_lake::option_round::interface::{
    ConstructorArgs as ConstructorArgsOptionRound, IOptionRoundDispatcher,
    IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait,
    OptionRoundState, PricingData,
};
use pitch_lake::tests::option_round::rb_tree::rb_tree_mock_contract::{
    IRBTreeMockContractDispatcher, IRBTreeMockContractDispatcherTrait, RBTreeMockContract,
};
use pitch_lake::tests::utils::facades::option_round_facade::{
    OptionRoundFacade, OptionRoundFacadeTrait,
};
use pitch_lake::tests::utils::facades::vault_facade::{
    VaultFacade, VaultFacadeImpl, VaultFacadeTrait,
};
use pitch_lake::tests::utils::helpers::accelerators::{
    accelerate_to_auctioning, accelerate_to_auctioning_custom, accelerate_to_running,
    accelerate_to_settled,
};
use pitch_lake::tests::utils::helpers::event_helpers::clear_event_logs;
use pitch_lake::tests::utils::helpers::general_helpers::to_wei;
use pitch_lake::tests::utils::lib::test_accounts::{
    bystander, liquidity_providers_get, option_bidders_get, weth_owner,
};
use pitch_lake::tests::utils::lib::variables::{decimals, week_duration};
use pitch_lake::vault::contract::Vault;
use pitch_lake::vault::interface::{
    ConstructorArgs, IVaultDispatcher, IVaultDispatcherTrait, JobRequest, L1Data,
};
use starknet::syscalls::deploy_syscall;
use starknet::testing::{set_block_timestamp, set_contract_address};
use starknet::{ClassHash, ContractAddress, get_block_timestamp, get_contract_address, testing};

// ERC20 Constants
pub const DECIMALS: u8 = 18_u8;
pub const SUPPLY: u256 = 999999999999999999999999999999;

// Vault Constants
pub const ROUND_TRANSITION_DURATION: u64 = 3 * HOUR;
pub const AUCTION_DURATION: u64 = 8 * HOUR;
pub const ROUND_DURATION: u64 = 30 * DAY;
pub const PROVING_DELAY: u64 = 10 * MINUTE;
pub const PROGRAM_ID: felt252 = 'PITCH_LAKE_V1';

pub fn PITCHLAKE_VERIFIER() -> ContractAddress {
    'FOSSIL VERIFIER'.try_into().unwrap()
}

// Deploy eth contract for testing
pub fn deploy_eth() -> ERC20ABIDispatcher {
    let mut calldata = array![];

    calldata.append_serde(1000 * a_lot_of_eth());
    calldata.append_serde(weth_owner());

    let (contract_address, _): (ContractAddress, Span<felt252>) = deploy_syscall(
        Eth::TEST_CLASS_HASH.try_into().unwrap(),
        'some saltt' + get_block_timestamp().into(),
        calldata.span(),
        false,
    )
        .expect('deploy eth failed');

    // Clear the event log
    clear_event_logs(array![contract_address]);
    return ERC20ABIDispatcher { contract_address };
}

// Deploy the vault and fossil client
pub fn deploy_vault_with_events(
    alpha: u128, strike_level: i128, eth_address: ContractAddress,
) -> IVaultDispatcher {
    /// Deploy Vault
    let mut calldata = array![];
    let args = ConstructorArgs {
        verifier_address: PITCHLAKE_VERIFIER(),
        eth_address,
        option_round_class_hash: OptionRound::TEST_CLASS_HASH.try_into().unwrap(),
        alpha, // risk factor for vault
        strike_level, // strike price for r1 is settlement price of r0
        round_transition_duration: ROUND_TRANSITION_DURATION,
        auction_duration: AUCTION_DURATION,
        round_duration: ROUND_DURATION,
        program_id: PROGRAM_ID,
        proving_delay: PROVING_DELAY,
    };
    args.serialize(ref calldata);

    // @dev Making salt timestamp dependent so we can easily deploy new instances for testing
    let now = get_block_timestamp();
    let salt = 'some salt' + now.into();

    let (contract_address, _) = deploy_syscall(
        Vault::TEST_CLASS_HASH.try_into().unwrap(), salt, calldata.span(), true,
    )
        .expect('DEPLOY_VAULT_FAILED');

    return IVaultDispatcher { contract_address };
}

// Deploy the vault and fossil client with events cleared
pub fn deploy_vault(
    alpha: u128, strike_level: i128, eth_address: ContractAddress,
) -> IVaultDispatcher {
    let vault = deploy_vault_with_events(alpha, strike_level, eth_address);

    // Clear the event log
    clear_event_logs(array![vault.contract_address]);

    vault
}

pub fn setup_rb_tree_test() -> IRBTreeMockContractDispatcher {
    let (address, _) = deploy_syscall(
        RBTreeMockContract::TEST_CLASS_HASH.try_into().unwrap(), 0, array![].span(), false,
    )
        .unwrap_syscall();
    IRBTreeMockContractDispatcher { contract_address: address }
}

pub fn to_gwei(amount: u256) -> u256 {
    amount * 1_000_000_000
}

pub fn setup_facade_custom(alpha: u128, strike_level: i128) -> VaultFacade {
    set_block_timestamp(1234567890);

    // Deploy eth
    let eth_dispatcher: ERC20ABIDispatcher = deploy_eth();

    // Deploy vault facade
    let vault_dispatcher: IVaultDispatcher = deploy_vault(
        alpha, strike_level, eth_dispatcher.contract_address,
    );
    let mut vault_facade = VaultFacade { vault_dispatcher };

    // Skip proving delay
    set_block_timestamp(get_block_timestamp() + PROVING_DELAY);

    // Fulfill request to start auction
    let req = vault_facade.get_request_to_start_first_round_serialized();
    let res = vault_facade
        .generate_first_round_result_serialized(
            L1Data { twap: to_gwei(10), max_return: 5000, reserve_price: to_gwei(2) },
        );
    vault_facade.fossil_callback(req, res);

    // @dev Supply eth to liquidity providers and approve vault for transferring eth
    eth_supply_and_approve_all_providers(
        vault_dispatcher.contract_address, eth_dispatcher.contract_address,
    );

    // @dev Supply eth to option buyers and approve current round for transferring eth
    let current_round_address = vault_dispatcher
        .get_round_address(vault_dispatcher.get_current_round_id());
    eth_supply_and_approve_all_bidders(current_round_address, eth_dispatcher.contract_address);

    // Clear eth transfer events
    clear_event_logs(
        array![
            eth_dispatcher.contract_address, vault_facade.contract_address(), current_round_address,
        ],
    );

    return vault_facade;
}

pub fn setup_facade() -> (VaultFacade, ERC20ABIDispatcher) {
    // Deploy vault with 33.33% risk factor and strikes equal to basefee at start
    let mut vault_facade = setup_facade_custom(10_000, 0);
    let eth_dispatcher = ERC20ABIDispatcher { contract_address: vault_facade.get_eth_address() };

    (vault_facade, eth_dispatcher)
}

pub fn setup_test_auctioning_bidders(
    number_of_option_buyers: u32,
) -> (VaultFacade, ERC20ABIDispatcher, Span<ContractAddress>, u256) {
    let (mut vault, eth) = setup_facade();

    // Auction participants
    let mut option_bidders = option_bidders_get(number_of_option_buyers);

    // Start auction
    let total_options_available = accelerate_to_auctioning(ref vault);

    (vault, eth, option_bidders.span(), total_options_available)
}

pub fn setup_test_running() -> (VaultFacade, OptionRoundFacade) {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();

    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);

    (vault, current_round)
}

pub fn setup_test_auctioning_providers(
    number_of_option_buyers: u32, deposit_amounts: Span<u256>,
) -> (VaultFacade, ERC20ABIDispatcher, Span<ContractAddress>, u256) {
    let (mut vault, eth) = setup_facade();
    let mut liquidity_providers = liquidity_providers_get(number_of_option_buyers).span();
    // Amounts to deposit: [100, 200, 300, 400]
    let total_options_available = accelerate_to_auctioning_custom(
        ref vault, liquidity_providers, deposit_amounts,
    );
    (vault, eth, liquidity_providers, total_options_available)
}

//Eth setup helpers

pub fn eth_supply_and_approve_all(
    contract_address: ContractAddress,
    eth_address: ContractAddress,
    addresses: Span<ContractAddress>,
) {
    eth_supply(eth_address, addresses);
    eth_approval(contract_address, eth_address, addresses);
}
pub fn eth_supply_and_approve_all_providers(
    contract_address: ContractAddress, eth_address: ContractAddress,
) {
    let mut liquidity_providers = liquidity_providers_get(6);
    eth_supply_and_approve_all(contract_address, eth_address, liquidity_providers.span());
}

pub fn eth_supply_and_approve_all_bidders(
    contract_address: ContractAddress, eth_address: ContractAddress,
) {
    let option_biddders = option_bidders_get(6);
    eth_supply_and_approve_all(contract_address, eth_address, option_biddders.span());
}

pub fn a_lot_of_eth() -> u256 {
    decimals() * decimals() * decimals() //10^36 ETH
}

pub fn eth_supply(eth_address: ContractAddress, mut receivers: Span<ContractAddress>) {
    let eth_dispatcher = ERC20ABIDispatcher { contract_address: eth_address };
    for receiver in receivers {
        set_contract_address(weth_owner());
        let ob_amount_wei: u256 = a_lot_of_eth();

        eth_dispatcher.transfer(*receiver, ob_amount_wei);
    }
    //loop {
//    match receivers.pop_front() {
//        Option::Some(receiver) => {
//            set_contract_address(weth_owner());
//            let ob_amount_wei: u256 = a_lot_of_eth();

    //            eth_dispatcher.transfer(*receiver, ob_amount_wei);
//        },
//        Option::None => { break; },
//    };
//};
}
pub fn eth_approval(
    contract_address: ContractAddress,
    eth_address: ContractAddress,
    mut approvers: Span<ContractAddress>,
) {
    let eth_dispatcher = ERC20ABIDispatcher { contract_address: eth_address };
    for approver in approvers {
        set_contract_address(weth_owner());
        let ob_amount_wei: u256 = a_lot_of_eth();
        set_contract_address(*approver);
        eth_dispatcher.approve(contract_address, ob_amount_wei);
    }
    //    loop {
//        match approvers.pop_front() {
//            Option::Some(approver) => {
//                set_contract_address(weth_owner());
//                let ob_amount_wei: u256 = a_lot_of_eth();
//                set_contract_address(*approver);
//                eth_dispatcher.approve(contract_address, ob_amount_wei);
//            },
//            Option::None => { break; },
//        };
//    };
}
