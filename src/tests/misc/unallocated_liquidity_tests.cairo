use pitch_lake_starknet::tests::{
    utils::{
        helpers::{
            accelerators::{
                accelerate_to_auctioning_custom, accelerate_to_running_custom,
                accelerate_to_auctioning, accelerate_to_settled, accelerate_to_running
            },
            general_helpers::{create_array_gradient, create_array_linear,}, setup::{setup_facade},
        },
        lib::{
            test_accounts::{
                liquidity_provider_1, liquidity_provider_2, liquidity_providers_get,
                option_bidder_buyer_1, option_bidder_buyer_2, option_bidders_get,
            },
            variables::{decimals},
        },
        facades::{
            option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            vault_facade::{VaultFacade, VaultFacadeTrait},
        },
        mocks::mock_market_aggregator::{
            MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
            IMarketAggregatorSetterDispatcherTrait
        },
    },
};
// @note Return to this file post clean up to see if tests still needed

// #[test]
// #[available_gas(10000000)]
// fn test_collected_liquidity_does_not_roll_over() {
//     let (mut vault_facade, _) = setup_facade();
//     let mut option_round: OptionRoundFacade = vault_facade.get_next_round();
//     let params = option_round.get_params();
//     accelerate_to_running(ref vault_facade);
//     //Get the total allocated liquidity at this stage

//     let (lp_allocated, _) = vault_facade.get_lp_balance_spread(liquidity_provider_1());
//     // Collect premium
//     // Since no more deposits were made, unallocated is equal to the premiums from the auction

//     let claimable_premiums: u256 = params.total_options_available * params.reserve_price;
//     vault_facade.withdraw(claimable_premiums, liquidity_provider_1());

//     // The round has no more unallocated liquidity because lp withdrew it
//     let unlocked_liqudity_after_premium_claim: u256 = vault_facade.get_total_unlocked();
//     assert(unlocked_liqudity_after_premium_claim == 0, 'premium should not roll over');

//     // Settle option round with no payout
//     accelerate_to_settled(ref vault_facade,params.strike_price - 1);
//     // At this time, remaining liqudity was rolled to the next round (just initial deposit since there is no payout and premiums were collected)
//     let mut next_option_round: OptionRoundFacade = vault_facade.get_next_round();
//     // Check rolled over amount is correct
//     let next_round_unallocated: u256 = next_option_round.total_unallocated_liquidity();
//     assert(next_round_unallocated == lp_allocated, 'Rollover amount wrong');
// }

// Test that uncollected premiums roll over
// #[test]
// #[available_gas(10000000)]
// fn test_remaining_liqudity_rolls_over() {
//     let (mut vault_facade, _) = setup_facade();
//     let mut option_round: OptionRoundFacade = vault_facade.get_next_round();
//     let params = option_round.get_params();
//     accelerate_to_running(ref vault_facade);
//     //Get liquidity balance
//     //@note Will include the premiums is unallocated and the locked deposit in allocated at this stage
//     let (lp_allocated, lp_unallocated) = vault_facade.get_lp_balance_spread(liquidity_provider_1());
//     // Settle option round with no payout
//     IMarketAggregatorSetterDispatcher { contract_address: vault_facade.get_market_aggregator() }
//         .set_current_base_fee(params.strike_price - 1);
//     vault_facade.timeskip_and_settle_round();
//     // At this time, remaining liqudity was rolled to the next round (initial deposit + premiums)
//     let mut next_option_round: OptionRoundFacade = vault_facade.get_next_round();
//     // Check rolled over amount is correct
//     let next_round_unallocated: u256 = next_option_round.total_unallocated_liquidity();
//     assert(next_round_unallocated == lp_allocated + lp_unallocated, 'Rollover amount wrong');
// // }

// #[test]
// #[available_gas(10000000)]
// fn test_premium_collection_ratio_conversion_unallocated_pool_1() {
//     let (mut vault_facade, _) = setup_facade();
//     let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

//     // Deposit liquidity
//     let deposit_amount_wei_1: u256 = 1000 * decimals();
//     let deposit_amount_wei_2: u256 = 10000 * decimals();
//     vault_facade.deposit(deposit_amount_wei_1, liquidity_provider_1());
//     vault_facade.deposit(deposit_amount_wei_2, liquidity_provider_2());

//     let liquidity_providers = liquidity_providers_get(5);
//     let deposit_amounts = create_array_gradient(1000 * decimals(), 1000 * decimals(), 5);
//     let total_options_available (was total_deposts before) = accelerate_to_auctioning_custom(
//         ref vault_facade, liquidity_providers.span(), deposit_amounts.span()
//     );
//     let params = current_round.get_params();
//     // Make bid (ob1)
//     let bid_amount: u256 = params.total_options_available;

//     let option_bidders = option_bidders_get(5);
//     let bid_prices = create_array_linear(params.reserve_price, 5);
//     let bid_amounts = create_array_linear(params.reserve_price * bid_amount, 5);
//     let clearing_price = accelerate_to_running_custom(
//         ref vault_facade, option_bidders.span(), bid_prices.span(), bid_amounts.span()
//     );

//     // Premium comes from unallocated pool
//     let total_collateral: u256 = current_round.total_collateral();
//     let total_premium_to_be_paid: u256 = current_round.get_auction_clearing_price()
//         * current_round.total_options_sold();
//     // LP % of the round
//     // @note Check math is correct/precision is handled (goes for all instances of ratio calculations like this)
//     let ratio_of_liquidity_provider_1: u256 = (vault_facade
//         .get_collateral_balance_for(liquidity_provider_1())
//         * 100)
//         / total_collateral;
//     let ratio_of_liquidity_provider_2: u256 = (vault_facade
//         .get_collateral_balance_for(liquidity_provider_2())
//         * 100)
//         / total_collateral;
//     // LP premiums share
//     let premium_for_liquidity_provider_1: u256 = (ratio_of_liquidity_provider_1
//         * total_premium_to_be_paid)
//         / 100;
//     let premium_for_liquidity_provider_2: u256 = (ratio_of_liquidity_provider_2
//         * total_premium_to_be_paid)
//         / 100;
//     // The actual unallocated balance of the LPs
//     let actual_unallocated_balance_provider_1: u256 = vault_facade
//         .get_unallocated_balance_for(liquidity_provider_1());
//     let actual_unallocated_balance_provider_2: u256 = vault_facade
//         .get_unallocated_balance_for(liquidity_provider_2());

//     assert(
//         actual_unallocated_balance_provider_1 == premium_for_liquidity_provider_1,
//         'premium paid in ratio'
//     );
//     assert(
//         actual_unallocated_balance_provider_2 == premium_for_liquidity_provider_2,
//         'premium paid in ratio'
//     );
// }

// #[test]
// #[available_gas(10000000)]
// fn test_premium_collection_ratio_conversion_unallocated_pool_2() {
//     let (mut vault_facade, _) = setup_facade();
//     let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
//     let params = current_round.get_params();
//     // Deposit liquidity
//     let deposit_amount_wei_1: u256 = 1000 * decimals();
//     vault_facade.deposit(deposit_amount_wei_1, liquidity_provider_1());
//     vault_facade.deposit(deposit_amount_wei_1, liquidity_provider_2());
//     // Make bid
//     vault_facade.start_auction();
//     let bid_amount_user_1: u256 = ((params.total_options_available / 2) + 1) * params.reserve_price;
//     let bid_amount_user_2: u256 = (params.total_options_available / 2) * params.reserve_price;
//     current_round.place_bid(bid_amount_user_1, params.reserve_price, option_bidder_buyer_1());
//     current_round.place_bid(bid_amount_user_2, params.reserve_price, option_bidder_buyer_2());
//     // End auction
//     vault_facade.timeskip_and_end_auction();
//     // Premium comes from unallocated pool
//     let total_collateral: u256 = current_round.total_collateral();
//     let total_premium_to_be_paid: u256 = current_round.get_auction_clearing_price()
//         * current_round.total_options_sold();
//     // LP % of the round
//     let ratio_of_liquidity_provider_1: u256 = (vault_facade
//         .get_collateral_balance_for(liquidity_provider_1())
//         * 100)
//         / total_collateral;
//     let ratio_of_liquidity_provider_2: u256 = (vault_facade
//         .get_collateral_balance_for(liquidity_provider_2())
//         * 100)
//         / total_collateral;
//     // LP premiums share
//     let premium_for_liquidity_provider_1: u256 = (ratio_of_liquidity_provider_1
//         * total_premium_to_be_paid)
//         / 100;
//     let premium_for_liquidity_provider_2: u256 = (ratio_of_liquidity_provider_2
//         * total_premium_to_be_paid)
//         / 100;
//     // The actual unallocated balance of the LPs
//     let actual_unallocated_balance_provider_1: u256 = vault_facade
//         .get_unallocated_balance_for(liquidity_provider_1());
//     let actual_unallocated_balance_provider_2: u256 = vault_facade
//         .get_unallocated_balance_for(liquidity_provider_2());

//     assert(
//         actual_unallocated_balance_provider_1 == premium_for_liquidity_provider_1,
//         'premium paid in ratio'
//     );
//     assert(
//         actual_unallocated_balance_provider_2 == premium_for_liquidity_provider_2,
//         'premium paid in ratio'
//     );
// }


