use debug::PrintTrait;
use starknet::{
    ContractAddressIntoFelt252, contract_address_to_felt252, ClassHash, ContractAddress,
    contract_address_const, deploy_syscall, Felt252TryIntoContractAddress, get_contract_address,
    get_block_timestamp, testing::{set_block_timestamp, set_contract_address}
};
use pitch_lake_starknet::tests::{
    option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
    vault_facade::{VaultFacade, VaultFacadeTrait}, utils,
    utils::{
        setup_facade, liquidity_provider_1, liquidity_provider_2, liquidity_providers_get, decimals,
        option_bidder_buyer_1, option_bidder_buyer_2, accelerate_to_running,
        accelerate_to_auctioning
    },
    mocks::mock_market_aggregator::{
        MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
        IMarketAggregatorSetterDispatcherTrait
    },
};
use pitch_lake_starknet::tests::utils::{
    create_array_gradient, accelerate_to_auctioning_custom, create_array_linear, option_bidders_get,
    accelerate_to_running_custom // , deploy_vault, allocated_pool_address, unallocated_pool_address,
// timestamp_start_month, timestamp_end_month, liquidity_provider_2,
// , option_bidder_buyer_3, option_bidder_buyer_4,
// vault_manager, weth_owner, mock_option_params, assert_event_transfer
};


#[test]
#[available_gas(10000000)]
fn test_premiums_and_unsold_liquidity_unallocated_amount() {
    let (mut vault_facade, _) = setup_facade();
    // @note add accelerate to auctioning
    // Accelerate to round 1 running
    accelerate_to_running(ref vault_facade);
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

// @note Should be a withdraw test
// Make sure we update all withdraw tests and test all vectors (withdraw when premium/no premiums, next round deplosts/not, etc)
// Should not fail but return Result::Err(e)
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Collect > unallocated balance', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_more_than_unallocated_balance_failure() {
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
    let (_, lp_unlocked_position) = vault_facade.get_all_lp_liquidity(liquidity_provider_1());
    // Withdraw from rewards
    vault_facade.withdraw(lp_unlocked_position + 1, liquidity_provider_1());
}

// @note should be a round settle test
#[test]
#[available_gas(10000000)]
fn test_withdrawn_premiums_do_not_roll_over() {
    let (mut vault_facade, _) = setup_facade();
    // Round 1 running, round 2 open (round 1's starting liquidity is 200)
    utils::accelerate_to_auctioning_custom(
        ref vault_facade,
        liquidity_providers_get(2).span(),
        array![100 * decimals(), 100 * decimals()].span()
    );
    utils::accelerate_to_running(ref vault_facade);
    let (mut round_1, mut round_2) = vault_facade.get_current_and_next_rounds();

    // LP1 withdraws premiums earned in round 1, LP2 does not (1/2 premiums withdrawn)
    let round_1_premiums = round_1.total_premiums();
    vault_facade.withdraw(round_1_premiums / 2, liquidity_provider_1());

    // Settle round 1 with no payout, start round 2 (round 1 starting liquidity + 1/2 premiums roll over)
    utils::accelerate_to_settled(ref vault_facade, 0);
    set_block_timestamp(get_block_timestamp() + vault_facade.get_round_transition_period() + 1);
    // Start round 2 auction, no additional deposits
    utils::accelerate_to_auctioning_custom(ref vault_facade, array![].span(), array![].span());

    // LP and total locked/unlocked positions
    let (lp1_locked_position, lp1_unlocked_position) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_1());
    let (lp2_locked_position, lp2_unlocked_position) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_2());
    // @note replace with vaut::locked/unlocked
    let (round_2_locked, round_2_unlocked) = round_2.get_all_round_liquidity();

    assert(round_2_locked == (200 * decimals()) + round_1_premiums / 2, 'Vault locked wrong');
    assert(round_2_unlocked == 0, 'Vault unlocked wrong');
    assert(lp1_locked_position == 100 * decimals(), 'LP1 locked wrong');
    assert(lp1_unlocked_position == 0, 'LP1 unlocked wrong');
    assert(lp2_locked_position == 100 * decimals() + round_1_premiums / 2, 'LP2 locked wrong');
    assert(lp2_unlocked_position == 0, 'LP2 unlocked wrong');
}

// @note These tests need to update/rewrite
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
    let _deposit_total = accelerate_to_auctioning_custom(
        ref vault_facade, lps.span(), deposit_amounts.span()
    );
    let params = current_round.get_params();
    // Make bid (ob1)
    let bid_amount: u256 = params.total_options_available;

    let obs = option_bidders_get(5);
    let bid_prices = create_array_linear(params.reserve_price, 5);
    let bid_amounts = create_array_linear(params.reserve_price * bid_amount, 5);
    let _clearing_price = accelerate_to_running_custom(
        ref vault_facade, obs.span(), bid_prices.span(), bid_amounts.span()
    );

    // Premium comes from unallocated pool
    let total_collateral: u256 = current_round.total_collateral();
    let total_premium_to_be_paid: u256 = current_round.get_auction_clearing_price()
        * current_round.total_options_sold();
    // LP % of the round
    // @note Check math is correct/precision is handled (goes for all instances of ratio calculations like this)
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

