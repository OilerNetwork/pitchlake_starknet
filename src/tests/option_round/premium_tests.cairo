use starknet::testing::{set_block_timestamp, set_contract_address, ContractAddress};
use pitch_lake_starknet::tests::{
    option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
    vault_facade::{VaultFacade, VaultFacadeTrait},
    mocks::{
        mock_market_aggregator::{
            MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
            IMarketAggregatorSetterDispatcherTrait
        }
    },
    vault::utils::{accelerate_to_running}
};
use pitch_lake_starknet::tests::utils::{
    setup_facade, liquidity_provider_1, liquidity_provider_2, liquidity_provider_3,
    liquidity_provider_4, liquidity_provider_5, decimals, option_bidder_buyer_1,
    option_bidder_buyer_2
};


// Test premiums collectable is 0 before auction end
#[test]
#[available_gas(10000000)]
fn test_premium_amount_0_before_auction_end(
    ref vault_facade: VaultFacade, liquidity_providers: Span<ContractAddress>, amounts: Span<u256>
) {
    let (mut vault_facade, _) = setup_facade();

    // Deposit liquidity
    vault_facade.deposit(100 * decimals(), liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    // Bid for all options at reserve price
    let mut current_round = vault_facade.get_current_round();
    let params = current_round.get_params();
    let bid_amount = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_amount = bid_amount * bid_price;
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());

    // Check premiums collectable is 0 since auction is still on going
    let premiums_collectable = vault_facade.get_unallocated_balance_for(liquidity_provider_1());
    assert(premiums_collectable == 0, 'LP premiums shd be 0');
}


// Test the portion of premiums an LP can collect in a round is correct
#[test]
#[available_gas(10000000)]
fn test_premium_amount_for_liquidity_providers_1() {
    let (mut vault_facade, _) = setup_facade();
    // LPs
    let lps = array![liquidity_provider_1(), liquidity_provider_2(),];
    // Deposit amounts
    let amounts = array![1000 * decimals(), 10000 * decimals()];

    _test_premiums_collectable_helper(ref vault_facade, lps.span(), amounts.span());
}

// Test the portion of premiums an LP can collect in a round is correct (more LPs)
#[test]
#[available_gas(10000000)]
fn test_premium_amount_for_liquidity_providers_2() {
    let (mut vault_facade, _) = setup_facade();
    // LPs
    let lps = array![
        liquidity_provider_1(),
        liquidity_provider_2(),
        liquidity_provider_3(),
        liquidity_provider_4()
    ];
    // Deposit amounts
    let amounts = array![250 * decimals(), 500 * decimals(), 1000 * decimals(), 1500 * decimals(),];

    _test_premiums_collectable_helper(ref vault_facade, lps.span(), amounts.span());
}

// Test the portion of premiums an LP can collect in a round is correct (more LPs)
#[test]
#[available_gas(10000000)]
fn test_premium_amount_for_liquidity_providers_3() {
    let (mut vault_facade, _) = setup_facade();
    // LPs
    let lps = array![
        liquidity_provider_1(),
        liquidity_provider_2(),
        liquidity_provider_3(),
        liquidity_provider_4()
    ];
    // Deposit amounts
    let amounts = array![333 * decimals(), 333 * decimals(), 333 * decimals(), 1 * decimals(),];

    _test_premiums_collectable_helper(ref vault_facade, lps.span(), amounts.span());
}

// Test the portion of premiums an LP can collect in a round is correct (more LPs)
#[test]
#[available_gas(10000000)]
fn test_premium_amount_for_liquidity_providers_4() {
    let (mut vault_facade, _) = setup_facade();
    // LPs
    let lps = array![
        liquidity_provider_1(),
        liquidity_provider_2(),
        liquidity_provider_3(),
        liquidity_provider_4(),
        liquidity_provider_5(),
    ];
    // Deposit amounts
    let amounts = array![25, 25, 25, 25, 1];

    _test_premiums_collectable_helper(ref vault_facade, lps.span(), amounts.span());
}
// Internal tester to check the premiums collectable for LPs is correct
fn _test_premiums_collectable_helper(
    ref vault_facade: VaultFacade, liquidity_providers: Span<ContractAddress>, amounts: Span<u256>
) {
    let (mut vault_facade, _) = setup_facade();
    assert(liquidity_providers.len() == amounts.len(), 'Span missmatch');
    // Deposit liquidity
    let mut i = 0;
    loop {
        if (i == liquidity_providers.len()) {
            break;
        }
        let lp: ContractAddress = *liquidity_providers.at(i);
        let deposit_amount: u256 = *amounts.at(i);
        vault_facade.deposit(deposit_amount, lp);

        i += 1;
    };
    // Start auction
    vault_facade.start_auction();
    // End auction, minting all options at reserve price
    accelerate_to_running(ref vault_facade);
    // Get total collateral in pool (deposit total) and total premium
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let mut total_collateral_in_pool = 0;
    i = 0;
    loop {
        if (i == amounts.len()) {
            break;
        }
        total_collateral_in_pool += *amounts.at(i);
        i += 1;
    };
    let total_premium: u256 = current_round.get_auction_clearing_price()
        * current_round.total_options_sold();

    // Check each LP's collectable premiums matches expected
    i = 0;
    loop {
        if (i == liquidity_providers.len()) {
            break;
        }
        // @note Handle precision loss ?
        let lp_expected_premium = (*amounts.at(i) * total_premium) / total_collateral_in_pool;
        let lp_actual_premium = vault_facade
            .get_unallocated_balance_for(*liquidity_providers.at(i));

        assert(lp_actual_premium == lp_expected_premium, 'LP premiums wrong');

        i += 1;
    };
}
// @note Need tests for premium collection: eth transfer, lp/round unallocated decrementing, remaining premiums for other LPs unaffected, cannot collect twice/more than remaining collectable amount


