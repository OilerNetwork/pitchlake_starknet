use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait
};
// use pitch_lake_starknet::option_round::{OptionRoundParams, OptionRoundState,};
use pitch_lake_starknet::option_round::{
    OptionRoundParams, OptionRoundState, OptionRound, IOptionRoundDispatcher,
    IOptionRoundDispatcherTrait
};
use pitch_lake_starknet::market_aggregator::{
    IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait,
    IMarketAggregatorSafeDispatcher, IMarketAggregatorSafeDispatcherTrait
};
use result::ResultTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall, SyscallResult,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};

use starknet::contract_address::ContractAddressZeroable;
use openzeppelin::utils::serde::SerializedAppend;

use traits::Into;
use traits::TryInto;
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{
    setup, decimals, option_round_test_owner, deploy_vault, allocated_pool_address,
    unallocated_pool_address, timestamp_start_month, timestamp_end_month, liquidity_provider_1,
    liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2, vault_manager, weth_owner,
    mock_option_params, assert_event_auction_start, assert_event_auction_settle,
    assert_event_option_settle
};
use pitch_lake_starknet::tests::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait
};


/// TODO fix enum compares

#[test]
#[available_gas(10000000)]
fn test_round_initialized() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let (current_round_id, _) = vault_dispatcher.current_option_round();
    // additional setup for first time deploy ? 
    // OptionRoundDispatcher 
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(current_round_id)
    };
    let state: OptionRoundState = round_dispatcher.get_option_round_state();
    let expectedInitializedValue: OptionRoundState = OptionRoundState::Initialized;
// assert(expectedInitializedValue == state, "state should be Initialized");
// assert (expectedInitializedValue == OptionRoundState::Initialized, "state should be Initialized");
}

// add test for proper state of current/next

#[test]
#[available_gas(10000000)]
fn test_round_start_auction_success() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // Add liq. to current round
    let deposit_amount_wei: u256 = 10 * decimals();
    set_contract_address(liquidity_provider_1());
    // todo: consolidate open_liq.. and desosit_liq... into one functions
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round 
    let (option_round_id, option_round_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round_new();

    // OptionRoundDispatcher 
    let (round_id, _) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    let state: OptionRoundState = round_dispatcher.get_option_round_state();
    let expectedState: OptionRoundState = OptionRoundState::AuctionStarted;
// assert(expectedState == state, "auction should be started");
}


#[test]
#[available_gas(10000000)]
fn test_round_clearing_price_pre_auction_end() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // Add liq.
    let deposit_amount_wei: u256 = 10 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round 
    let (option_round_id, option_round_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round_new();

    // OptionRoundDispatcher 
    let (round_id, _) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    let clearing_price: u256 = round_dispatcher.get_auction_clearing_price();
    // Should be 0 as auction has not ended
    assert(clearing_price == 0, 'clearing price should be 0');
    assert_event_auction_start(round_dispatcher.get_option_round_params().total_options_available);
}

#[test]
#[available_gas(10000000)]
fn test_round_option_sold_pre_auction_end() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // Add liq.
    let deposit_amount_wei: u256 = 10 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round 
    let (option_round_id, option_round_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round_new();

    // OptionRoundDispatcher 
    let (round_id, _) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    let options_sold: u256 = round_dispatcher.total_options_sold();
    // Should be zero as auction has not ended
    assert(options_sold == 0, 'options_sold should be 0');
}


// Duplicate of test_round_start_auction_success_new, keeping for now
#[test]
#[available_gas(10000000)]
fn test_round_state_started() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // Add liq. to current round
    // add test for deposit liq when no next round ? or not possible because always only 1 open at a time ? 
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    // todo: consolidate open_liq.. and desosit_liq... into one functions
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round 
    let (option_round_id, option_round_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round_new();

    // OptionRoundDispatcher 
    let (round_id, _) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    let state: OptionRoundState = round_dispatcher.get_option_round_state();
    let expectedState: OptionRoundState = OptionRoundState::AuctionStarted;
    // assert(expectedState == state, "auction should be started");
    assert_event_auction_start(round_dispatcher.get_option_round_params().total_options_available);
}

// matt: AuctionEnded is no longer an enum, only AuctionSettled, duplicating tests for now
#[test]
#[available_gas(10000000)]
fn test_round_state_auction_settled() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // Add liq. to current round
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round
    let (option_round_id, option_round_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round_new();

    // OptionRoundDispatcher
    let (round_id, _) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    set_block_timestamp(option_round_params.auction_end_time + 1);
    round_dispatcher.settle_auction();
    let state: OptionRoundState = round_dispatcher.get_option_round_state();
    // assert(state == OptionRoundState::AuctionSettled, "state should be AuctionEnded");
    assert_event_auction_settle(round_dispatcher.get_auction_clearing_price());
}

#[test]
#[available_gas(10000000)]
fn test_round_state_option_settled() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Add liq. to current round
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round
    let (option_round_id, _): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round_new();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();

    let state: OptionRoundState = round_dispatcher.get_option_round_state();
    set_block_timestamp(option_params.option_expiry_time + 1);

    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: round_dispatcher.get_market_aggregator().contract_address
    };
    mock_maket_aggregator_setter.set_current_base_fee(option_params.reserve_price);

    round_dispatcher.settle_option_round();

    let state: OptionRoundState = round_dispatcher.get_option_round_state();
    let settlement_price: u256 = round_dispatcher.get_market_aggregator().get_current_base_fee();
    // assert(state == OptionRoundState::OptionSettled, "state should be Settled");
    assert_event_option_settle(settlement_price);
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'option has already settled',))]
fn test_round_double_settle_failure() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Add liq. to current round
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round
    let (option_round_id, _): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round_new();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Settle auction
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();
    set_block_timestamp(option_params.option_expiry_time + 1);

    /// Settle option round twice
    round_dispatcher.settle_option_round();
    round_dispatcher.settle_option_round();
}

#[test]
#[available_gas(10000000)]
#[should_panic(
    expected: ('Some error', 'auction has not ended, cannot claim auction_place_bid deposit',)
)]
fn test_refund_unused_bid_deposit_failure_new() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Add liq. to current round
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round
    let (option_round_id, _): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round_new();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Add bid (bid_amount, bid_price)
    set_contract_address(option_bidder_buyer_1());
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;

    round_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);
    // Should fail as auction has not ended
    round_dispatcher.refund_unused_bid_deposit(option_bidder_buyer_1());
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'option has not settled, cannot claim payout',))]
fn test_claim_payout_failure_new() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Add liq. to current round
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round
    let (option_round_id, _): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round_new();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Make bid
    set_contract_address(option_bidder_buyer_1());
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;

    round_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);
    // Should fail as option has not settled
    round_dispatcher.claim_option_payout(option_bidder_buyer_1());
}

// matt: test was commented out
// when is this callable ? or only for rolling over liq/executing claims ?
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'auction has not ended, cannot claim premium collected',))]
fn test_claim_premium_failure() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Add liq. to current round
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round
    let (option_round_id, _): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round_new();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Make bid
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);

    // Should fail as auction has not ended
    round_dispatcher.transfer_premium_collected_to_vault(liquidity_provider_1());
}


// matt: left off hereeee post baja
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'option has not settled, cannot transfer'))]
fn test_transfer_to_vault_failure_matt() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Add liq. to current round
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round
    let (option_round_id, _): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round_new();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Make bid
    set_contract_address(option_bidder_buyer_1());
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;
    round_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);

    // Settle auction
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();

    // Try to withdraw liquidity before option has settled
    set_contract_address(liquidity_provider_1());
    vault_dispatcher
        .withdraw_liquidity(lp_id, deposit_amount_wei); // should fail as option has not settled
}

