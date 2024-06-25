use pitch_lake_starknet::tests::{
    utils::{
        helpers::{
            accelerators::{accelerate_to_running_custom,},
            setup::{setup_facade, deploy_custom_option_round},
            general_helpers::{get_erc20_balance, assert_two_arrays_equal_length},
        },
        lib::{test_accounts::{option_bidders_get},},
        facades::{
            vault_facade::{VaultFacade, VaultFacadeTrait},
            option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait, OptionRoundParams}
        },
    },
};
use starknet::{contract_address_const, testing::{set_block_timestamp}};
// Test options can be tokenized
// Test options cannot be tokenized twice
// Test option balance returns erc20 balance and non tokenized balances

// Internal helper function to deploy custom option round, start auction, place bids,
// then end auction
fn accelerate_to_running_custom_option_round(
    ref vault: VaultFacade,
    total_options_available: u256,
    reserve_price: u256,
    bid_amounts: Span<u256>,
    bid_prices: Span<u256>,
) -> (u256, u256) {
    // Check amounts and prices array lengths are equal
    assert_two_arrays_equal_length(bid_amounts, bid_prices);

    // Deploy custom option round
    let vault_address = contract_address_const::<'vault address'>();
    let auction_start_date: u64 = 1;
    let auction_end_date: u64 = 2;
    let option_settlement_date: u64 = 3;

    let mut option_round = deploy_custom_option_round(
        vault_address,
        1_u256,
        auction_start_date,
        auction_end_date,
        option_settlement_date,
        reserve_price,
        'cap_level',
        'strike price'
    );

    // Start auction
    set_block_timestamp(auction_start_date + 1);
    option_round.start_auction(total_options_available);

    // Make bids
    let number_of_option_bidders = bid_amounts.len();
    let mut option_bidders = option_bidders_get(number_of_option_bidders).span();
    option_round.place_bids(bid_amounts, bid_prices, option_bidders);

    // End auction
    set_block_timestamp(auction_end_date + 1);
    let (clearing_price, options_sold) = option_round.end_auction();
    (clearing_price, options_sold)
}


// Test tokenizing options mints option tokens
#[test]
#[available_gas(10000000)]
fn test_tokenizing_options_mints_option_tokens() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();

    // Start auction with custom auction params
    let options_available = 200;
    let reserve_price = 2;
    let number_of_option_bidders = 6;
    let mut option_bidders = option_bidders_get(number_of_option_bidders).span();
    let bid_amounts = array![50, 142, 235, 222, 75, 35].span();
    let bid_prices = array![20, 11, 11, 2, 1, 1].span();
    accelerate_to_running_custom_option_round(
        ref vault, options_available, reserve_price, bid_amounts, bid_prices
    );

    loop {
        match option_bidders.pop_front() {
            Option::Some(bidder) => {
                // User's option erc20 balance before tokenizing
                let option_erc20_balance_before = get_erc20_balance(
                    current_round.contract_address(), *bidder
                );

                // Tokenize options
                let options_minted = current_round.tokenize_options(*bidder);

                // User's option erc20 balance after tokenizing
                let option_erc20_balance_after = get_erc20_balance(
                    current_round.contract_address(), *bidder
                );

                // Check that the user's erc20 option balance increases by the number of options minted
                assert(
                    option_erc20_balance_after == option_erc20_balance_before + options_minted,
                    'wrong option erc20 balance'
                );
            },
            Option::None => { break (); },
        }
    }
}

// Test user cannot tokenize options again
// @dev This call should not fail, simply do nothing the second time
#[test]
#[available_gas(10000000)]
fn test_tokenizing_options_twice_does_nothing() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();

    // Start auction with custom auction params
    let options_available = 200;
    let reserve_price = 2;
    let number_of_option_bidders = 6;
    let mut option_bidders = option_bidders_get(number_of_option_bidders).span();
    let bid_amounts = array![50, 142, 235, 222, 75, 35].span();
    let bid_prices = array![20, 11, 11, 2, 1, 1].span();
    accelerate_to_running_custom_option_round(
        ref vault, options_available, reserve_price, bid_amounts, bid_prices
    );

    loop {
        match option_bidders.pop_front() {
            Option::Some(bidder) => {
                // User's option erc20 balance before tokenizing
                let option_erc20_balance_before = get_erc20_balance(
                    current_round.contract_address(), *bidder
                );

                // Tokenize options
                let options_minted = current_round.tokenize_options(*bidder);
                // Tokenize again, should do nothing
                current_round.tokenize_options(*bidder);

                // User's option erc20 balance after tokenizing
                let option_erc20_balance_after = get_erc20_balance(
                    current_round.contract_address(), *bidder
                );

                // Check that the user's erc20 option balance increases by the number of options minted
                assert(
                    option_erc20_balance_after == option_erc20_balance_before + options_minted,
                    'wrong option erc20 balance'
                );
            },
            Option::None => { break (); },
        }
    }
}

// Test tokenizing options sets option_balance to 0
// @note Discuss if this is the expected behavior, or if option_balance shd include storage + erc20 balances ?
#[test]
#[available_gas(10000000)]
fn test_tokenizing_options_sets_option_storage_balance_to_0() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();

    // Start auction with custom auction params
    let options_available = 200;
    let reserve_price = 2;
    let number_of_option_bidders = 6;
    let mut option_bidders = option_bidders_get(number_of_option_bidders).span();
    let bid_amounts = array![50, 142, 235, 222, 75, 35].span();
    let bid_prices = array![20, 11, 11, 2, 1, 1].span();
    accelerate_to_running_custom_option_round(
        ref vault, options_available, reserve_price, bid_amounts, bid_prices
    );

    loop {
        match option_bidders.pop_front() {
            Option::Some(bidder) => {
                // Tokenize options
                current_round.tokenize_options(*bidder);

                // Check that the user's option balance in storage is set to 0 (all erc20 now)
                assert(
                    current_round.get_option_balance_for(*bidder) == 0, 'wrong option erc20 balance'
                );
            },
            Option::None => { break (); },
        }
    }
}
// @note Discuss:
// - option_balance_for. Should it just be options in storage ? or also include erc20 options ?
//  - erc20 balance of function will already return option erc20 balance
//  - test_tokenizing_options_sets_option_storage_balance_to_0 shd be modified if behaviro changes

// - should all option tokens be minted at auction end (then sent to owner when tokenized ? or minted upon tokenizing)
//  - later makes most sense to me


