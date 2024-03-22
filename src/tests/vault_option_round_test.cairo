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


/// These tests deal with the lifecycle of an option round, from deployment to settlement ///

// Test that round 0 deploys as settled, and round 1 deploys as open
// Test that an option round deploys with state::Open (currently testing mock in vault::constructor,
// will need a test that each option round start sets current to auctioning, and next to open)
#[test]
#[available_gas(10000000)]
fn test_intitial_rounds_after_vault_deployment() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let current_round_id = vault_dispatcher.current_option_round_id();
    let current_round_address = vault_dispatcher.get_option_round_address(current_round_id);
    let current_round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: current_round_address
    };
    let next_round_id = vault_dispatcher.next_option_round_id();
    let next_round_address = vault_dispatcher.get_option_round_address(next_round_id);
    let next_round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: next_round_address
    };
    // Round 0 should be settled
    let mut state: OptionRoundState = current_round_dispatcher.get_option_round_state();
    let mut expected: OptionRoundState = OptionRoundState::Settled;
    assert(expected == state, 'round 0 should be Settled');
    assert(current_round_id == 0, 'current round should be 0');

    // Round 1 should be Open
    state = next_round_dispatcher.get_option_round_state();
    expected = OptionRoundState::Open;
    assert(expected == state, 'round 1 should be Open');
    assert(next_round_id == 1, 'next round should be 1');
}

// deposit_tests: test that right after deployment, LP can deposit into round 1

// Test auction cannot start before the previous round has settled
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'previous round has not settled',))]
fn test_option_round_auction_start_too_early_failure() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Update current round to 1, and next round to 2
    // @dev time jump to auction start time ?
    let mut success: bool = vault_dispatcher.start_next_option_round();
    assert(success, 'auction 1 should have started');
    // Try to start auction before previous round has settled
    success = vault_dispatcher.start_next_option_round();
}

// Test if auction starts and vault::current/next_round pointers are updated.
// @dev this test should be able to start immediately after deployment because
// round 0 deploys as settled, and round 1 deploys as open.
#[test]
#[available_gas(10000000)]
fn test_option_round_auction_start_success() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Start round 1's auction, deploying round 2
    let success: bool = vault_dispatcher.start_next_option_round();
    assert(success, 'auction should have started');
    let current_round_id = vault_dispatcher.current_option_round_id();
    let current_round_address = vault_dispatcher.get_option_round_address(current_round_id);
    let current_round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: current_round_address
    };
    let next_round_id = vault_dispatcher.next_option_round_id();
    let next_round_address = vault_dispatcher.get_option_round_address(next_round_id);
    let next_round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: next_round_address
    };
    // Check round 1 is auctioning
    let mut state: OptionRoundState = current_round_dispatcher.get_option_round_state();
    let mut expectedState: OptionRoundState = OptionRoundState::Auctioning;
    assert(expectedState == state, 'round 1 should be running');
    assert(current_round_id == 1, 'current round should be 1');
    // check round 2 is open
    state = next_round_dispatcher.get_option_round_state();
    expectedState = OptionRoundState::Open;
    assert(expectedState == state, 'round 2 should be open');
    assert(next_round_id == 2, 'next round should be 2');
    // Check that auction start event was emitted with correct total_options_available
    assert_event_auction_start(
        current_round_dispatcher.get_option_round_params().total_options_available
    );
}


// Test that OB cannot refund bids before auction settles
// @note move this into OB test files (state::Settled tests)
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'auction has not ended, cannot claim place_bid deposit',))]
fn test_refund_unused_bids_too_early_failure() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Start auction
    // @dev time jump to auction start time ? 
    let success: bool = vault_dispatcher.start_next_option_round();
    assert(success, 'auction should have started');
    let current_round_id = vault_dispatcher.current_option_round_id();
    let current_round_address = vault_dispatcher.get_option_round_address(current_round_id);
    let current_round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: current_round_address
    };
    // Make bid 
    set_contract_address(option_bidder_buyer_1());
    let option_params: OptionRoundParams = current_round_dispatcher.get_option_round_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;
    current_round_dispatcher.place_bid(bid_amount_user_1, bid_price_user_1);
    // Try to refund bid before auction settles
    current_round_dispatcher.refund_unused_bids(option_bidder_buyer_1());
}

// Test that auction clearing price is 0 pre auction end
#[test]
#[available_gas(10000000)]
fn test_option_round_clearing_price_before_auction_end() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Start auction
    // @dev time jump to auction start time ? 
    let success: bool = vault_dispatcher.start_next_option_round();
    assert(success, 'auction should have started');
    let current_round_id = vault_dispatcher.current_option_round_id();
    let current_round_address = vault_dispatcher.get_option_round_address(current_round_id);
    let current_round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: current_round_address
    };
    // Make bid 
    set_contract_address(option_bidder_buyer_1());
    let option_params: OptionRoundParams = current_round_dispatcher.get_option_round_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;
    current_round_dispatcher.place_bid(bid_amount_user_1, bid_price_user_1);
    // Check that clearing price is 0 pre auction settlement
    let clearing_price = current_round_dispatcher.get_auction_clearing_price();
    assert(clearing_price == 0, 'should be 0 pre auction end');
}

// Test that options sold is 0 pre auction end
#[test]
#[available_gas(10000000)]
fn test_option_round_options_sold_pre_auction_end() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Start auction
    // @dev time jump to auction start time ? 
    let success: bool = vault_dispatcher.start_next_option_round();
    assert(success, 'auction should have started');
    let current_round_id = vault_dispatcher.current_option_round_id();
    let current_round_address = vault_dispatcher.get_option_round_address(current_round_id);
    let current_round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: current_round_address
    };
    // Make bid 
    set_contract_address(option_bidder_buyer_1());
    let option_params: OptionRoundParams = current_round_dispatcher.get_option_round_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;
    current_round_dispatcher.place_bid(bid_amount_user_1, bid_price_user_1);
    // Check that options_sold is 0 pre auction settlement
    let options_sold: u256 = current_round_dispatcher.total_options_sold();
    // Should be zero as auction has not ended
    assert(options_sold == 0, 'options_sold should be 0');
}

// Test that auction clearing price is set post auction end, and state updates to Running
#[test]
#[available_gas(10000000)]
fn test_option_round_settle_auction_success() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Start auction
    // @dev time jump to auction start time ? 
    let success: bool = vault_dispatcher.start_next_option_round();
    assert(success, 'auction should have started');
    let current_round_id = vault_dispatcher.current_option_round_id();
    let current_round_address = vault_dispatcher.get_option_round_address(current_round_id);
    let current_round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: current_round_address
    };
    // Make bid 
    set_contract_address(option_bidder_buyer_1());
    let option_params: OptionRoundParams = current_round_dispatcher.get_option_round_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;
    current_round_dispatcher.place_bid(bid_amount_user_1, bid_price_user_1);
    // Settle auction
    let option_round_params: OptionRoundParams = current_round_dispatcher.get_option_round_params();
    set_block_timestamp(option_round_params.auction_end_time + 1);
    let clearing_price: u256 = current_round_dispatcher.settle_auction();
    assert(clearing_price == 0, 'should be reserve_price');
    // Check that state is Running now, and auction clearing price is set
    let state: OptionRoundState = current_round_dispatcher.get_option_round_state();
    let expectedState: OptionRoundState = OptionRoundState::Running;
    assert(expectedState == state, 'round should be Running');
    // Check auction clearing price event 
    assert_event_auction_settle(current_round_dispatcher.get_auction_clearing_price());
}


// Test that auction cannot be settled twice
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some exrror', 'auction has already settled',))]
fn test_option_round_settle_auction_twice_failure() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Start auction
    // @dev time jump to auction start time ? 
    let success: bool = vault_dispatcher.start_next_option_round();
    assert(success, 'auction should have started');
    let current_round_id = vault_dispatcher.current_option_round_id();
    let current_round_address = vault_dispatcher.get_option_round_address(current_round_id);
    let current_round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: current_round_address
    };
    // Make bid 
    set_contract_address(option_bidder_buyer_1());
    let option_params: OptionRoundParams = current_round_dispatcher.get_option_round_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;
    current_round_dispatcher.place_bid(bid_amount_user_1, bid_price_user_1);
    // Settle auction
    let option_round_params: OptionRoundParams = current_round_dispatcher.get_option_round_params();
    set_block_timestamp(option_round_params.auction_end_time + 1);
    // let success: bool = current_round_dispatcher.settle_auction();
    let clearing_price: u256 = current_round_dispatcher.settle_auction();
    assert(clearing_price == 0, 'auction should have settled');
    // Settle option round
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: current_round_dispatcher.get_market_aggregator().contract_address
    };
    // Spoof settlement price
    // Settlement price is the price of the asset at the time of option expiry (from fossil)
    let option_params: OptionRoundParams = current_round_dispatcher.get_option_round_params();
    mock_maket_aggregator_setter.set_current_base_fee(option_params.reserve_price);
    set_block_timestamp(option_round_params.option_expiry_time + 1);
    let success: bool = current_round_dispatcher.settle_option_round();
    assert(success, 'round should have settled');
    // Settle round
    set_block_timestamp(option_params.auction_end_time + 1);
    current_round_dispatcher.settle_auction();
    current_round_dispatcher.settle_auction();
}


// Test that the round settles 
#[test]
#[available_gas(10000000)]
fn test_option_round_settle_success() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Start auction
    // @dev time jump to auction start time ? 
    let success: bool = vault_dispatcher.start_next_option_round();
    assert(success, 'auction should have started');
    let current_round_id = vault_dispatcher.current_option_round_id();
    let current_round_address = vault_dispatcher.get_option_round_address(current_round_id);
    let current_round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: current_round_address
    };
    // Settle auction
    let option_round_params: OptionRoundParams = current_round_dispatcher.get_option_round_params();
    set_block_timestamp(option_round_params.auction_end_time + 1);
    let clearing_price: u256 = current_round_dispatcher.settle_auction();
    assert(clearing_price == 0, 'auction should have settled');
    // Settle option round
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: current_round_dispatcher.get_market_aggregator().contract_address
    };
    // Spoof settlement price
    // Settlement price is the price of the asset at the time of option expiry (from fossil)
    mock_maket_aggregator_setter.set_current_base_fee(option_round_params.reserve_price);
    set_block_timestamp(option_round_params.option_expiry_time + 1);
    let success: bool = current_round_dispatcher.settle_option_round();
    assert(success, 'round should have settled');
    // Check that state is Settled now, and the settlement price is set
    let state: OptionRoundState = current_round_dispatcher.get_option_round_state();
    let settlement_price: u256 = current_round_dispatcher
        .get_market_aggregator()
        .get_current_base_fee();
    assert(state == OptionRoundState::OptionSettled, 'state should be Settled');
    // Check option settle event
    assert_event_option_settle(settlement_price);
}

// Test that option round cannot be settled twice
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'option has already settled',))]
fn test_option_round_settle_twice_failure() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Start auction
    let success: bool = vault_dispatcher.start_next_option_round();
    // @dev time jump to auction start time ? 
    assert(success, 'auction should have started');
    let current_round_id = vault_dispatcher.current_option_round_id();
    let current_round_address = vault_dispatcher.get_option_round_address(current_round_id);
    let current_round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: current_round_address
    };
    // Settle auction
    let option_round_params: OptionRoundParams = current_round_dispatcher.get_option_round_params();
    set_block_timestamp(option_round_params.auction_end_time + 1);
    let clearing_price: u256 = current_round_dispatcher.settle_auction();
    assert(clearing_price == option_round_params.reserve_price, 'auction should have settled');
    // Settle option round
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: current_round_dispatcher.get_market_aggregator().contract_address
    };
    // Spoof settlement price
    // Settlement price is the price of the asset at the time of option expiry (from fossil)
    mock_maket_aggregator_setter.set_current_base_fee(option_round_params.reserve_price);
    set_block_timestamp(option_round_params.option_expiry_time + 1);
    let success: bool = current_round_dispatcher.settle_option_round();
    assert(success, 'round should have settled');
    // Settle round
    set_block_timestamp(option_round_params.auction_end_time + 1);
    current_round_dispatcher.settle_auction();
    set_block_timestamp(option_round_params.option_expiry_time + 1);

    /// Settle option round twice
    current_round_dispatcher.settle_option_round();
    current_round_dispatcher.settle_option_round();
}


// Test that OB cannot exercise options pre option settlement
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'option has not settled, cannot claim payout',))]
fn test_exercise_options_too_early_failure() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Start auction
    let success: bool = vault_dispatcher.start_next_option_round();
    // @dev time jump to auction start time ? 
    assert(success, 'auction should have started');
    let current_round_id = vault_dispatcher.current_option_round_id();
    let current_round_address = vault_dispatcher.get_option_round_address(current_round_id);
    let current_round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: current_round_address
    };
    // Make bid 
    set_contract_address(option_bidder_buyer_1());
    let option_params: OptionRoundParams = current_round_dispatcher.get_option_round_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;
    current_round_dispatcher.place_bid(bid_amount_user_1, bid_price_user_1);
    // Settle auction
    let option_round_params: OptionRoundParams = current_round_dispatcher.get_option_round_params();
    set_block_timestamp(option_round_params.auction_end_time + 1);
    let clearing_price: u256 = current_round_dispatcher.settle_auction();
    assert(clearing_price == option_params.reserve_price, 'auction should have settled');
    // Should fail as option has not settled
    current_round_dispatcher.exercise_options(option_bidder_buyer_1());
}
// Tests
// @note test that liquidity moves from 1 -> 2 when auction 2 starts
// @note test that LP can submit claim while round 1::running, and when round 1 
// settles, claim is executed.
// @note test that LP can withdraw after round 1 settles, and before round 2 starts 
// (1::settled, 2::open)
// @note test place bid when current.state == Running & Settled (both should fail)
// @note test refund bid when current.state == Running & Settled (both should succeed if there are any to refund)
// @note test refund bid
// @note test combining LP NFTs with locked & unlocked liquidity
// 
// 
// 
// 
// 
/// Old ///
// matt: test was commented out
// when is this callable ? or only for rolling over liq/executing claims ?
// #[test]
// #[available_gas(10000000)]
// #[should_panic(expected: ('Some error', 'auction has not ended, cannot claim premium collected',))]
// fn test_claim_premium_failure() {
//     let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

//     // Add liq. to current round
//     set_contract_address(liquidity_provider_1());
//     let deposit_amount_wei = 10000 * decimals();
//     let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

//     // Start the option round
//     let (option_round_id, _): (u256, OptionRoundParams) = vault_dispatcher.start_new_option_round();

//     // OptionRoundDispatcher
//     let (round_id, option_params) = vault_dispatcher.current_option_round();
//     let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
//         contract_address: vault_dispatcher.option_round_addresses(round_id)
//     };

//     // Make bid
//     let bid_count: u256 = option_params.total_options_available + 10;
//     let bid_price_user_1: u256 = option_params.reserve_price;
//     let bid_amount_user_1: u256 = bid_count * bid_price_user_1;
//     set_contract_address(option_bidder_buyer_1());
//     round_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);

//     // Should fail as auction has not ended
//     round_dispatcher.transfer_premium_collected_to_vault(liquidity_provider_1());
// }

// dont think we need this test anymore, vault will handle transferring liq from current round to next,
// liq never sits in the vault
// #[test]
// #[available_gas(10000000)]
// #[should_panic(expected: ('Some error', 'option has not settled, cannot transfer'))]
// fn test_transfer_to_vault_failure_matt() {
//     let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

//     // Add liq. to current round
//     set_contract_address(liquidity_provider_1());
//     let deposit_amount_wei = 10000 * decimals();
//     let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

//     // Start the option round
//     let (option_round_id, _): (u256, OptionRoundParams) = vault_dispatcher.start_new_option_round();

//     // OptionRoundDispatcher
//     let (round_id, option_params) = vault_dispatcher.current_option_round();
//     let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
//         contract_address: vault_dispatcher.option_round_addresses(round_id)
//     };

//     // Make bid
//     set_contract_address(option_bidder_buyer_1());
//     let bid_count: u256 = option_params.total_options_available + 10;
//     let bid_price_user_1: u256 = option_params.reserve_price;
//     let bid_amount_user_1: u256 = bid_count * bid_price_user_1;
//     round_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);

//     // Settle auction
//     set_block_timestamp(option_params.auction_end_time + 1);
//     round_dispatcher.settle_auction();

//     // Try to withdraw liquidity before option has settled
//     set_contract_address(liquidity_provider_1());
//     vault_dispatcher
//         .withdraw_liquidity(lp_id, deposit_amount_wei); // should fail as option has not settled
// }


