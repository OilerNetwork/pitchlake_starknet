use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait,
    OptionRoundCreated
};
use pitch_lake_starknet::tests::{
    vault::{utils::{accelerate_to_auctioning, accelerate_to_running}},
};
use pitch_lake_starknet::option_round::{OptionRoundParams, OptionRoundState};
use result::ResultTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};

use pitch_lake_starknet::tests::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};
use starknet::contract_address::ContractAddressZeroable;
use openzeppelin::utils::serde::SerializedAppend;

use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{
    setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    zero_address, vault_manager, weth_owner, option_round_contract_address, mock_option_params,
    pop_log, assert_no_events_left, month_duration, setup_return_mkt_agg_facade,
    assert_event_option_settle, assert_event_transfer
};
use pitch_lake_starknet::option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};
use pitch_lake_starknet::tests::mocks::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait,
};
use pitch_lake_starknet::market_aggregator::{
    IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait,
    IMarketAggregatorSafeDispatcher, IMarketAggregatorSafeDispatcherTrait
};

/// helpers
// used ?
fn assert_event_option_created(
    prev_round: ContractAddress,
    new_round: ContractAddress,
    collaterized_amount: u256,
    option_round_params: OptionRoundParams
) {
    let event = pop_log::<OptionRoundCreated>(zero_address()).unwrap();
    assert(event.prev_round == prev_round, 'Invalid prev_round');
    assert(event.new_round == new_round, 'Invalid new_round');
    assert(event.collaterized_amount == collaterized_amount, 'Invalid collaterized_amount');
    assert(event.option_round_params == option_round_params, 'Invalid option_round_params');
    assert_no_events_left(zero_address());
}

// @note move to option_round/state_transition_tests or /option_settle_tests
// Test options cannot settle before expiry date
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'Options cannot settle before expiry',))]
fn test_options_settle_before_expiry_date_failure() {
    let (mut vault_facade, _) = setup_facade();
    // Add liq. to next round
    let deposit_amount_wei = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());

    // Start the option round
    vault_facade.start_auction();

    // OptionRoundDispatcher
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round.get_params();

    // Place bid
    let option_amount: u256 = params.total_options_available;
    let option_price: u256 = params.reserve_price;
    let bid_amount: u256 = option_amount * option_price;
    current_round.place_bid(bid_amount, option_price, option_bidder_buyer_1());

    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    current_round.end_auction();

    // Settle option round before expiry
    set_block_timestamp(params.option_expiry_time - 1);
    vault_facade.settle_option_round(option_bidder_buyer_1());
}

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

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('option has already settled', 'ENTRYPOINT_FAILED',))]
fn test_option_round_settle_twice_failure() {
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
    let option_round_params: OptionRoundParams = current_round_facade.get_params();
    set_block_timestamp(option_round_params.auction_end_time + 1);
    vault_facade.end_auction();
    // Settle option round

    vault_facade.timeskip_and_settle_round();
    // Try to settle the option round again
    vault_facade.timeskip_and_settle_round();
}

// Test current round's remaining liquidity adds to the next round's unallocated when there is no payout, and no premiums collected
#[test]
#[available_gas(10000000)]
fn test_option_round_settle_moves_remaining_liquidity_to_next_round_without_payout_without_premiums_collected() {
    _test_option_round_settle_moves_remaining_liquidity_to_next_round_with_or_without_payout_AND_with_or_without_premiums_collected(
        false, false
    );
}

// Test current round's remaining liquidity adds to the next round's unallocated when there is a payout,
#[test]
#[available_gas(10000000)]
fn test_option_round_settle_moves_remaining_liquidity_to_next_round_with_payout_without_premiums_collected() {
    _test_option_round_settle_moves_remaining_liquidity_to_next_round_with_or_without_payout_AND_with_or_without_premiums_collected(
        true, false
    );
}

// Test current round's remaining liquidity adds to the next round's unallocated when there is no payout, and some premiums collected
#[test]
#[available_gas(10000000)]
fn test_option_round_settle_moves_remaining_liquidity_to_next_round_without_payout_with_premiums_collected() {
    _test_option_round_settle_moves_remaining_liquidity_to_next_round_with_or_without_payout_AND_with_or_without_premiums_collected(
        false, true
    );
}

// Test current round's remaining liquidity adds to the next round's unallocated when there is a payout, and some premiums collected
#[test]
#[available_gas(10000000)]
fn test_option_round_settle_moves_remaining_liquidity_to_next_round_with_payout_with_premiums_collected() {
    _test_option_round_settle_moves_remaining_liquidity_to_next_round_with_or_without_payout_AND_with_or_without_premiums_collected(
        true, true
    );
}

// Internal test function to be called by external tests. Tests the correcnt remaining liquidity transfers to the next round
// and the round & lps collateral/unallocated updates correctly. 
// @dev This internal test can be used to test multiple scenarios (with or without payouts, and with or without lps collecting premiums)
// @note Expand test to having LP1 and 2 deposit into the next round before current settles, will get better coverage

// @note Total collateral will remain fixed at the starting value (for now) in case we need it for conversion rates later
//  - Could have another variable option_round::starting_liquidity if we think setting collateral to 0 makes more sense upon settlement
fn _test_option_round_settle_moves_remaining_liquidity_to_next_round_with_or_without_payout_AND_with_or_without_premiums_collected(
    is_payouts: bool, is_premiums_collected: bool
) {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    // LP2 deposits liquidity into round 1 
    // @dev accelerate_to_auctioning will deposit liquidity into the next round as LP1, so we are matching that deposit
    // for more test coverage (multiple lps)
    // @note Make sure this value matches lp1's deposit in the accelerate_to_auctioning function
    let deposit_amount = 100 * decimals();
    vault_facade.deposit(deposit_amount, liquidity_provider_1());
    // Start auction
    accelerate_to_auctioning(ref vault_facade);
    // End auction, minting all options at reserve price
    accelerate_to_running(ref vault_facade);

    // LP1 does or does not collect their premiums 
    match is_premiums_collected {
        true => vault_facade.collect_premiums(liquidity_provider_1()),
        false => ()
    }

    // ETH balances of rounds before settlement
    let (mut current_round, mut next_round) = vault_facade.get_current_and_next_rounds();
    let current_round_eth_init = eth_dispatcher.balance_of(current_round.contract_address());
    let next_round_eth_init = eth_dispatcher.balance_of(next_round.contract_address());

    // Expected remaining liquidity for the current round after is settles
    let mut expected_remaining_liquidity = current_round.total_collateral()
        + current_round.total_premiums();

    // Expected LP unallocated liquidity after settlement (amount rolled to the next round)
    // @dev LP2's premiums (1/2 the total) rolls over to the next round
    let mut expected_lp2_unallocated = deposit_amount + current_round.total_premiums() / 2;
    // @dev If is_premiums_collected == true, LP1's collects all of their premiums (1/2 the total), thus it does not roll over 
    let mut expected_lp1_unallocated = deposit_amount
        + match is_premiums_collected {
            true => 0,
            false => current_round.total_premiums() / 2
        };

    // If there is a payout, then: the expected remaining liquidity will be reduced by the total payout, 
    // and both LPs share this loss 
    match is_payouts {
        true => {
            expected_remaining_liquidity -= current_round.total_payout();
            expected_lp1_unallocated -= current_round.total_payout() / 2;
            expected_lp2_unallocated -= current_round.total_payout() / 2;
        },
        false => ()
    };

    // If premiums were collected, then the expected remaining liquidity will be reduced by the total collected
    match is_premiums_collected {
        true => expected_remaining_liquidity -= current_round
            .total_unallocated_liquidity_collected(),
        false => ()
    }

    assert(
        expected_remaining_liquidity == expected_lp1_unallocated + expected_lp2_unallocated,
        'remaining liquidity wrong math'
    );
    // Settle option round with or without payout
    vault_facade.settle_option_round_without_payout(is_payouts);
    let remaining_liquidity = current_round.get_remaining_liquidity();

    // LP unallocated and round ETH balances before round settle 
    let (_, lp1_unallocated_final) = vault_facade.get_all_lp_liquidity(liquidity_provider_1());
    let (_, lp2_unallocated_final) = vault_facade.get_all_lp_liquidity(liquidity_provider_2());
    let (_, next_round_unallocated_final) = next_round.get_all_round_liquidity();
    let current_round_eth_final = eth_dispatcher.balance_of(current_round.contract_address());
    let next_round_eth_final = eth_dispatcher.balance_of(next_round.contract_address());

    // Check remaiining liq. -> unallocated for LPs
    assert(remaining_liquidity == expected_remaining_liquidity, 'remaining liquidity incorrect');
    assert(lp1_unallocated_final == expected_lp1_unallocated, 'lp1 unalloc incorrect');
    assert(lp2_unallocated_final == expected_lp2_unallocated, 'lp2 unalloc incorrect');
    assert(next_round_unallocated_final == remaining_liquidity, 'unalloc shd update');
    // Check remaining_liquidity from the current round transfers to the next
    assert(
        current_round_eth_final == current_round_eth_init - remaining_liquidity,
        'current round eth shd dec.'
    );
    assert(
        next_round_eth_final == next_round_eth_init + remaining_liquidity, 'next round eth shd inc.'
    );
    // Assert transfer event
    assert_event_transfer(
        next_round.contract_address(), current_round.contract_address(), remaining_liquidity
    );
}

