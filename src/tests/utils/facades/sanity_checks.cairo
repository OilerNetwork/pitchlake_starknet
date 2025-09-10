use pitch_lake::tests::utils::facades::option_round_facade::{
    OptionRoundFacade, OptionRoundFacadeTrait,
};
use pitch_lake::tests::utils::facades::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake::tests::utils::helpers::general_helpers::get_erc20_balance;
use pitch_lake::types::Bid;
use starknet::ContractAddress;


/// Sanity checks ///
// These ensure the returned values from write functions match their associated storage slot/getter
// @note Commented out to avoid all tests failing for these reasons for now

pub fn start_auction(ref option_round: OptionRoundFacade, total_options_available: u256) -> u256 {
    let expected = option_round.get_total_options_available();
    assert(expected == total_options_available, 'Auction start sanity check fail');
    total_options_available
}

pub fn end_auction(
    ref option_round: OptionRoundFacade, clearing_price: u256, total_options_sold: u256,
) -> (u256, u256) {
    let expected1 = option_round.get_auction_clearing_price();
    let expected2 = option_round.total_options_sold();
    assert(expected1 == clearing_price, 'Auction end sanity check fail 1');
    assert(expected2 == total_options_sold, 'Auction end sanity check fail 2');
    (clearing_price, total_options_sold)
}

pub fn settle_option_round(ref option_round: OptionRoundFacade, total_payout: u256) -> u256 {
    let expected = option_round.total_payout();
    assert(expected == total_payout, 'Settle round sanity check fail');
    total_payout
}

pub fn refund_bid(
    ref option_round: OptionRoundFacade, refund_amount: u256, expected: u256,
) -> u256 {
    assert(refund_amount == expected, 'Refund sanity check fail');
    refund_amount
}

pub fn exercise_options(
    ref option_round: OptionRoundFacade, individual_payout: u256, expected: u256,
) -> u256 {
    assert(individual_payout == expected, 'Exercise opts sanity check fail');
    individual_payout
}

pub fn place_bid(ref self: OptionRoundFacade, bid: Bid) -> Bid {
    let nonce: felt252 = (self.get_bidding_nonce_for(bid.owner) - 1).into();
    let expected_id = core::poseidon::poseidon_hash_span(array![bid.owner.into(), nonce].span());
    assert(bid.bid_id == expected_id, 'Invalid hash generated');
    bid
}

pub fn update_bid(ref option_round: OptionRoundFacade, old_bid: Bid, new_bid: Bid) -> Bid {
    let storage_bid = option_round.get_bid_details(old_bid.bid_id);
    assert(new_bid == storage_bid, 'Bid Mismatch');
    new_bid
}

pub fn tokenize_options(
    ref option_round: OptionRoundFacade,
    option_bidder: ContractAddress,
    option_erc20_balance_before: u256,
    options_minted: u256,
) -> u256 {
    let option_erc20_balance_after = get_erc20_balance(
        option_round.contract_address(), option_bidder,
    );
    assert(
        option_erc20_balance_after == option_erc20_balance_before + options_minted,
        'ERC20 Balance Mismatch',
    );
    options_minted
}


/// Vault

pub fn deposit(
    ref vault: VaultFacade, liquidity_provider: ContractAddress, unlocked_amount: u256,
) -> u256 {
    let storage_unlocked_amount = vault.get_lp_unlocked_balance(liquidity_provider);

    assert_eq!(unlocked_amount, storage_unlocked_amount);
    storage_unlocked_amount
}

pub fn withdraw(
    ref vault: VaultFacade, liquidity_provider: ContractAddress, unlocked_amount: u256,
) -> u256 {
    let unlocked_amount_in_storage = vault.get_lp_unlocked_balance(liquidity_provider);
    assert_eq!(unlocked_amount, unlocked_amount_in_storage);
    unlocked_amount_in_storage
}

pub fn claim_queued_liquidity(ref vault: VaultFacade, queued_amount: u256, expected: u256) -> u256 {
    assert!(queued_amount == expected, "Withdraw stashed sanity check fail");
    queued_amount
}
