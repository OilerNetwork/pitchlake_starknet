use pitch_lake::{
    tests::{
        utils::{
            helpers::{
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_running_custom,
                    timeskip_and_end_auction,
                },
                setup::{setup_facade, setup_test_auctioning_bidders},
                general_helpers::{
                    create_array_linear, create_array_gradient, create_array_gradient_reverse
                },
            },
            lib::{
                test_accounts::{
                    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
                    option_bidder_buyer_4, option_bidders_get,
                },
                variables::{decimals},
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
        },
    }
};
use starknet::testing::{set_block_timestamp, set_contract_address};

// Test clearing price is 0 before auction end
#[test]
#[available_gas(50000000)]
fn test_clearing_price_0_before_auction_end() {
    let (mut vault_facade, _) = setup_facade();
    let total_options_available = accelerate_to_auctioning(ref vault_facade);

    // Place bids but not end auction
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let bid_amount: u256 = total_options_available;
    let bid_price: u256 = current_round.get_reserve_price();
    vault_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());

    // Check that clearing price is 0 before auction end
    let clearing_price = current_round.get_auction_clearing_price();
    assert(clearing_price == 0, 'should be 0 pre auction end');
}

// Test clearing price is 0 if no bids are placed
#[test]
#[available_gas(50000000)]
fn test_clearing_price_is_0_when_no_bids() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);

    // Make no bids and end auction
    let (clearing_price, _) = timeskip_and_end_auction(ref vault_facade);

    // Check clearing price is 0 if no bids were placed
    assert(clearing_price == 0, 'clearing price sold shd be 0');
}

// Test clearing price is the only bid price
#[test]
#[available_gas(50000000)]
fn test_clearing_price_is_only_bid_price() {
    let (mut vault, _) = setup_facade();
    // Deposit liquidity and start the auction
    let total_options_available = accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();

    // Make bid
    let bidder = option_bidders_get(1).span();
    let bid_amount = array![total_options_available].span();
    let bid_price = array![current_round.get_reserve_price() + 1].span();
    let (clearing_price, _) = accelerate_to_running_custom(
        ref vault, bidder, bid_amount, bid_price
    );

    assert(clearing_price == *bid_price[0], 'clearing price wrong');
}

// Test clearing price is max price to sell all options
#[test]
#[available_gas(800000000)]
fn test_clearing_price_is_highest_price_to_sell_all_options() {
    let (mut vault, _) = setup_facade();
    // Deposit liquidity and start the auction
    let total_options_available = accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();

    // Make bids, 4 bidders bid for 1/3 total options each, each bidder outbidding the previous
    // one's price
    let bidders = option_bidders_get(4).span();
    let bid_amounts = create_array_linear(total_options_available / 3 + 1, bidders.len()).span();
    let bid_prices = create_array_gradient(current_round.get_reserve_price(), 1, bidders.len())
        .span();

    let (clearing_price, _) = accelerate_to_running_custom(
        ref vault, bidders, bid_amounts, bid_prices
    );
    // Check that clearing price is the 2nd bid price (max price to sell all options)
    assert(clearing_price == *bid_prices[1], 'clearing price wrong');
}

// Test clearing price is the lowest bid price to sell the most options
// - In this case, the auction sells total_options_available - 1 @ reserve price, but could sell
//    total_options_available - 2 @ 10x reserve price
#[test]
#[available_gas(50000000)]
fn test_clearing_price_is_lowest_price_when_selling_less_than_total_options() {
    let (mut vault_facade, _, option_bidders, _) = setup_test_auctioning_bidders(2);

    // Make bids
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();
    let bid_amounts = array![1, current_round.get_total_options_available() - 2].span();
    let bid_prices = array![reserve_price, 10 * reserve_price].span();

    let (clearing_price, _) = accelerate_to_running_custom(
        ref vault_facade, option_bidders, bid_amounts, bid_prices,
    );

    // Check clearing price is the lowest bid price, to sell the max number of options
    assert(clearing_price == reserve_price, 'clearing price wrong');
}

// Test clearing price is the lowest bid price to sell the most options
// - In this case, the auction sells total_options_available @ reserve price, but could sell
//    total_options_available - 1 @ 10x reserve price
#[test]
#[available_gas(50000000)]
fn test_clearing_price_is_lowest_price_when_selling_total_options() {
    let (mut vault_facade, _, option_bidders, _) = setup_test_auctioning_bidders(2);

    // Make bids
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();
    let bid_amounts = array![1, current_round.get_total_options_available() - 1].span();
    let bid_prices = array![reserve_price, 10 * reserve_price].span();

    let (clearing_price, _) = accelerate_to_running_custom(
        ref vault_facade, option_bidders, bid_amounts, bid_prices,
    );

    // Check clearing price is the lowest bid price, to sell the max number of options
    assert(clearing_price == reserve_price, 'clearing price wrong');
}
// @dev See option_distribution_tests.cairo for real number tests (using python scripts)


