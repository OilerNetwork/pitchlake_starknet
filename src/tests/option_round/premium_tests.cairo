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
    vault::utils::{accelerate_to_running}, utils::{assert_event_transfer}
};
use pitch_lake_starknet::tests::utils::{
    setup_facade, liquidity_provider_1, liquidity_provider_2, liquidity_provider_3,
    liquidity_provider_4, liquidity_provider_5, decimals, option_bidder_buyer_1,
    option_bidder_buyer_2, assert_event_option_withdraw_payout, assert_event_vault_transfer,
    clear_event_logs, assert_event_option_withdraw_premium
};
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};
use debug::PrintTrait;

// @note If premiums collected fails/is 0 amount, should an event be emiited or no ?

// Test premiums collectable is 0 before auction end
#[test]
#[available_gas(10000000)]
fn test_premium_amount_0_before_auction_end() {
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
#[available_gas(1000000000)]
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
#[available_gas(1000000000)]
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
#[available_gas(1000000000)]
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
#[available_gas(1000000000)]
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

// Test the portion of premiums an LP can collect in a round is correct, when deposit 1 >>> deposit 2
#[test]
#[available_gas(1000000000)]
fn test_premium_amount_for_liquidity_providers_5() {
    let (mut vault_facade, _) = setup_facade();
    // LPs
    let lps = array![liquidity_provider_1(), liquidity_provider_2(),];
    // Deposit amounts
    // @dev 1000 ETH & 0.001 ETH
    let amounts = array![1000 * decimals(), decimals() / 1000];

    _test_premiums_collectable_helper(ref vault_facade, lps.span(), amounts.span());
}

// Test collecting premiums transfers ETH
#[test]
#[available_gas(10000000)]
fn test_premium_collection_transfers_eth() {
    let (mut vault_facade, eth) = setup_facade();
    // LPs
    let lps = array![liquidity_provider_1(), liquidity_provider_2(),];
    // Deposit amounts
    let amounts = array![50 * decimals(), 50 * decimals()];

    _test_premiums_collectable_helper(ref vault_facade, lps.span(), amounts.span());

    // LP balances pre collection
    let lp1_balance_init = eth.balance_of(liquidity_provider_1());
    let lp2_balance_init = eth.balance_of(liquidity_provider_2());
    let collectable_premiums = vault_facade
        .get_unallocated_balance_for(liquidity_provider_1()); // same as lp2

    // Collect premiums
    vault_facade.collect_premiums(liquidity_provider_1());
    vault_facade.collect_premiums(liquidity_provider_2());

    // LP balances post collection
    let lp2_balance_final = eth.balance_of(liquidity_provider_2());
    let lp1_balance_final = eth.balance_of(liquidity_provider_1());

    // Check eth: current_round -> lps
    assert(
        lp1_balance_final == lp1_balance_init + collectable_premiums, 'lp1 did not collect premiums'
    );
    assert(
        lp2_balance_final == lp2_balance_init + collectable_premiums, 'lp2 did not collect premiums'
    );
}


#[test]
#[available_gas(10000000)]
fn test_premium_collection_emits_events() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit and start auction
    // @note Replace with accelerators post sync
    let lps = array![liquidity_provider_1(), liquidity_provider_2(),];
    let amounts = array![50 * decimals(), 50 * decimals()];
    _test_premiums_collectable_helper(ref vault_facade, lps.span(), amounts.span());
    let mut option_round = vault_facade.get_current_round();
    // Clear events
    clear_event_logs(array![vault_facade.contract_address(), option_round.contract_address()]);
    // Initial protocol spread
    let (lp1_collateral_init, lp1_unallocated_init) = vault_facade.get_all_lp_liquidity(*lps.at(0));
    let (lp2_collateral_init, lp2_unallocated_init) = vault_facade.get_all_lp_liquidity(*lps.at(1));
    let lp1_total_balance_before = lp1_collateral_init + lp1_unallocated_init;
    let lp2_total_balance_before = lp2_collateral_init + lp2_unallocated_init;

    // Collect premiums
    let collected_amount1 = vault_facade.collect_premiums(*lps.at(0));
    let collected_amount2 = vault_facade.collect_premiums(*lps.at(1));

    assert_event_option_withdraw_premium(
        option_round.contract_address(), *lps.at(0), collected_amount1
    );
    assert_event_option_withdraw_premium(
        option_round.contract_address(), *lps.at(1), collected_amount2
    );
    assert_event_vault_transfer(
        vault_facade.contract_address(),
        *lps.at(0),
        lp1_total_balance_before,
        lp1_total_balance_before - collected_amount1,
        false
    );
    assert_event_vault_transfer(
        vault_facade.contract_address(),
        *lps.at(1),
        lp2_total_balance_before,
        lp2_total_balance_before - collected_amount2,
        false
    );
//check vault and option round evetns
}

// Test collecting premiums updates lp/round unallocated
#[test]
#[available_gas(10000000)]
fn test_premium_collection_updates_unallocated_amounts() {
    let (mut vault_facade, _) = setup_facade();
    // LPs
    let lps = array![liquidity_provider_1(), liquidity_provider_2(),];
    // Deposit amounts
    let amounts = array![50 * decimals(), 50 * decimals()];

    _test_premiums_collectable_helper(ref vault_facade, lps.span(), amounts.span());

    // Unallocated balances pre collection
    let mut current_round = vault_facade.get_current_round();
    let round_unallocated_init = current_round.total_unallocated_liquidity();
    let lp2_unallocated_init = vault_facade.get_unallocated_balance_for(liquidity_provider_2());
    // Collect premiums (lp 1 only)
    vault_facade.collect_premiums(liquidity_provider_1());

    // Unallocated balaances post collection
    let lp1_unallocated_final = vault_facade.get_unallocated_balance_for(liquidity_provider_1());
    let lp2_unallocated_final = vault_facade.get_unallocated_balance_for(liquidity_provider_2());
    let round_unallocated_final = current_round.total_unallocated_liquidity();

    // Check unallocated balances for round/lps is correct
    assert(lp1_unallocated_final == 0, 'lp1 did not collect premiums');
    assert(lp2_unallocated_final == lp2_unallocated_init, 'lp2 shd not collect premiums');
    assert(
        round_unallocated_final == round_unallocated_init - lp2_unallocated_init,
        'round unallocated wrong'
    );
}

// Test collecting premiums twice fails
// @note Maybe this shouldnt fail, but just do nothing instead ?
#[test]
#[available_gas(10000000000)]
#[should_panic(expected: ('No premiums to collect', 'ENTRYPOINT_FAILED'))]
fn test_premium_collect_none_fails() {
    let (mut vault_facade, eth) = setup_facade();
    // LPs
    let lps = array![liquidity_provider_1()];
    let amounts = array![50 * decimals()];
    // Deposit amounts

    _test_premiums_collectable_helper(ref vault_facade, lps.span(), amounts.span());

    // Collect premiums
    vault_facade.collect_premiums(liquidity_provider_1());

    // Try to collect premiums again
    vault_facade.collect_premiums(liquidity_provider_1());
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
// @note Need tests for premium collection: lp/round unallocated decrementing, remaining premiums for other LPs unaffected, cannot collect twice/more than remaining collectable amount


