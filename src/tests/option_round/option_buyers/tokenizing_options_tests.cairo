use pitch_lake_starknet::{
    types::Errors,
    tests::{
        utils::{
            helpers::{
                accelerators::{
                    accelerate_to_running_custom, accelerate_to_auctioning,
                    timeskip_and_end_auction,
                },
                setup::{setup_facade, deploy_custom_option_round},
                general_helpers::{
                    to_wei, to_wei_multi, get_erc20_balance, assert_two_arrays_equal_length
                },
                event_helpers::{assert_event_options_tokenized, clear_event_logs}
            },
            lib::{test_accounts::{option_bidders_get, option_bidder_buyer_1},},
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait, OptionRoundParams}
            },
        },
    }
};
use starknet::{contract_address_const, ContractAddress, testing::{set_block_timestamp}};

fn test_helper(ref vault: VaultFacade) -> (OptionRoundFacade, Span<ContractAddress>) {
    let mut current_round = vault.get_current_round();
    let d = current_round.decimals();

    // Start auction with custom auction params
    let options_available = to_wei(200, d);
    let reserve_price = to_wei(2, d);
    current_round.setup_mock_auction(ref vault, options_available, reserve_price);

    // Place bids
    let number_of_option_bidders = 6;
    let mut option_bidders = option_bidders_get(number_of_option_bidders).span();
    let bid_amounts = to_wei_multi(array![50, 142, 235, 222, 75, 35].span(), d);
    let bid_prices = to_wei_multi(array![20, 11, 11, 2, 1, 1].span(), d);
    current_round.place_bids_ignore_errors(bid_amounts, bid_prices, option_bidders);
    timeskip_and_end_auction(ref vault);

    (current_round, option_bidders)
}


// Test tokenizing options mints option tokens
#[test]
#[available_gas(500000000)]
fn test_tokenizing_options_mints_option_tokens() {
    let (mut vault, _) = setup_facade();
    let (mut current_round, mut option_bidders) = test_helper(ref vault);

    // Check that tokenizing options mints the correct number of option tokens
    loop {
        match option_bidders.pop_front() {
            Option::Some(bidder) => {
                // User's option erc20 balance before tokenizing
                let option_erc20_balance_before = get_erc20_balance(
                    current_round.contract_address(), *bidder
                );

                // Tokenize options
                let options_minted = current_round.tokenize_options(*bidder);
                assert_event_options_tokenized(
                    current_round.contract_address(), *bidder, options_minted
                );
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

#[test]
#[available_gas(500000000)]
fn test_tokenizing_options_events() {
    let (mut vault, _) = setup_facade();
    let (mut current_round, mut option_bidders) = test_helper(ref vault);

    // Check options tokenized event emits correctly
    clear_event_logs(array![current_round.contract_address()]);
    loop {
        match option_bidders.pop_front() {
            Option::Some(bidder) => {
                // User's option erc20 balance before tokenizing
                // Tokenize options
                let options_minted = current_round.tokenize_options(*bidder);
                assert_event_options_tokenized(
                    current_round.contract_address(), *bidder, options_minted
                );
            // User's option erc20 balance after tokenizing
            },
            Option::None => { break (); },
        }
    }
}

#[test]
#[available_gas(500000000)]
fn test_tokenizing_options_before_auction_end_fails() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let option_bidder = option_bidder_buyer_1();
    let err = Errors::AuctionNotEnded;

    current_round.tokenize_options_expect_error(option_bidder, err);
    accelerate_to_auctioning(ref vault);
    // @note needed ?
    current_round.tokenize_options_expect_error(option_bidder, err);
}


// Test user cannot tokenize options again
// @dev This call should not fail, simply do nothing the second time
#[test]
#[available_gas(500000000)]
fn test_tokenizing_options_twice_does_nothing() {
    let (mut vault, _) = setup_facade();
    let (mut current_round, mut option_bidders) = test_helper(ref vault);

    // Check that tokenizing options twice does nothing for each bidder
    loop {
        match option_bidders.pop_front() {
            Option::Some(bidder) => {
                // Tokenize options
                current_round.tokenize_options(*bidder);

                // User's option erc20 balance before tokenizing again
                let option_erc20_balance_before = get_erc20_balance(
                    current_round.contract_address(), *bidder
                );

                // Tokenize again, should do nothing
                current_round.tokenize_options(*bidder);

                // User's option erc20 balance after tokenizing
                let option_erc20_balance_after = get_erc20_balance(
                    current_round.contract_address(), *bidder
                );

                // Check that the user's erc20 option balance increases by the number of options minted
                assert(
                    option_erc20_balance_after == option_erc20_balance_before,
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
#[available_gas(500000000)]
fn test_tokenizing_options_sets_option_storage_balance_to_0() {
    let (mut vault, _) = setup_facade();
    let (mut current_round, mut option_bidders) = test_helper(ref vault);

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
