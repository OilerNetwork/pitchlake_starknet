use starknet::testing::{set_block_timestamp, set_contract_address, ContractAddress};
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};
use pitch_lake_starknet::tests::{
    utils::{
        event_helpers::{assert_event_transfer, assert_event_vault_withdrawal},
        accelerators::{
            accelerate_to_auctioning, accelerate_to_auctioning_custom, accelerate_to_running,
            accelerate_to_running_custom, accelerate_to_settled, clear_event_logs
        },
        test_accounts::{
            liquidity_provider_1, liquidity_provider_2, liquidity_provider_3, liquidity_provider_4,
            liquidity_provider_5, option_bidder_buyer_1, option_bidder_buyer_2,
            option_bidder_buyer_3, liquidity_providers_get
        },
        variables::{decimals}, setup::{setup_facade},
        facades::{
            option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait, OptionRoundParams},
            vault_facade::{VaultFacade, VaultFacadeTrait},
        },
        mocks::{
            mock_market_aggregator::{
                MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
                IMarketAggregatorSetterDispatcherTrait
            }
        },
    },
};
use debug::PrintTrait;

// @note If premiums collected fails/is 0 amount, should an event be emiited or no ?
// Test premiums collectable is 0 before auction end
#[test]
#[available_gas(10000000)]
fn test_premium_amount_0_before_auction_end() {
    let (mut vault_facade, _) = setup_facade();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = current_round_facade.get_params();

    // Bid for all options at reserve price
    let bid_amount = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_amount = bid_amount * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());

    // Check premiums collectable is 0 since auction is still on going
    let premiums_collectable = vault_facade.get_lp_unlocked_balance(liquidity_provider_1());
    assert(premiums_collectable == 0, 'LP premiums shd be 0');
}


// Test the portion of premiums an LP can collect in a round is correct
#[test]
#[available_gas(1000000000)]
fn test_premium_amount_for_liquidity_providers_1() {
    let (mut vault_facade, _) = setup_facade();
    // LPs
    let lps = liquidity_providers_get(2);
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
    let lps = liquidity_providers_get(4);
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
    let lps = liquidity_providers_get(4);
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
    let lps = liquidity_providers_get(5);
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
    let lps = liquidity_providers_get(2);
    // Deposit amounts
    // @dev 1000 ETH & 0.001 ETH
    let amounts = array![1000 * decimals(), decimals() / 1000];

    _test_premiums_collectable_helper(ref vault_facade, lps.span(), amounts.span());
}

// @note Should be a withdraw test
// Test collecting premiums transfers ETH
// #[test]
// #[available_gas(10000000)]
// fn test_premium_collection_transfers_eth() {
//     let (mut vault_facade, eth) = setup_facade();
//     // LPs
//     let lps = liquidity_providers_get(2);
//     // Deposit amounts
//     let amounts = array![50 * decimals(), 50 * decimals()];

//     _test_premiums_collectable_helper(ref vault_facade, lps.span(), amounts.span());

//     // LP balances pre collection
//     let lp1_balance_init = eth.balance_of(*lps[0]);
//     let lp2_balance_init = eth.balance_of(*lps[1]);
//     let collectable_premiums = vault_facade.get_unallocated_balance_for(*lps[0]); // same as lp2

//     // Collect premiums
//     vault_facade.collect_premiums(*lps[0]);
//     vault_facade.collect_premiums(*lps[1]);

//     // LP balances post collection
//     let lp2_balance_final = eth.balance_of(*lps[1]);
//     let lp1_balance_final = eth.balance_of(*lps[0]);
//     let mut _current_round = vault_facade.get_current_round();

//     // Check eth: current_round -> lps
//     assert(
//         lp1_balance_final == lp1_balance_init + collectable_premiums, 'lp1 did not collect premiums'
//     );
//     assert(
//         lp2_balance_final == lp2_balance_init + collectable_premiums, 'lp2 did not collect premiums'
//     );
// }

// @note Add test that premiums earned are sent to vault (eth transfer)
// @note Add test that premiums go to vault::unlocked & vault::lp::unlocked

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
    let (lp1_collateral_init, lp1_unallocated_init) = vault_facade
        .get_lp_balance_spread(*lps.at(0));
    let (lp2_collateral_init, lp2_unallocated_init) = vault_facade
        .get_lp_balance_spread(*lps.at(1));
    let lp1_total_balance_before = lp1_collateral_init + lp1_unallocated_init;
    let lp2_total_balance_before = lp2_collateral_init + lp2_unallocated_init;

    // Collect premiums
    let collected_amount1 = vault_facade.collect_premiums(*lps.at(0));
    let collected_amount2 = vault_facade.collect_premiums(*lps.at(1));

    assert_event_vault_withdrawal(
        vault_facade.contract_address(),
        *lps.at(0),
        lp1_total_balance_before,
        lp1_total_balance_before - collected_amount1,
    );
    assert_event_vault_withdrawal(
        vault_facade.contract_address(),
        *lps.at(1),
        lp2_total_balance_before,
        lp2_total_balance_before - collected_amount2,
    );
}

// @note Test that vault::unlocked updates not round's
// Test collecting premiums updates lp/round unallocated
// #[test]
// #[available_gas(10000000)]
// fn test_premium_collection_updates_unallocated_amounts() {
//     let (mut vault_facade, _) = setup_facade();
//     // LPs
//     let lps = liquidity_providers_get(2);
//     // Deposit amounts
//     let amounts = array![50 * decimals(), 50 * decimals()];

//     _test_premiums_collectable_helper(ref vault_facade, lps.span(), amounts.span());

//     // Unallocated balances pre collection
//     let mut current_round = vault_facade.get_current_round();
//     let round_unallocated_init = current_round.total_unallocated_liquidity();
//     let lp2_unallocated_init = vault_facade.get_unallocated_balance_for(*lps[1]);
//     // Collect premiums (lp 1 only)
//     vault_facade.collect_premiums(*lps[0]);

//     // Unallocated balaances post collection
//     let lp1_unallocated_final = vault_facade.get_unallocated_balance_for(*lps[0]);
//     let lp2_unallocated_final = vault_facade.get_unallocated_balance_for(*lps[1]);
//     let round_unallocated_final = current_round.total_unallocated_liquidity();

//     // Check unallocated balances for round/lps is correct
//     assert(lp1_unallocated_final == 0, 'lp1 did not collect premiums');
//     assert(lp2_unallocated_final == lp2_unallocated_init, 'lp2 shd not collect premiums');
//     assert(
//         round_unallocated_final == round_unallocated_init - lp2_unallocated_init,
//         'round unallocated wrong'
//     );
// }

// @note This is essentailly testing withdraw amount > unlocked balance, so should be a withdraw test,
// but we still should test LP cannot double collect prmeiums
// Test collecting premiums twice fails
// @note Maybe this shouldnt fail, but just do nothing instead ?
// #[test]
// #[available_gas(10000000000)]
// #[should_panic(expected: ('No premiums to collect', 'ENTRYPOINT_FAILED'))]
// fn test_premium_collect_none_fails() {
//     let (mut vault_facade, _) = setup_facade();
//     // LPs
//     let lps = liquidity_providers_get(1);
//     let amounts = array![50 * decimals()];
//     // Deposit amounts

//     _test_premiums_collectable_helper(ref vault_facade, lps.span(), amounts.span());

//     // Collect premiums
//     vault_facade.collect_premiums(*lps[0]);

//     // Try to collect premiums again
//     vault_facade.collect_premiums(*lps[0]);
// }

// Internal tester to check the premiums collectable for LPs is correct
fn _test_premiums_collectable_helper(
    ref vault_facade: VaultFacade, liquidity_providers: Span<ContractAddress>, amounts: Span<u256>
) {
    // @note: we don't need to setup it again right? we are doing this ??
    // let (mut vault_facade, _) = setup_facade();
    assert(liquidity_providers.len() == amounts.len(), 'Span missmatch');

    // Deposit liquidity and start the auction
    accelerate_to_auctioning_custom(ref vault_facade, liquidity_providers, amounts);

    // End auction, minting all options at reserve price
    accelerate_to_running(ref vault_facade);

    // Get total collateral in pool (deposit total) and total premium
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let amount_span = amounts;
    let mut total_collateral_in_pool = 0;
    let mut i = 0;
    loop {
        if (i == amount_span.len()) {
            break;
        }
        total_collateral_in_pool += *amount_span.at(i);
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
        let lp_expected_premium = (*amount_span.at(i) * total_premium) / total_collateral_in_pool;
        let lp_actual_premium = vault_facade.get_lp_unlocked_balance(*liquidity_providers.at(i));

        assert(lp_actual_premium == lp_expected_premium, 'LP premiums wrong');

        i += 1;
    };
}
// @note Need tests for premium collection: lp/round unallocated decrementing, remaining premiums for other LPs unaffected, cannot collect twice/more than remaining collectable amount


