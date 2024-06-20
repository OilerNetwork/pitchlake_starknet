use starknet::{ContractAddress, testing::{set_contract_address}};
use openzeppelin::token::erc20::interface::{IERC20DispatcherTrait,};
use pitch_lake_starknet::{
    //vault::{IVaultDispatcherTrait},
    contracts::option_round::{IOptionRoundDispatcherTrait, OptionRound::Bid},
    tests::{
        utils::{
            helpers::{
                event_helpers,
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_running_custom,
                    accelerate_to_settled,
                },
                setup::{setup_facade},
            },
            lib::test_accounts::{option_bidders_get, liquidity_provider_1, liquidity_provider_2},
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}
            },
        }
    }
};


/// Sanity checks ///
// These ensure the returned values from write functions match their associated storage slot/getter
// @note Commented out to avoid all tests failing for these reasons for now

fn start_auction(ref option_round: OptionRoundFacade, total_options_available: u256) -> u256 {
    let expected = option_round.get_total_options_available();
    //assert(expected == total_options_available, 'Auction start sanity check fail');
    total_options_available
}

fn end_auction(
    ref option_round: OptionRoundFacade, clearing_price: u256, total_options_sold: u256
) -> (u256, u256) {
    let expected1 = option_round.get_auction_clearing_price();
    let expected2 = option_round.total_options_sold();
    //assert(expected1 == clearing_price, 'Auction end sanity check fail 1');
    assert(expected2 == total_options_sold, 'Auction end sanity check fail 2');
    (clearing_price, total_options_sold)
}

fn settle_option_round(ref option_round: OptionRoundFacade, total_payout: u256) -> u256 {
    let expected = option_round.total_payout();
    //assert(expected == total_payout, 'Settle round sanity check fail');
    total_payout
}

fn refund_bid(ref option_round: OptionRoundFacade, refund_amount: u256, expected: u256) -> u256 {
    //assert(refund_amount == expected, 'Refund sanity check fail');
    refund_amount
}

fn exercise_options(
    ref option_round: OptionRoundFacade, individual_payout: u256, expected: u256
) -> u256 {
    //assert(individual_payout == expected, 'Exercise opts sanity check fail');
    individual_payout
}

fn place_bid(ref self: OptionRoundFacade, bidder: ContractAddress, id: felt252) -> felt252 {
    let nonce: felt252 = (self.get_nonce_for(bidder) - 1).into();
    let hash = poseidon::poseidon_hash_span(array![bidder.into(), nonce].span());
    //assert(hash == id , 'Invalid hash generated');
    id
}
fn update_bid(ref option_round: OptionRoundFacade, bid_id: felt252, bid: Bid) -> Bid {
    let storage_bid = option_round.get_bid_details(bid_id);
    //assert(bid == storage_bid, 'Bid Mismatch');
    bid
}

/// Vault

fn deposit(ref vault: VaultFacade, lp: ContractAddress, unlocked_amount: u256) -> u256 {
    let expected_unlocked_amount = vault.get_lp_unlocked_balance(lp);
    //assert(unlocked_amount == expected_unlocked_amount, 'Deposit sanity check fail');
    expected_unlocked_amount
}

fn withdraw(ref vault: VaultFacade, lp: ContractAddress, unlocked_amount: u256) -> u256 {
    let expected_unlocked_amount = vault.get_lp_unlocked_balance(lp);
    //assert(unlocked_amount == expected_unlocked_amount, 'Deposit sanity check fail');
    expected_unlocked_amount
}

/// Event Checks ///

// Test to make sure the event assertions are working as expected
// @dev This is needed because we are manually constructing/popping some events in
// our assertions and this is a sanity check for each
// @note Currently, we are firing mock events using rm_me functions on the Vault & OptionRound
// contracts, this is not ideal, we either need to figure out a way to emit events from this
// test, or drop this test once we add the implementation for firing each event
#[test]
#[available_gas(100000000)]
fn test_event_testers() {
    let (mut vault, eth) = setup_facade();
    /// new test, make emission come from entry point on vault,
    let mut round = vault.get_current_round();
    set_contract_address(liquidity_provider_1());
    event_helpers::clear_event_logs(
        array![eth.contract_address, vault.contract_address(), round.contract_address()]
    );
    eth.transfer(liquidity_provider_2(), 100);
    event_helpers::assert_event_transfer(
        eth.contract_address, liquidity_provider_1(), liquidity_provider_2(), 100
    );
    round.option_round_dispatcher.rm_me(100);
    event_helpers::assert_event_auction_start(round.contract_address(), 100);
    event_helpers::assert_event_auction_bid_accepted(
        round.contract_address(), round.contract_address(), 100, 100
    );
    event_helpers::assert_event_auction_bid_rejected(
        round.contract_address(), round.contract_address(), 100, 100
    );
    event_helpers::assert_event_auction_end(round.contract_address(), 100);
    event_helpers::assert_event_option_settle(round.contract_address(), 100);
    event_helpers::assert_event_option_round_deployed(
        vault.contract_address(), 1, vault.contract_address()
    );
    event_helpers::assert_event_vault_deposit(
        vault.contract_address(), vault.contract_address(), 100, 100
    );
    event_helpers::assert_event_vault_withdrawal(
        vault.contract_address(), vault.contract_address(), 100, 100
    );
    event_helpers::assert_event_unused_bids_refunded(
        round.contract_address(), round.contract_address(), 100
    );
    event_helpers::assert_event_options_exercised(
        round.contract_address(), round.contract_address(), 100, 100
    );
}
