use pitch_lake_starknet::tests::vault_facade::VaultFacadeTrait;
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
    setup_facade, setup_return_mkt_agg, setup_return_mkt_agg_facade, decimals,
    option_round_test_owner, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, vault_manager, weth_owner, mock_option_params,
    assert_event_auction_start, assert_event_auction_settle, assert_event_option_settle
};
use pitch_lake_starknet::tests::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait
};

use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};


/// These tests deal with the lifecycle of an option round, from deployment to settlement ///

/// Constructor Tests ///

// Test the vault's constructor 
#[test]
#[available_gas(10000000)]
fn test_vault_constructor() {
    let (
        vault_facade, _, mkt_agg_dispatcher
    ): (IVaultDispatcher, IERC20Dispatcher, IMarketAggregatorDispatcher) =
        setup_return_mkt_agg();
    let current_round_id = vault_facade.current_option_round_id();
    let next_round_id = current_round_id + 1;
    // Test vault constructor args
    assert(vault_facade.vault_manager() == vault_manager(), 'vault manager incorrect');
    assert(
        vault_facade.get_market_aggregator() == mkt_agg_dispatcher.contract_address,
        'mkt agg incorrect'
    );
    // assert vault type ()
    // Current round should be 0 and next round should be 1
    assert(current_round_id == 0, 'current round should be 0');
    assert(next_round_id == 1, 'next round should be 1');
}

// Test the option round constructor
// Test that round 0 deploys as settled, and round 1 deploys as open.
#[test]
#[available_gas(10000000)]
fn test_option_round_constructor() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();

    let mut next_round_facade: OptionRoundFacade = vault_facade.get_next_round();
    // Round 0 should be settled
    let mut state: OptionRoundState = current_round_facade.get_state();
    let mut expected: OptionRoundState = OptionRoundState::Settled;
    assert(expected == state, 'round 0 should be Settled');

    // Round 1 should be Open
    state = next_round_facade.get_state();
    expected = OptionRoundState::Open;
    assert(expected == state, 'round 1 should be Open');

    // The round's vault & market aggregator addresses should be set
    assert(
        current_round_facade.vault_address() == vault_facade.contract_address(),
        'vault address should be set'
    );
    assert(
        next_round_facade.vault_address() == vault_facade.contract_address(),
        'vault address should be set'
    );
    assert(
        current_round_facade.get_market_aggregator() == vault_facade.get_market_aggregator(),
        'round 0 mkt agg address wrong'
    );
    assert(
        next_round_facade.get_market_aggregator() == vault_facade.get_market_aggregator(),
        'round 1 mkt agg address wrong'
    );
}

// Test that deposits go into the open/next round
// @dev Move this test to deposit tests
#[test]
#[available_gas(10000000)]
fn test_vault_deposits_go_into_the_next_round() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();

    let next_round_id = vault_facade.current_option_round_id() + 1;
    let next_round_address = vault_facade.get_option_round_address(next_round_id);
    // Before deposit balances
    let user_bal_before: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let round_bal_before: u256 = eth_dispatcher.balance_of(next_round_address);
    // LP deposits 10 ETH into the open round (1)
    let deposit_amount_wei: u256 = 10 * decimals();
    // Does deposit need to return an lp id ? or the round the deposit goes into, success bool, or nothing ? 
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // After deposit balances
    let user_bal_after: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let round_bal_after: u256 = eth_dispatcher.balance_of(next_round_address);

    assert(user_bal_before - deposit_amount_wei == user_bal_after, 'user balance incorrect');
    assert(round_bal_before + deposit_amount_wei == round_bal_after, 'round balance incorrect');
}

/// Auction Start Tests ///

// Test an auction starts and the round becomes the current round. Test that the 
// next round is deployed.
#[test]
#[available_gas(10000000)]
fn test_vault_start_auction_success() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1) so its auction can start
    let deposit_amount_wei: u256 = 10 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start round 1's auction
    vault_facade.start_auction();
    // Get the current and next rounds
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let mut next_round_facade: OptionRoundFacade = vault_facade.get_next_round();
    // Check round 1 is auctioning
    let mut state: OptionRoundState = current_round_facade.get_state();
    let mut expectedState: OptionRoundState = OptionRoundState::Auctioning;
    assert(expectedState == state, 'round 1 should be auctioning');
    assert(vault_facade.get_current_round_id() == 1, 'current round should be 1');
    // check round 2 is open
    state = next_round_facade.get_state();
    expectedState = OptionRoundState::Open;
    assert(expectedState == state, 'round 2 should be open');
    // Check that auction start event was emitted with correct total_options_available
    assert_event_auction_start(current_round_facade.get_params().total_options_available);
}

// Test the next auction cannot start if the current round is Auctioning
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Current round is Auctioning', 'ENTRYPOINT_FAILED'))]
fn test_vault_start_auction_while_current_round_Auctioning_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1) so its auction can start
    let deposit_amount_wei: u256 = 10 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // @dev The vault constructor already has the current round (0) settled, so we need to start round 1 first to make it Auctioning.
    // Start round 1 (Auctioning) and deploy round 2 (Open)
    vault_facade.start_auction();
    // LP deposits (into round 2 since 1 is Auctioning)
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Try to start auction 2 before round 1 has settled
    set_contract_address(vault_manager());
    vault_facade.start_auction();
}

// Test that an auction cannot start while the current is Running
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Round is Running', 'ENTRYPOINT_FAILED',))]
fn test_vault_start_auction_while_current_round_Running_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid 
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    set_block_timestamp(option_params.auction_end_time + 1);
    vault_facade.end_auction();
    // Try to start the next auction while the current is Running
    vault_facade.start_auction();
}

// Test that an auction cannot start before the round transition period is over
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Round transition period not over', 'ENTRYPOINT_FAILED',))]
fn test_vault_start_auction_before_round_transition_period_is_over_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid 
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    set_block_timestamp(option_params.auction_end_time + 1);
    vault_facade.end_auction();
    // Settle option round
    set_block_timestamp(option_params.option_expiry_time + 1);
    vault_facade.settle_option_round(liquidity_provider_1());
    // Try to start the next auction before waiting the round transition period
    vault_facade.start_auction();
}

// Test that OB cannot refund bids before auction settles
// @dev move this into auction/bid tests
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('The auction is still on-going', 'ENTRYPOINT_FAILED',))]
fn test_option_round_refund_unused_bids_too_early_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    // Get the current (auctioning) round
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid 
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Try to refund bid before auction settles
    current_round_facade.refund_bid(option_bidder_buyer_1());
}

// Test that auction clearing price is 0 pre auction end
// @dev move to auction/bidding tests
#[test]
#[available_gas(10000000)]
fn test_option_round_clearing_price_is_0_before_auction_end() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    set_contract_address(vault_manager());
    vault_facade.start_auction();
    // Get the current auctioning roun
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid 
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Check that clearing price is 0 pre auction settlement
    let clearing_price = current_round_facade.get_auction_clearing_price();
    assert(clearing_price == 0, 'should be 0 pre auction end');
}

// Test that options sold is 0 pre auction end
// @dev move to auction/bid tests
#[test]
#[available_gas(10000000)]
fn test_option_round_options_sold_before_auction_end_is_0() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    set_contract_address(vault_manager());
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid
    set_contract_address(option_bidder_buyer_1());
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Check that options_sold is 0 pre auction settlement
    let options_sold: u256 = current_round_facade.total_options_sold();
    // Should be zero as auction has not ended
    assert(options_sold == 0, 'options_sold should be 0');
}

/// Auction End Tests /// 

// Test that the auction clearing price is set post auction end, and state updates to Running
#[test]
#[available_gas(10000000)]
fn test_vault_end_auction_success() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    set_contract_address(vault_manager());
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid 
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    let option_round_params: OptionRoundParams = current_round_facade.get_params();
    set_block_timestamp(option_round_params.auction_end_time + 1);
    let clearing_price: u256 = vault_facade.end_auction();
    assert(clearing_price == 0, 'should be reserve_price');
    // Check that state is Running now, and auction clearing price is set
    let state: OptionRoundState = current_round_facade.get_state();
    let expectedState: OptionRoundState = OptionRoundState::Running;
    assert(expectedState == state, 'round should be Running');
    // Check auction clearing price event 
    assert_event_auction_settle(current_round_facade.get_auction_clearing_price());
}

// Test that the auction cannot be ended twice
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('The auction has already been settled', 'ENTRYPOINT_FAILED',))]
fn test_option_round_end_auction_twice_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    set_contract_address(vault_manager());
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid 
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    set_block_timestamp(option_params.auction_end_time + 1);
    vault_facade.end_auction();
    // Try to settle auction a second time
    vault_facade.end_auction();
}

/// Round Settle Tests ///

// Test that the round settles 
#[test]
#[available_gas(10000000)]
fn test_option_round_settle_success() {
    let (mut vault_facade, _, mut mkt_agg) = setup_return_mkt_agg_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid 

    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    let option_round_params: OptionRoundParams = current_round_facade.get_params();
    set_block_timestamp(option_round_params.auction_end_time + 1);
    let clearing_price: u256 = vault_facade.end_auction();
    assert(clearing_price == option_round_params.reserve_price, 'clearing price wrong');
    // Settle option round
    set_block_timestamp(option_round_params.option_expiry_time + 1);
    vault_facade.settle_option_round(liquidity_provider_1());
    // Check that state is Settled now, auction clearing price is set, and the round is still the current round (round transition period just started)
    let state: OptionRoundState = current_round_facade.get_state();
    let settlement_price: u256 = mkt_agg.get_current_base_fee();
    assert(state == OptionRoundState::Settled, 'state should be Settled');
    assert_event_option_settle(settlement_price);
    assert(vault_facade.current_option_round_id() == 1, 'current round should still be 1');
}

// Test that an option round cannot be settled twice
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('option has already settled', 'ENTRYPOINT_FAILED',))]
fn test_option_round_settle_twice_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    set_contract_address(vault_manager());
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid 

    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    let option_round_params: OptionRoundParams = current_round_facade.get_params();
    set_block_timestamp(option_round_params.auction_end_time + 1);
    vault_facade.end_auction();
    // Settle option round
    set_block_timestamp(option_round_params.option_expiry_time + 1);
    vault_facade.settle_option_round(liquidity_provider_1());
    // Try to settle the option round again
    vault_facade.settle_option_round(liquidity_provider_1());
}


// Test that OB cannot exercise options pre option settlement
// Move to auction/bidding tests
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot exercise before round settles ', 'ENTRYPOINT_FAILED',))]
fn test_exercise_options_too_early_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();

    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    set_contract_address(vault_manager());
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid 
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    let option_round_params: OptionRoundParams = current_round_facade.get_params();
    set_block_timestamp(option_round_params.auction_end_time + 1);
    vault_facade.end_auction();
    // Should fail as option has not settled
    current_round_facade.exercise_options(option_bidder_buyer_1());
}
// Tests
// @note test collect premiums & unlocked liq before roll over, should fail if Settled 
// @note test LP can deposit into next always 
// @note test LP can withdraw from next (storage position) when current < Settled (only updates storage position if they already have one in the next round)
// @note test LP can withdraw from next (dynamic) when current == Settled (calculate position value at end of current and update next position/checkpoint)
// @note test that liquidity moves from current -> next when current settles 
// @note test premiums & unlocked liq roll over 
// @note test roll over if LP collects first
// @note test that LP can withdraw from next position ONLY during round transition period
// @note test place bid when current.state == Auctioning. Running & Settled should both should fail
// @note test refund bid when current.state >= Running. Auctioning should fail since bid is locked
// @note test that LP can tokenize current position when current.state >= Running. Auctioning should fail since no premiums yet 
// @note test positionizing rlp tokens while into next round (at any current round state and during round transition period)


