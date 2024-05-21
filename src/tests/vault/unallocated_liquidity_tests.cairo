// use array::ArrayTrait;
use debug::PrintTrait;
// use option::OptionTrait;
// use openzeppelin::token::erc20::interface::{
//     IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
//     IERC20SafeDispatcherTrait,
// };
// use pitch_lake_starknet::option_round::{OptionRoundParams};

// use result::ResultTrait;
use starknet::{
    ContractAddressIntoFelt252, contract_address_to_felt252, ClassHash, ContractAddress,
    contract_address_const, deploy_syscall, Felt252TryIntoContractAddress, get_contract_address,
    get_block_timestamp, testing::{set_block_timestamp, set_contract_address}
};

// use starknet::contract_address::ContractAddressZeroable;
// use openzeppelin::utils::serde::SerializedAppend;

// use traits::Into;
// use traits::TryInto;
// use pitch_lake_starknet::eth::Eth;

use pitch_lake_starknet::tests::{
    option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
    vault_facade::{VaultFacade, VaultFacadeTrait}
};
use pitch_lake_starknet::tests::utils::{
    setup_facade, liquidity_provider_1, liquidity_provider_2, liquidity_providers_get, decimals,
    option_bidder_buyer_1, option_bidder_buyer_2, accelerate_to_running, accelerate_to_auctioning,
    accelerate_to_running_partial, create_array_gradient, accelerate_to_auctioning_custom,
    create_array_linear, option_bidders_get,
    accelerate_to_running_custom // , deploy_vault, allocated_pool_address, unallocated_pool_address,
// timestamp_start_month, timestamp_end_month, liquidity_provider_2,
// , option_bidder_buyer_3, option_bidder_buyer_4,
// vault_manager, weth_owner, mock_option_params, assert_event_transfer
};
use pitch_lake_starknet::tests::mocks::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait
};

// Test that collected premiums do not roll over to the next round 

#[test]
#[available_gas(10000000)]
fn test_premiums_and_unsold_liquidity_unallocated_amount() {
    let (mut vault_facade, _) = setup_facade();
    // Accelerate to round 1 running
    accelerate_to_running_partial(ref vault_facade);
    // Current round (running), next round (open)
    let mut current_round = vault_facade.get_current_round();
    let current_params = current_round.get_params();
    // Make deposit into next round
    let deposit_amount = 100 * decimals();
    vault_facade.deposit(deposit_amount, liquidity_provider_1());
    // Amount of premiums earned from the auction (plus unsold liq) for LP 
    let premiums_earned = current_round.total_options_sold()
        * current_params
            .reserve_price; // @dev lp owns 100% of the pool, so 100% of the prmeium is theirs
    // LP unallocated is premiums earned + next round deposits
    let (_, lp_unallocated) = vault_facade.get_all_lp_liquidity(liquidity_provider_1());
    // Withdraw from rewards
    assert(lp_unallocated == premiums_earned + deposit_amount, 'LP unallocated wrong');
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Collect > unallocated balance', 'ENTRYPOINT_FAILED'))]
fn test_collect_more_than_unallocated_balance_failure() {
    let (mut vault_facade, _) = setup_facade();
    // Accelerate to round 1 running
    vault_facade.start_auction();
    // Current round (running), next round (open)
    // Make deposit into next round
    let deposit_amount = 100 * decimals();
    vault_facade.deposit(deposit_amount, liquidity_provider_1());
    // Amount of premiums earned from the auction (plus unsold liq) for LP 
    // @dev lp owns 100% of the pool, so 100% of the prmeium is theirs
    // LP unallocated is premiums earned + next round deposits
    let (_, lp_unallocated) = vault_facade.get_all_lp_liquidity(liquidity_provider_1());
    // Withdraw from rewards
    let collect_amount = lp_unallocated + 1;
    vault_facade.collect_unallocated(collect_amount);
}

#[test]
#[available_gas(10000000)]
fn test_collected_liquidity_does_not_roll_over() {
    let (mut vault_facade, _) = setup_facade();
    let mut option_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = option_round.get_params();
    accelerate_to_running(ref vault_facade);
    //Get the total allocated liquidity at this stage

    let (lp_allocated, _) = vault_facade.get_all_lp_liquidity(liquidity_provider_1());
    // Collect premium 
    // Since no more deposit is made unallocated is equal to the premiums from the auction

    let claimable_premiums: u256 = params.total_options_available * params.reserve_price;
    vault_facade.collect_unallocated(claimable_premiums);

    // The round has no more unallocated liquidity because lp withdrew it
    let unallocated_liqudity_after_premium_claim: u256 = option_round.total_unallocated_liquidity();
    assert(unallocated_liqudity_after_premium_claim == 0, 'premium should not roll over');

    // Settle option round with no payout
    IMarketAggregatorSetterDispatcher { contract_address: vault_facade.get_market_aggregator() }
        .set_current_base_fee(params.strike_price - 1);
    vault_facade.timeskip_and_settle_round();
    // At this time, remaining liqudity was rolled to the next round (just initial deposit since there is no payout and premiums were collected)
    let mut next_option_round: OptionRoundFacade = vault_facade.get_next_round();
    // Check rolled over amount is correct
    let next_round_unallocated: u256 = next_option_round.total_unallocated_liquidity();
    assert(next_round_unallocated == lp_allocated, 'Rollover amount wrong');
}

// Test that uncollected premiums roll over
#[test]
#[available_gas(10000000)]
fn test_remaining_liqudity_rolls_over() {
    let (mut vault_facade, _) = setup_facade();
    let mut option_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = option_round.get_params();
    accelerate_to_running(ref vault_facade);
    //Get liquidity balance
    //@note Will include the premiums is unallocated and the locked deposit in allocated at this stage
    let (lp_allocated, lp_unallocated) = vault_facade.get_all_lp_liquidity(liquidity_provider_1());
    // Settle option round with no payout
    IMarketAggregatorSetterDispatcher { contract_address: vault_facade.get_market_aggregator() }
        .set_current_base_fee(params.strike_price - 1);
    vault_facade.timeskip_and_settle_round();
    // At this time, remaining liqudity was rolled to the next round (initial deposit + premiums)
    let mut next_option_round: OptionRoundFacade = vault_facade.get_next_round();
    // Check rolled over amount is correct
    let next_round_unallocated: u256 = next_option_round.total_unallocated_liquidity();
    assert(next_round_unallocated == lp_allocated + lp_unallocated, 'Rollover amount wrong');
}

#[test]
#[available_gas(10000000)]
fn test_premium_collection_ratio_conversion_unallocated_pool_1() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

    // Deposit liquidity
    let deposit_amount_wei_1: u256 = 1000 * decimals();
    let deposit_amount_wei_2: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei_1, liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei_2, liquidity_provider_2());

    let lps = liquidity_providers_get(5);
    let deposit_amounts = create_array_gradient(1000 * decimals(), 1000 * decimals(), 5);
    let deposit_total = accelerate_to_auctioning_custom(
        ref vault_facade, lps.span(), deposit_amounts.span()
    );
    let params = current_round.get_params();
    // Make bid (ob1)
    let bid_amount: u256 = params.total_options_available;

    let obs = option_bidders_get(5);
    let bid_prices = create_array_linear(params.reserve_price, 5);
    let bid_amounts = create_array_linear(params.reserve_price * bid_amount, 5);
    let clearing_price = accelerate_to_running_custom(
        ref vault_facade, obs.span(), bid_prices.span(), bid_amounts.span()
    );

    // Premium comes from unallocated pool
    let total_collateral: u256 = current_round.total_collateral();
    let total_premium_to_be_paid: u256 = current_round.get_auction_clearing_price()
        * current_round.total_options_sold();
    // LP % of the round
    let ratio_of_liquidity_provider_1: u256 = (vault_facade
        .get_collateral_balance_for(liquidity_provider_1())
        * 100)
        / total_collateral;
    let ratio_of_liquidity_provider_2: u256 = (vault_facade
        .get_collateral_balance_for(liquidity_provider_2())
        * 100)
        / total_collateral;
    // LP premiums share
    let premium_for_liquidity_provider_1: u256 = (ratio_of_liquidity_provider_1
        * total_premium_to_be_paid)
        / 100;
    let premium_for_liquidity_provider_2: u256 = (ratio_of_liquidity_provider_2
        * total_premium_to_be_paid)
        / 100;
    // The actual unallocated balance of the LPs
    let actual_unallocated_balance_provider_1: u256 = vault_facade
        .get_unallocated_balance_for(liquidity_provider_1());
    let actual_unallocated_balance_provider_2: u256 = vault_facade
        .get_unallocated_balance_for(liquidity_provider_2());

    assert(
        actual_unallocated_balance_provider_1 == premium_for_liquidity_provider_1,
        'premium paid in ratio'
    );
    assert(
        actual_unallocated_balance_provider_2 == premium_for_liquidity_provider_2,
        'premium paid in ratio'
    );
}

#[test]
#[available_gas(10000000)]
fn test_premium_collection_ratio_conversion_unallocated_pool_2() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round.get_params();
    // Deposit liquidity
    let deposit_amount_wei_1: u256 = 1000 * decimals();
    vault_facade.deposit(deposit_amount_wei_1, liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei_1, liquidity_provider_2());
    // Make bid
    vault_facade.start_auction();
    let bid_amount_user_1: u256 = ((params.total_options_available / 2) + 1) * params.reserve_price;
    let bid_amount_user_2: u256 = (params.total_options_available / 2) * params.reserve_price;
    current_round.place_bid(bid_amount_user_1, params.reserve_price, option_bidder_buyer_1());
    current_round.place_bid(bid_amount_user_2, params.reserve_price, option_bidder_buyer_2());
    // End auction
    vault_facade.timeskip_and_end_auction();
    // Premium comes from unallocated pool
    let total_collateral: u256 = current_round.total_collateral();
    let total_premium_to_be_paid: u256 = current_round.get_auction_clearing_price()
        * current_round.total_options_sold();
    // LP % of the round
    let ratio_of_liquidity_provider_1: u256 = (vault_facade
        .get_collateral_balance_for(liquidity_provider_1())
        * 100)
        / total_collateral;
    let ratio_of_liquidity_provider_2: u256 = (vault_facade
        .get_collateral_balance_for(liquidity_provider_2())
        * 100)
        / total_collateral;
    // LP premiums share
    let premium_for_liquidity_provider_1: u256 = (ratio_of_liquidity_provider_1
        * total_premium_to_be_paid)
        / 100;
    let premium_for_liquidity_provider_2: u256 = (ratio_of_liquidity_provider_2
        * total_premium_to_be_paid)
        / 100;
    // The actual unallocated balance of the LPs
    let actual_unallocated_balance_provider_1: u256 = vault_facade
        .get_unallocated_balance_for(liquidity_provider_1());
    let actual_unallocated_balance_provider_2: u256 = vault_facade
        .get_unallocated_balance_for(liquidity_provider_2());

    assert(
        actual_unallocated_balance_provider_1 == premium_for_liquidity_provider_1,
        'premium paid in ratio'
    );
    assert(
        actual_unallocated_balance_provider_2 == premium_for_liquidity_provider_2,
        'premium paid in ratio'
    );
}

