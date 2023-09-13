use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20,
    IERC20Dispatcher,
    IERC20DispatcherTrait,
    IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait};
use pitch_lake_starknet::option_round::{IOptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundParams, OptionRoundState};

use result::ResultTrait;
use starknet::{
    ClassHash,
    ContractAddress,
    contract_address_const,
    deploy_syscall,
    Felt252TryIntoContractAddress,
    get_contract_address,
    get_block_timestamp, testing::{set_block_timestamp, set_contract_address}
};

use starknet::contract_address::ContractAddressZeroable;
use openzeppelin::utils::serde::SerializedAppend;

use traits::Into;
use traits::TryInto;
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{setup, deployOptionRound, option_round_test_owner, deployVault, allocated_pool_address, unallocated_pool_address, timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2, vault_manager, weth_owner, mock_option_params};

/// TODO fix enum compares


#[test]
#[available_gas(10000000)]
fn test_round_initialized() {
    let round_dispatcher: IOptionRoundDispatcher = deployOptionRound(option_round_test_owner());
    let state:OptionRoundState = round_dispatcher.get_option_round_state();
    // let expectedInitializedValue :OptionRoundState = OptionRoundState::Initialized;
    // assert (expectedInitializedValue == state, "state should be Initialized");
    // assert (expectedInitializedValue == OptionRoundState::Initialized, "state should be Initialized");
}


#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'only owner can start auction',))]
fn test_round_start_auction_failure() {
    let round_dispatcher: IOptionRoundDispatcher = deployOptionRound(option_round_test_owner());
    set_contract_address(liquidity_provider_1());
    round_dispatcher.start_auction(mock_option_params());
}

#[test]
#[available_gas(10000000)]
fn test_round_start_auction_success() {
    let round_dispatcher: IOptionRoundDispatcher = deployOptionRound(option_round_test_owner());
    set_contract_address(option_round_test_owner());
    let success  : bool = round_dispatcher.start_auction(mock_option_params());
    assert(success == true, 'should be able to start');
}

#[test]
#[available_gas(10000000)]
fn test_round_state_started() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei :u256 = 10000 * vault_dispatcher.decimals().into();
    let success:bool = vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);
    let state:OptionRoundState = round_dispatcher.get_option_round_state();
    // assert (state == OptionRoundState::AuctionStarted, "state should be AuctionStarted");
    // round_dispatcher.get
}


#[test]
#[available_gas(10000000)]
fn test_round_state_auction_ended() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * vault_dispatcher.decimals().into();
    let success:bool = vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    round_dispatcher.end_auction();
    let state:OptionRoundState = round_dispatcher.get_option_round_state();
    // assert (state == OptionRoundState::AuctionEnded, "state should be AuctionEnded");

    // round_dispatcher.get
}


#[test]
#[available_gas(10000000)]
fn test_round_state_auction_settled() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * vault_dispatcher.decimals().into();
    let success:bool = vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    round_dispatcher.end_auction();
    set_block_timestamp(option_params.expiry_time);
    round_dispatcher.settle(option_params.reserve_price, ArrayTrait::new());

    let state:OptionRoundState = round_dispatcher.get_option_round_state();
    // assert (state == OptionRoundState::AuctionEnded, "state should be AuctionSettled");

    // round_dispatcher.get
}
