use starknet::{
    contract_address_const, ContractAddress, testing::{set_block_timestamp, set_contract_address}
};
use openzeppelin_token::erc20::interface::{ERC20ABIDispatcherTrait,};
use pitch_lake::tests::{
    utils::{
        helpers::{
            accelerators::{
                accelerate_to_auctioning, accelerate_to_auctioning_custom, accelerate_to_running,
                accelerate_to_running_custom, timeskip_and_settle_round, timeskip_and_end_auction,
                //accelerate_to_running_custom_option_round,
            },
            setup::{setup_facade, setup_test_auctioning_bidders},
            general_helpers::{
                pow, to_wei, to_wei_multi, sum_u256_array, create_array_linear,
                create_array_gradient, create_array_gradient_reverse,
                assert_two_arrays_equal_length,
            },
        },
        lib::{
            test_accounts::{
                liquidity_provider_1, option_bidder_buyer_1, option_bidder_buyer_2,
                option_bidder_buyer_3, option_bidder_buyer_4, option_bidder_buyer_5,
                option_bidder_buyer_6, option_bidders_get
            },
            variables::{decimals},
        },
        facades::{
            vault_facade::{VaultFacade, VaultFacadeTrait},
            option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}
        },
    },
};

// Test that options sold is 0 pre auction end
#[test]
#[available_gas(500000000)]
fn test_options_sold_0_before_auction_end() {
    let (mut vault, _) = setup_facade();
    let total_options_available = accelerate_to_auctioning(ref vault);

    // Place bids but not end auction
    let mut current_round: OptionRoundFacade = vault.get_current_round();
    let bid_amount: u256 = total_options_available;
    let bid_price: u256 = current_round.get_reserve_price();
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());

    // Check that options sold is 0 before auction end
    let options_sold = current_round.total_options_sold();
    assert(options_sold == 0, 'should be 0 pre auction end');
}

// Test options sold is 0 if no bids are placed
#[test]
#[available_gas(500000000)]
fn test_options_sold_is_0_when_no_bids() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);

    // Make no bids and end auction
    let (_, options_sold) = timeskip_and_end_auction(ref vault_facade);

    // Check options sold is 0 if no bids were placed
    assert(options_sold == 0, 'options sold sold shd be 0');
}

// Test bidding for more than total options available does not result in more options sold
#[test]
#[available_gas(500000000)]
fn test_bidding_for_more_than_total_options_available() {
    let number_of_option_bidders = 3;
    let (mut vault, _, option_bidders, total_options_available) = setup_test_auctioning_bidders(
        number_of_option_bidders
    );
    let mut current_round = vault.get_current_round();

    // Each option bidder bids for >= the total number of options
    let bid_amounts = create_array_gradient(total_options_available, 1, number_of_option_bidders);
    let bid_prices = create_array_linear(
        current_round.get_reserve_price(), number_of_option_bidders
    );
    accelerate_to_running_custom(ref vault, option_bidders, bid_amounts.span(), bid_prices.span());

    // Check total options sold is the total options available
    assert(current_round.total_options_sold() == total_options_available, 'options sold wrong');
}

// Test bidding for less than total options available at the same price sells the sum of the bids
#[test]
#[available_gas(500000000)]
fn test_bidding_for_less_than_total_options_available() {
    let number_of_option_bidders = 3;
    let (mut vault, _, option_bidders, _) = setup_test_auctioning_bidders(number_of_option_bidders);
    let mut current_round = vault.get_current_round();

    // Each option bidder bids for < the total number of options (combined)
    let bid_amounts = create_array_linear(1, number_of_option_bidders);
    let bid_prices = create_array_linear(
        current_round.get_reserve_price(), number_of_option_bidders
    );
    let (_, options_sold) = accelerate_to_running_custom(
        ref vault, option_bidders, bid_amounts.span(), bid_prices.span(),
    );

    // Check total options sold is the total options available
    assert(options_sold == sum_u256_array(bid_amounts.span()), 'options sold wrong');
}

// Test bidding for less than total options available at different prices sells the sum of the bids
#[test]
#[available_gas(500000000)]
fn test_bidding_for_less_than_total_options_available_different_prices() {
    let number_of_option_bidders = 3;
    let (mut vault, _, option_bidders, _) = setup_test_auctioning_bidders(number_of_option_bidders);
    let mut current_round = vault.get_current_round();

    // Each option bidder bids for < the total number of options (combined)

    let bid_amounts = create_array_linear(1, number_of_option_bidders);
    let bid_prices = create_array_gradient(
        current_round.get_reserve_price(), 1, number_of_option_bidders
    );
    let (_, options_sold) = accelerate_to_running_custom(
        ref vault, option_bidders, bid_amounts.span(), bid_prices.span(),
    );

    // Check total options sold is the total options available
    assert(options_sold == sum_u256_array(bid_amounts.span()), 'options sold wrong');
}

// Test bids with the same amount, higher price are favored in the auction
#[test]
#[available_gas(500000000)]
fn test_bidding_same_amount_higher_price_wins() {
    let number_of_option_bidders = 3;
    let (mut vault, _, mut option_bidders, total_options_available) = setup_test_auctioning_bidders(
        number_of_option_bidders
    );
    let mut current_round = vault.get_current_round();

    // Each bidder bids for the same amount with incrementally higher bids

    let bid_amounts = create_array_linear(total_options_available, number_of_option_bidders);
    let bid_prices = create_array_gradient(
        current_round.get_reserve_price(), 1, number_of_option_bidders
    );
    accelerate_to_running_custom(ref vault, option_bidders, bid_amounts.span(), bid_prices.span());

    // Check last bidder (winner) receives all options, others receive 0
    match option_bidders.pop_back() {
        Option::Some(ob) => {
            let winner_option_balance = current_round.get_mintable_options_for(*ob);
            assert(
                winner_option_balance == total_options_available, 'winner should get all options'
            );
            loop {
                match option_bidders.pop_front() {
                    Option::Some(ob) => {
                        let loser_option_balance = current_round.get_mintable_options_for(*ob);
                        assert(loser_option_balance == 0, 'loser should get no options')
                    },
                    Option::None => { break (); }
                }
            }
        },
        Option::None => { panic!("This shd not revert here") }
    }
}

// Test bids with the same price, the earlier bids are favored in the auction
#[test]
#[available_gas(500000000)]
fn test_bidding_same_price_earlier_bids_win() {
    let number_of_option_bidders = 5;
    let (mut vault, _, mut option_bidders, total_options_available) = setup_test_auctioning_bidders(
        number_of_option_bidders
    );
    let mut current_round = vault.get_current_round();

    // Each bidder bids for the same amount with incrementally higher bids

    let bid_amounts = create_array_gradient(total_options_available, 1, number_of_option_bidders);
    let bid_prices = create_array_linear(
        current_round.get_reserve_price(), number_of_option_bidders
    );
    accelerate_to_running_custom(ref vault, option_bidders, bid_amounts.span(), bid_prices.span());

    // Check first bidder (winner) receives all options, others receive 0
    match option_bidders.pop_front() {
        Option::Some(ob) => {
            let winner_option_balance = current_round.get_mintable_options_for(*ob);
            assert_eq!(winner_option_balance, total_options_available);
            loop {
                match option_bidders.pop_front() {
                    Option::Some(ob) => {
                        let loser_option_balance = current_round.get_mintable_options_for(*ob);
                        assert_eq!(loser_option_balance, 0)
                    },
                    Option::None => { break (); }
                }
            }
        },
        Option::None => { panic!("This shd not revert here") }
    }
}

// Test higher price wins even if losing bidders bid total is higher
#[test]
#[available_gas(500000000)]
fn test_bidding_higher_price_beats_higher_total_bid_amount() {
    let number_of_option_bidders = 3;
    let (mut vault, _, mut option_bidders, total_options_available) = setup_test_auctioning_bidders(
        number_of_option_bidders
    );
    let mut current_round = vault.get_current_round();

    // Each bidder out bids the other's price, but with a lower amount
    // @dev i.e The last bidder bids the highest price, but the other bidders bid a higher total eth
    // (amount * price)

    let bid_amounts = create_array_gradient_reverse(
        total_options_available + 10, 1, number_of_option_bidders
    );
    let bid_prices = create_array_gradient(
        current_round.get_reserve_price(), 1, number_of_option_bidders
    );
    accelerate_to_running_custom(ref vault, option_bidders, bid_amounts.span(), bid_prices.span());
    // Check last bidder (winner) receives all options, others receive 0
    match option_bidders.pop_back() {
        Option::Some(ob) => {
            let winner_option_balance = current_round.get_mintable_options_for(*ob);
            assert(
                winner_option_balance == total_options_available, 'winner should get all options'
            );
            loop {
                match option_bidders.pop_front() {
                    Option::Some(ob) => {
                        let loser_option_balance = current_round.get_mintable_options_for(*ob);
                        assert(loser_option_balance == 0, 'loser should get no options')
                    },
                    Option::None => { break (); }
                }
            }
        },
        Option::None => { panic!("This shd not revert here") }
    }
}

// Test that the last bidder gets the remaining options to be sold
#[test]
#[available_gas(500000000)]
fn test_remaining_bids_go_to_last_bidder() {
    let number_of_option_bidders = 3;
    let (mut vault, _, mut option_bidders, total_options_available) = setup_test_auctioning_bidders(
        number_of_option_bidders
    );
    let mut current_round = vault.get_current_round();

    // Each bidder bids the same price for a portion of the bids
    // the last bidder should get some of their bid amount
    let bid_amounts = array![
        total_options_available / 2, total_options_available / 3, total_options_available / 3
    ]
        .span();
    let bid_prices = create_array_linear(
        current_round.get_reserve_price(), number_of_option_bidders
    )
        .span();
    accelerate_to_running_custom(ref vault, option_bidders, bid_amounts, bid_prices);

    // Check bidder 1 & 2 get their bid amounts, and bidder 3 gets the remaining
    assert(
        current_round.get_mintable_options_for(*option_bidders[0]) == *bid_amounts[0],
        'ob1 wrong option amount'
    );
    assert(
        current_round.get_mintable_options_for(*option_bidders[1]) == *bid_amounts[1],
        'ob2 wrong option amount'
    );
    let remaining_options = total_options_available - (*bid_amounts[0] + *bid_amounts[1]);
    assert(
        current_round.get_mintable_options_for(*option_bidders[2]) == remaining_options,
        'ob3 wrong option amount'
    )
}

// @note Redundant with above tests
//#[test]
//#[available_gas(10000000)]
//fn test_total_options_after_auction_1() {
//    let (mut vault, _) = setup_facade();
//
//    // Deposit liquidity and start the auction
//    accelerate_to_auctioning(ref vault);
//    // Make bids
//    let mut current_round: OptionRoundFacade = vault.get_current_round();
//
//    let reserve_price = current_round.get_reserve_price();
//    let total_options_available = current_round.get_total_options_available();
//
//    // OB 1 and 2 bid for > the total options available at the reserve price
//    let option_bidders = option_bidders_get(2);
//    let bid_amount_1: u256 = total_options_available / 2 + 1;
//    let bid_amount_2: u256 = total_options_available / 2;
//    let bid_price = reserve_price;
//
//    accelerate_to_running_custom(
//        ref vault,
//        option_bidders.span(),
//        array![bid_amount_1, bid_amount_2].span(),
//        array![bid_price, bid_price].span()
//    );
//
//    // Check total options sold is the total options available
//    assert(total_options_available == current_round.total_options_sold(), 'options sold wrong');
//}

// @note Redundant with above tests
//#[test]
//#[available_gas(10000000)]
//fn test_total_options_after_auction_2() {
//    let (mut vault_facade, _) = setup_facade();
//
//    // Deposit liquidity and start the auction
//    let total_options_available = accelerate_to_auctioning(ref vault_facade);
//    // Make bids
//    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
//    let reserve_price = current_round.get_reserve_price();
//    let total_options_available = current_round.get_total_options_available();
//
//    // OB 1 and 2 bid for > the total options available at the reserve price
//    let option_bidders = option_bidders_get(2);
//    let bid_amount_1: u256 = total_options_available / 2 + 1;
//    let bid_amount_2: u256 = total_options_available / 2;
//    let bid_price_1 = reserve_price;
//    let bid_price_2 = reserve_price + 1;
//
//    accelerate_to_running_custom(
//        ref vault_facade,
//        option_bidders.span(),
//        array![bid_amount_1, bid_amount_2].span(),
//        array![bid_price_1, bid_price_2].span()
//    );
//
//    // Check total options sold is the total options available
//    assert(total_options_available == current_round.total_options_sold(), 'options sold wrong');
//}

// Redundant with above test
//#[test]
//#[available_gas(10000000)]
//fn test_total_options_after_auction_3() {
//    let (mut vault_facade, _) = setup_facade();
//
//    // Deposit liquidity and start the auction
//    accelerate_to_auctioning(ref vault_facade);
//    // Make bids
//    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
//
//    let option_bidders = option_bidders_get(1);
//
//    // place bid and end the auction
//    let bid_amount = 2;
//    let bid_price = current_round.get_reserve_price();
//
//    accelerate_to_running_custom(
//        ref vault_facade, option_bidders.span(), array![bid_amount].span(),
//        array![bid_price].span()
//    );
//
//    assert(bid_amount == current_round.total_options_sold(), 'options sold wrong');
//}

// @note Redundant with above test
//#[test]
//#[available_gas(10000000)]
//fn test_total_options_after_auction_5() {
//    let (mut vault_facade, _) = setup_facade();
//
//    // Deposit liquidity and start the auction
//    accelerate_to_auctioning(ref vault_facade);
//    // Make bids
//    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
//    let reserve_price = current_round.get_reserve_price();
//    let total_options_available = current_round.get_total_options_available();
//
//    // place bid and end the auction
//    let option_bidders = option_bidders_get(1);
//
//    let bid_amount = total_options_available + 10;
//    let bid_price = reserve_price;
//
//    accelerate_to_running_custom(
//        ref vault_facade, option_bidders.span(), array![bid_amount].span(),
//        array![bid_price].span()
//    );
//
//    // Check all options sell
//    assert(
//        total_options_available == current_round.total_options_sold(), 'max options should sell'
//    );
//}

// Test that the last bidder gets no options if there are none left
#[test]
#[available_gas(500000000)]
fn test_the_last_bidder_gets_no_options_if_none_left() {
    let number_of_option_bidders = 5;
    let (mut vault_facade, _, mut option_bidders, total_options_available) =
        setup_test_auctioning_bidders(
        number_of_option_bidders
    );
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

    // Make bids, end auction
    let bid_amount = total_options_available / (number_of_option_bidders.into() - 1);
    let bid_amounts = create_array_linear(bid_amount, number_of_option_bidders);
    let bid_prices = create_array_linear(
        current_round.get_reserve_price(), number_of_option_bidders
    );
    accelerate_to_running_custom(
        ref vault_facade, option_bidders, bid_amounts.span(), bid_prices.span()
    );

    // Check that the last bidder gets 0 options, and the rest get the bid amount
    match option_bidders.pop_back() {
        Option::Some(last_bidder) => {
            assert(
                current_round.get_mintable_options_for(*last_bidder) == 0,
                'last bidder shd get 0 options'
            );

            loop {
                match option_bidders.pop_front() {
                    Option::Some(bidder) => {
                        assert(
                            current_round.get_mintable_options_for(*bidder) == bid_amount,
                            'bidder shd get bid amount'
                        );
                    },
                    Option::None => { break (); }
                }
            }
        },
        Option::None => { panic!("This shd not revert here") }
    }
}

// Test losing bidder gets no options
#[test]
#[available_gas(500000000)]
fn test_losing_bid_gets_no_options() {
    let number_of_option_bidders = 5;
    let (mut vault, _, mut option_bidders, total_options_available) = setup_test_auctioning_bidders(
        number_of_option_bidders
    );
    // Deposit liquidity and start the auction
    let mut current_round = vault.get_current_round();

    // Make bids, 5 bidders bid for 1/3 total options each, each bidder outbidding the previous
    // one's price
    let mut bid_amounts = create_array_linear(
        total_options_available / (number_of_option_bidders - 1).into(), option_bidders.len()
    )
        .span();
    let bid_prices = create_array_gradient(
        current_round.get_reserve_price(), 1, option_bidders.len()
    )
        .span();

    accelerate_to_running_custom(ref vault, option_bidders, bid_amounts, bid_prices);

    // Check that the first bidder gets no options, and the rest get their bid amounts
    match option_bidders.pop_front() {
        Option::Some(losing_bidder) => {
            assert(
                current_round.get_mintable_options_for(*losing_bidder) == 0,
                'losing bidder shd get 0 options'
            );
            loop {
                match option_bidders.pop_front() {
                    Option::Some(bidder) => {
                        // @dev Each bidder bids for the same amount so we can use [0] for all here
                        let bid_amount = *bid_amounts[0];
                        assert(
                            current_round.get_mintable_options_for(*bidder) == bid_amount,
                            'bidder should get bid amount'
                        );
                    },
                    Option::None => { break (); }
                }
            }
        },
        Option::None => { panic!("This shd not revert here") }
    }
}


/// Real number tests

// @note These tests require the auction start params struct to be modified to set auction params
// - will spoof caller as vault to do this
// @note Use python script to generate the expected outcomes, verify correct script (1:2), generate
// a few test cases

// Test where the total options available have been exhausted

#[test]
#[available_gas(500000000)]
fn test_option_distribution_real_numbers_1() {
    let (mut vault, _) = setup_facade();
    let options_available = 200;

    let reserve_price = 2;
    let expected_options_sold = 200;
    let bid_amounts = array![50, 142, 235, 222, 75, 35].span();
    let bid_prices = array![20, 11, 11, 2, 1, 1].span();

    let mut expected_option_distribution = array![50, 142, 8, 0, 0, 0].span();

    auction_real_numbers_test_helper(
        ref vault,
        options_available,
        reserve_price,
        bid_amounts,
        bid_prices,
        expected_options_sold,
        expected_option_distribution
    )
}

// Test where the total options available have not been exhausted
#[test]
#[available_gas(500000000)]
fn test_option_distribution_real_numbers_2() {
    let (mut vault, _) = setup_facade();
    let options_available = 200;

    let reserve_price = 2;
    let expected_options_sold = 145;
    let bid_amounts = array![25, 20, 60, 40, 75, 35].span();
    let bid_prices = array![25, 24, 15, 2, 1, 1].span();

    let mut expected_option_distribution = array![25, 20, 60, 40, 0, 0].span();

    auction_real_numbers_test_helper(
        ref vault,
        options_available,
        reserve_price,
        bid_amounts,
        bid_prices,
        expected_options_sold,
        expected_option_distribution
    )
}

#[test]
#[available_gas(500000000)]
fn test_option_distribution_real_numbers_3() {
    let (mut vault, _) = setup_facade();
    let options_available = 500;

    let expected_options_sold = 500;
    let reserve_price: u256 = 2;
    let bid_amounts = array![400, 50, 30, 50, 75, 30].span();
    let bid_prices = array![50, 40, 30, 20, 2, 2].span();

    let mut expected_option_distribution = array![400, 50, 30, 20, 0, 0].span();

    auction_real_numbers_test_helper(
        ref vault,
        options_available,
        reserve_price,
        bid_amounts,
        bid_prices,
        expected_options_sold,
        expected_option_distribution
    )
}

// @note Need to make sure rejected bids do not revert here, switch to using raw calls
fn auction_real_numbers_test_helper(
    ref vault: VaultFacade,
    options_available: u256,
    reserve_price: u256,
    bid_amounts: Span<u256>,
    bid_prices: Span<u256>,
    expected_options_sold: u256,
    mut expected_option_distribution: Span<u256>,
) {
    let mut current_round: OptionRoundFacade = vault.get_current_round();
    let d = current_round.decimals();
    let options_available = to_wei(options_available, d);
    let reserve_price = to_wei(reserve_price, d);
    let bid_amounts = to_wei_multi(bid_amounts, d);
    let bid_prices = to_wei_multi(bid_prices, d);
    let expected_options_sold = to_wei(expected_options_sold, d);
    expected_option_distribution = to_wei_multi(expected_option_distribution, d);

    // Mock values of the option round and start the auction
    current_round.setup_mock_auction(ref vault, options_available, reserve_price);

    // Place bids, ignoring the failed bids
    let bidders = option_bidders_get(bid_amounts.len()).span();
    current_round.place_bids_ignore_errors(bid_amounts, bid_prices, bidders);
    let (_, options_sold) = timeskip_and_end_auction(ref vault);

    // Check that the correct number of options were sold and distributed
    assert(options_sold == expected_options_sold, 'options sold should match');
    let mut option_bidders = option_bidders_get(bid_amounts.len()).span();
    loop {
        match option_bidders.pop_front() {
            Option::Some(bidder) => {
                let options = current_round.get_mintable_options_for(*bidder);
                let expected_options = expected_option_distribution.pop_front().unwrap();
                assert(options == *expected_options, 'options should match');
            },
            Option::None => { break (); }
        }
    }
}

