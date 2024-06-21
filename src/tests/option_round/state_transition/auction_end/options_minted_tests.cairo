use core::array::ArrayTrait;
use starknet::testing::{set_block_timestamp, set_contract_address};
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};
use pitch_lake_starknet::tests::{
    utils::{
        helpers::{
            accelerators::{
                accelerate_to_auctioning, accelerate_to_running, accelerate_to_running_custom,
                timeskip_and_settle_round, timeskip_and_end_auction
            },
            setup::{setup_facade, setup_test_bidders},
            general_helpers::{create_array_linear, create_array_gradient},
        },
        lib::{
            test_accounts::{
                liquidity_provider_1, option_bidder_buyer_1, option_bidder_buyer_2,
                option_bidder_buyer_3, option_bidder_buyer_4, option_bidder_buyer_5,
                option_bidder_buyer_6, option_bidders_get
            },
            variables::decimals,
        },
        facades::{
            vault_facade::{VaultFacade, VaultFacadeTrait},
            option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait, OptionRoundParams}
        },
    },
};

// @note move these tests to ./src/tests/option_round/state_transition/auction_end_tests
// @note should clean these tests up, one makes no sense, the assertions should lead with options_sold == , not ... == options_sold
// @note should break tests up into options sold tests and options distributed tests

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_1() {
    let (mut vault_facade, _, option_bidders) = setup_test_bidders(2);

    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

    let reserve_price = current_round.get_reserve_price();
    let total_options_available = current_round.get_total_options_available();

    // OB 1 and 2 bid for > the total options available at the reserve price

    let bid_amounts = array![total_options_available / 2, total_options_available / 2 + 1].span();
    let bid_prices = array![reserve_price, reserve_price].span();

    accelerate_to_running_custom(ref vault_facade, option_bidders, bid_amounts, bid_prices);

    // Check total options sold is the total options available
    assert(total_options_available == current_round.total_options_sold(), 'options sold wrong');
}


#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_2() {
    let (mut vault_facade, _, option_bidders) = setup_test_bidders(2);

    // Deposit liquidity and start the auction
    // Make bids
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();
    let total_options_available = current_round.get_total_options_available();

    // OB 1 and 2 bid for > the total options available at the reserve price
    let bid_amounts = array![total_options_available / 2 + 1, total_options_available / 2].span();
    let bid_prices = array![reserve_price, reserve_price + 1].span();

    accelerate_to_running_custom(ref vault_facade, option_bidders, bid_amounts, bid_prices);

    // Check total options sold is the total options available
    assert(total_options_available == current_round.total_options_sold(), 'options sold wrong');
}

// @note This test makes no sense
#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_3() {
    let (mut vault_facade, _, option_bidders) = setup_test_bidders(1);

    // Deposit liquidity and start the auction
    // Make bids
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

    // place bid and end the auction

    let bid_amount = 2;
    let bid_price = current_round.get_reserve_price();

    accelerate_to_running_custom(
        ref vault_facade, option_bidders, array![bid_amount].span(), array![bid_price].span()
    );

    assert(bid_amount == current_round.total_options_sold(), 'options sold wrong')
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_4() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

    // Make no bids
    // Settle auction
    timeskip_and_end_auction(ref vault_facade);

    // Check no options were sold if no bids
    assert(0 == current_round.total_options_sold(), 'no options should sell');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_5() {
    let (mut vault_facade, _, option_bidders) = setup_test_bidders(1);

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();
    let total_options_available = current_round.get_total_options_available();

    // place bid and end the auction

    let bid_amount = total_options_available + 10;
    let bid_price = reserve_price;

    accelerate_to_running_custom(
        ref vault_facade, option_bidders, array![bid_amount].span(), array![bid_price].span()
    );

    // Check all options sell
    assert(
        total_options_available == current_round.total_options_sold(), 'max options should sell'
    );
}


#[test]
#[available_gas(10000000)]
fn test_option_balance_per_bidder_after_auction_1() {
    let number_of_bidders = 4;
    let (mut vault_facade, _, mut option_bidders) = setup_test_bidders(number_of_bidders);

    // Deposit liquidity and start the auction
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

    let reserve_price = current_round.get_reserve_price();
    let total_options_available = current_round.get_total_options_available();

    // Make bids

    let bid_prices = create_array_gradient(reserve_price + 1, 1, number_of_bidders, false).span();

    let bid_amounts = create_array_linear(total_options_available / 3, 4).span();

    // place bids and end the auction
    accelerate_to_running_custom(ref vault_facade, option_bidders, bid_amounts, bid_prices,);

    // Test that each user gets the correct amount of options
    // @dev Using erc20 dispatcher since the option balances are the same as
    // erc20::balance_of()
    let round_facade_erc20 = IERC20Dispatcher {
        contract_address: current_round.contract_address()
    };
    let total_options_created_count: u256 = current_round.total_options_sold();
    let mut options_created = array![];

    loop {
        match option_bidders.pop_front() {
            Option::Some(bidder) => {
                let options = round_facade_erc20.balance_of(*bidder);
                options_created.append(options);
            },
            Option::None => { break; }
        }
    };

    // @dev: getting ENTRYPOINT_NOT_FOUND for this, check

    assert(total_options_created_count == total_options_available, 'options shd match');
    let mut index = 0;
    while index < number_of_bidders {
        if (index == 0) {
            // OB 1 should get 0, since price is OB 2's price
            assert(*options_created[index] == 0, 'Options mismatch')
        } else {
            // All other OBs should get their share of options (1/3 total)
            assert(*options_created[index] == total_options_available / 3, 'Options mismatch')
        }
        index += 1;
    };
}


// test where the total options available have not been exhausted
// @note: make sure the calculation is right
#[test]
#[available_gas(10000000)]
fn test_option_balance_per_bidder_after_auction_2() {
    let number_of_bidders = 6;

    // Deposit liquidity and start the auction
    let (mut vault_facade, _, option_bidders) = setup_test_bidders(number_of_bidders);

   
    // Make bids
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let mut reserve_price = current_round.get_reserve_price();
    let mut total_options_available = current_round.get_total_options_available();

    // Make bids

    total_options_available = 300; //TODO need a better way to mock this
    reserve_price = 2;

    let bid_option_amount_user_1: u256 = 50;
    let bid_price_per_unit_user_1: u256 = 20;

    let bid_option_amount_user_2: u256 = 142;
    let bid_price_per_unit_user_2: u256 = 11;

    let bid_option_amount_user_3: u256 = 235;
    let bid_price_per_unit_user_3: u256 = 11;

    let bid_option_amount_user_4: u256 = 222;
    let bid_price_per_unit_user_4: u256 = 2;

    let bid_option_amount_user_5: u256 = 75;
    let bid_price_per_unit_user_5: u256 = 1;

    let bid_option_amount_user_6: u256 = 35;
    let bid_price_per_unit_user_6: u256 = 1;

    accelerate_to_running_custom(
        ref vault_facade,
        option_bidders,
        array![
            bid_option_amount_user_1,
            bid_option_amount_user_2,
            bid_option_amount_user_3,
            bid_option_amount_user_4,
            bid_option_amount_user_5,
            bid_option_amount_user_6
        ]
            .span(),
        array![
            bid_price_per_unit_user_1,
            bid_price_per_unit_user_2,
            bid_price_per_unit_user_3,
            bid_price_per_unit_user_4,
            bid_price_per_unit_user_5,
            bid_price_per_unit_user_6
        ]
            .span()
    );

    let round_facade_erc20 = IERC20Dispatcher {
        contract_address: current_round.contract_address()
    };
    let total_options_created_count: u256 = current_round.total_options_sold();
    let options_created_user_1_count: u256 = round_facade_erc20.balance_of(*option_bidders[0]);
    let options_created_user_2_count: u256 = round_facade_erc20.balance_of(*option_bidders[1]);
    let options_created_user_3_count: u256 = round_facade_erc20.balance_of(*option_bidders[2]);
    let options_created_user_4_count: u256 = round_facade_erc20.balance_of(*option_bidders[3]);
    let options_created_user_5_count: u256 = round_facade_erc20.balance_of(*option_bidders[4]);
    let options_created_user_6_count: u256 = round_facade_erc20.balance_of(*option_bidders[5]);

    assert(total_options_created_count == 275, 'options shd match');
    assert(options_created_user_1_count == 25, 'options shd match');
    assert(options_created_user_2_count == 71, 'options shd match');
    assert(options_created_user_3_count == 117, 'options shd match');
    assert(options_created_user_4_count == 86, 'options shd match');
    assert(options_created_user_5_count == 0, 'options shd match');
    assert(options_created_user_6_count == 0, 'options shd match');
}

// Test that options sold is 0 pre auction end
#[test]
#[available_gas(10000000)]
fn test_option_round_options_sold_before_auction_end_is_0() {
    let (mut vault_facade, _) = setup_facade();

    // Deposit liquidity and start the auction
    //set_contract_address(vault_manager());
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

    let reserve_price = current_round.get_reserve_price();
    let total_options_available = current_round.get_total_options_available();

    // Make bid
    set_contract_address(option_bidder_buyer_1());
    let bid_amount: u256 = current_round.get_total_options_available() + 10;
    let bid_price: u256 = current_round.get_reserve_price();
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());

    // Check that options_sold is 0 pre auction settlement
    let options_sold: u256 = current_round.total_options_sold();
    // Should be zero as auction has not ended
    assert(options_sold == 0, 'options_sold should be 0');
}
