// @note Moving these tests to option_round/bidding&clearing_price_tests

// test where the total options available have all been sold and there are unused bids which are locked up and can be claimed by the bidders
// @note The test looks redundant with unused bids tests, confirm with Matt
// #[test]
// #[available_gas(10000000)]
// fn test_option_balance_per_bidder_after_auction_3() {
//     let (mut vault_facade, _) = setup_facade();
//     // LP deposits (into round 1)
//     let deposit_amount_wei: u256 = 10000 * decimals();
//     set_contract_address(liquidity_provider_1());
//     vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
//     // Start auction
//     vault_facade.start_auction();
//     let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
//     let mut params: OptionRoundParams = round_facade.get_params();
//     // Make bids
//     params.total_options_available = 200; //TODO  need a better to mock this
//     params.reserve_price = 2;
//     let bid_option_amount_user_1: u256 = 50;
//     let bid_price_per_unit_user_1: u256 = 20;

//     round_facade
//         .place_bid(bid_option_amount_user_1, bid_price_per_unit_user_1, option_bidder_buyer_1());

//     let bid_option_amount_user_2: u256 = 142;
//     let bid_price_per_unit_user_2: u256 = 11;

//     round_facade
//         .place_bid(bid_option_amount_user_2, bid_price_per_unit_user_2, option_bidder_buyer_2());

//     let bid_option_amount_user_3: u256 = 235;
//     let bid_price_per_unit_user_3: u256 = 11;

//     round_facade
//         .place_bid(bid_option_amount_user_3, bid_price_per_unit_user_3, option_bidder_buyer_3());

//     let bid_option_amount_user_4: u256 = 422;
//     let bid_price_per_unit_user_4: u256 = 2;
//     round_facade
//         .place_bid(bid_option_amount_user_4, bid_price_per_unit_user_4, option_bidder_buyer_4());

//     let bid_option_amount_user_5: u256 = 75;
//     let bid_price_per_unit_user_5: u256 = 1;
//     round_facade
//         .place_bid(bid_option_amount_user_5, bid_price_per_unit_user_5, option_bidder_buyer_5());

//     let bid_option_amount_user_6: u256 = 35;
//     let bid_price_per_unit_user_6: u256 = 1;
//     round_facade
//         .place_bid(bid_option_amount_user_6, bid_price_per_unit_user_6, option_bidder_buyer_6());
//     // End auction
//     set_block_timestamp(params.auction_end_time + 1);
//     round_facade.end_auction();
//     // Get options distrubution and OB 3's refund amount
//     let round_facade_erc20 = IERC20Dispatcher { contract_address: round_facade.contract_address() };
//     let total_options_created_count: u256 = round_facade.total_options_sold();
//     let options_created_user_1_count: u256 = round_facade_erc20.balance_of(option_bidder_buyer_1());
//     let options_created_user_2_count: u256 = round_facade_erc20.balance_of(option_bidder_buyer_2());
//     let options_created_user_3_count: u256 = round_facade_erc20.balance_of(option_bidder_buyer_3());
//     let options_created_user_4_count: u256 = round_facade_erc20.balance_of(option_bidder_buyer_4());
//     let options_created_user_5_count: u256 = round_facade_erc20.balance_of(option_bidder_buyer_5());
//     let options_created_user_6_count: u256 = round_facade_erc20.balance_of(option_bidder_buyer_6());
//     let unused_bid_amount_user_3: u256 = round_facade.get_unused_bids_for(option_bidder_buyer_3());
//     // Check correct values
//     assert(total_options_created_count == params.total_options_available, 'options shd match');
//     assert(options_created_user_1_count == 25, 'options shd match');
//     assert(options_created_user_2_count == 71, 'options shd match');
//     assert(options_created_user_3_count == 104, 'options shd match');
//     assert(options_created_user_4_count == 0, 'options shd match');
//     assert(options_created_user_5_count == 0, 'options shd match');
//     assert(options_created_user_6_count == 0, 'options shd match');
//     assert(unused_bid_amount_user_3 == 27, 'unused bid amount shd match');
// }


