use pitch_lake_starknet::{
    tests::{
        utils::{
            helpers::{
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_running_custom
                },
                setup::{setup_facade}, general_helpers::{create_array_linear},
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
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait, OptionRoundParams},
            },
        },
    }
};
use starknet::testing::{set_block_timestamp, set_contract_address};

// @note Simplify tests:
// - should have test for when total premiums could be higher if less < total options are sold, but
// could sell all options for less total premiums,
// i.e bidder 1: 1/100 total options @ reserve price & bidder 2: 99/100 total options @ 10x reserve price
// - test same as above but if the not all options could be minted anyway
// i.e bidder1: 1/100 total options @ reserve price & bidder 2: 98/100 total options @ 10x reserve price
// - test when no bids have been placed
// - we have a mock of this in python already in the code base, we should use it to generate values for
// tests
// @note we may consider options being factional (1 option erc20 could have 6-18 decimals, representing
// 1,000,000 gas units. Owning 0.5000... option round tokens represent options for 500,000 gas units).
// Whening doing 1/100 * options available, we should divide with bps, see payout_tests for examples

// Test clearing price is 0 before auction end
#[test]
#[available_gas(10000000)]
fn test_option_round_clearing_price_0_before_auction_end() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity and start the auction
    let total_options_available = accelerate_to_auctioning(ref vault_facade);

    // Bid for option but do not end the auction
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

    //Option Round params

    let reserve_price = current_round.get_reserve_price();

    let bid_amount: u256 = total_options_available;
    let bid_price: u256 = reserve_price;
    // let bid_amount: u256 = bid_count * bid_price;
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Check that clearing price is 0 pre auction end
    let clearing_price = current_round.get_auction_clearing_price();
    assert(clearing_price == 0, 'should be 0 pre auction end');
}

// Test clearing price is the only bid price minting < total options
#[test]
#[available_gas(10000000)]
fn test_clearing_price_1() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);

    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

    let (clearing_price, _) = accelerate_to_running(ref vault_facade);
    // @dev This checks that vault::end_auction returns the clearing price that is set in storage
    assert(clearing_price == current_round.get_auction_clearing_price(), 'clearing price not set');
    assert(clearing_price == current_round.get_reserve_price(), 'clearing price wrong');
}

// Test clearing price is the lower bid price when minting < total options, to mint more
// @note The auction should mint as many options as possible, even if all do not mint,
// even if premiums could be higher selling even fewer ?
// - In this case, the clearing price sells total_options_available - 1 @ reserve price, but could sell
//    total_options_available - 2 @ 10x reserve price ?
#[test]
#[available_gas(10000000)]
fn test_clearing_price_2() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

    let reserve_price = current_round.get_reserve_price();

    let option_bidders = option_bidders_get(2);

    let bid_amount_user_1: u256 = 1;
    let bid_amount_user_2: u256 = current_round.get_total_options_available() - 2;
    let bid_price_user_1: u256 = current_round.get_reserve_price();
    let bid_price_user_2: u256 = current_round.get_reserve_price() * 10;

    let (clearing_price, _) = accelerate_to_running_custom(
        ref vault_facade,
        option_bidders.span(),
        array![bid_amount_user_1, bid_amount_user_2].span(),
        array![bid_price_user_1, bid_price_user_2].span()
    );
    // @dev This tests that vault::end_auction returns the clearing price that gets set
    assert(clearing_price == current_round.get_auction_clearing_price(), 'clearing price not set');
    assert(clearing_price == reserve_price, 'clearing price wrong');
}

// Test clearing price is the higher bid price when able to mint all options
#[test]
#[available_gas(10000000)]
fn test_clearing_price_3() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Two OBs bid for all options with different prices
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

    let reserve_price = current_round.get_reserve_price();
    let total_options_available = current_round.get_total_options_available();

    let option_bidders = option_bidders_get(3);
    let bid_amounts = create_array_linear(total_options_available, 3).span();
    let bid_price_user_1 = reserve_price;
    let bid_price_user_2 = reserve_price + 1;
    let bid_price_user_3 = reserve_price + 2;

    let (clearing_price, _) = accelerate_to_running_custom(
        ref vault_facade,
        option_bidders.span(),
        bid_amounts,
        array![bid_price_user_1, bid_price_user_2, bid_price_user_3].span()
    );
    // OB 3's price should be the clearing price
    assert(clearing_price == bid_price_user_3, 'clearing price wrong');
}


// Test clearing price is the lower bid price in order to mint all of the total options
// @note The auction should mint as many options as possible,
// even if premiums could be higher selling < all ?
// - In this case, the clearing price sells total_options_available @ reserve price, but could sell
//    total_options_available - 1 @ 10x reserve price ?
#[test]
#[available_gas(10000000)]
fn test_clearing_price_4() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity and start the auction
    let total_options_available = accelerate_to_auctioning(ref vault_facade);
    // Two OBs bid for the combined total amount of options, OB 1 outbids OB 2
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

    let reserve_price = current_round.get_reserve_price();

    let option_bidders = option_bidders_get(2);
    let bid_amount_user_1: u256 = 1;
    let bid_amount_user_2: u256 = total_options_available - 1;
    let bid_price_user_1: u256 = reserve_price;
    let bid_price_user_2: u256 = 10 * reserve_price;

    let (clearing_price, _) = accelerate_to_running_custom(
        ref vault_facade,
        option_bidders.span(),
        array![bid_amount_user_1, bid_amount_user_2].span(),
        array![bid_price_user_1, bid_price_user_2].span()
    );
    // OB 1's price should be the clearing price to mint all options
    assert(clearing_price == bid_price_user_1, 'clearing price shd be ob1 price');
}

// Test clearing price is the highest price able to mint the most options
#[test]
#[available_gas(10000000)]
fn test_clearing_price_5() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

    let reserve_price = current_round.get_reserve_price();
    let total_options_available = current_round.get_total_options_available();
    // Three OBs bid for the more than the total amount of options,
    // OB1 outbids OB2, OB2 outbids OB3
    let option_bidders = option_bidders_get(4);

    let bid_price_user_1: u256 = reserve_price + 3;
    let bid_price_user_2: u256 = reserve_price + 2;
    let bid_price_user_3: u256 = reserve_price + 1;
    let bid_price_user_4: u256 = reserve_price;

    let bid_amounts = create_array_linear(total_options_available / 3, 4);

    let (clearing_price, _) = accelerate_to_running_custom(
        ref vault_facade,
        option_bidders.span(),
        bid_amounts.span(),
        array![bid_price_user_1, bid_price_user_2, bid_price_user_3, bid_price_user_4].span()
    );
    // OB3's price will be the clearing price since. Higher would not mint all the options, and less would not optimze premium total
    assert(clearing_price == bid_price_user_3, 'clear price equal reserve price');
}

