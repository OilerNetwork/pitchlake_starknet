use pitch_lake::tests::utils::facades::option_round_facade::{
    OptionRoundFacade, OptionRoundFacadeTrait,
};
use pitch_lake::tests::utils::facades::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake::tests::utils::helpers::accelerators::{
    accelerate_to_auctioning, accelerate_to_auctioning_custom, accelerate_to_running,
};
use pitch_lake::tests::utils::helpers::setup::setup_facade;
use pitch_lake::tests::utils::lib::test_accounts::{
    liquidity_provider_1, liquidity_providers_get, option_bidder_buyer_1,
};
use pitch_lake::tests::utils::lib::variables::decimals;
use starknet::ContractAddress;

// @note move these tests to ./src/tests/option_round/state_transition/auction_end_tests

// @note If premiums collected fails/is 0 amount, should an event be emiited or no ?
// Test premiums collectable is 0 before auction end
#[test]
#[available_gas(50000000)]
fn test_premium_amount_0_before_auction_end() {
    let (mut vault_facade, _) = setup_facade();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();

    // Bid for all options at reserve price
    let bid_amount = current_round.get_total_options_available();
    let bid_price = current_round.get_reserve_price();
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());

    // Check premiums collectable is 0 since auction is still on going
    let premiums_collectable = vault_facade.get_lp_unlocked_balance(liquidity_provider_1());
    assert(premiums_collectable == 0, 'LP premiums shd be 0');
}


// Test the portion of premiums an LP can collect in a round is correct
#[test]
#[available_gas(50000000)]
fn test_premium_amount_for_liquidity_providers_1() {
    let (mut vault_facade, _) = setup_facade();
    // LPs
    let liquidity_providers = liquidity_providers_get(2);
    // Deposit amounts
    let amounts = array![1000 * decimals(), 10000 * decimals()];

    _test_premiums_collectable_helper(ref vault_facade, liquidity_providers.span(), amounts.span());
}

// Test the portion of premiums an LP can collect in a round is correct (more LPs)
#[test]
#[available_gas(50000000)]
fn test_premium_amount_for_liquidity_providers_2() {
    let (mut vault_facade, _) = setup_facade();
    // LPs
    let liquidity_providers = liquidity_providers_get(4);
    // Deposit amounts
    let amounts = array![250 * decimals(), 500 * decimals(), 1000 * decimals(), 1500 * decimals()];

    _test_premiums_collectable_helper(ref vault_facade, liquidity_providers.span(), amounts.span());
}

// Test the portion of premiums an LP can collect in a round is correct (more LPs)
#[test]
#[available_gas(50000000)]
fn test_premium_amount_for_liquidity_providers_3() {
    let (mut vault_facade, _) = setup_facade();
    // LPs
    let liquidity_providers = liquidity_providers_get(4);
    // Deposit amounts
    let amounts = array![333 * decimals(), 333 * decimals(), 333 * decimals(), 1 * decimals()];

    _test_premiums_collectable_helper(ref vault_facade, liquidity_providers.span(), amounts.span());
}

// Test the portion of premiums an LP can collect in a round is correct (more LPs)
#[test]
#[available_gas(80000000)]
fn test_premium_amount_for_liquidity_providers_4() {
    let (mut vault_facade, _) = setup_facade();
    // LPs
    let liquidity_providers = liquidity_providers_get(5);
    // Deposit amounts
    let amounts = array![
        25 * decimals(), 25 * decimals(), 25 * decimals(), 25 * decimals(), 1 * decimals(),
    ];

    _test_premiums_collectable_helper(ref vault_facade, liquidity_providers.span(), amounts.span());
}

// Test the portion of premiums an LP can collect in a round is correct, when deposit 1 >>> deposit
// 2
#[test]
#[available_gas(50000000)]
fn test_premium_amount_for_liquidity_providers_5() {
    let (mut vault_facade, _) = setup_facade();
    // LPs
    let liquidity_providers = liquidity_providers_get(2);
    // Deposit amounts
    // @dev 1000 ETH & 0.001 ETH
    let amounts = array![1000 * decimals(), decimals() / 1000];

    _test_premiums_collectable_helper(ref vault_facade, liquidity_providers.span(), amounts.span());
}

// @note Should be a withdraw test
// Test collecting premiums transfers ETH
// #[test]
// #[available_gas(10000000)]
// fn test_premium_collection_transfers_eth() {
//     let (mut vault_facade, eth) = setup_facade();
//     // LPs
//     let liquidity_providers = liquidity_providers_get(2);
//     // Deposit amounts
//     let amounts = array![50 * decimals(), 50 * decimals()];

//     _test_premiums_collectable_helper(ref vault_facade, liquidity_providers.span(),
//     amounts.span());

//     // LP balances pre collection
//     let lp1_balance_init = eth.balance_of(*liquidity_providers,[0]);
//     let lp2_balance_init = eth.balance_of(*liquidity_providers,[1]);
//     let collectable_premiums =
//     vault_facade.get_unallocated_balance_for(*liquidity_providers,[0]); // same as lp2

//     // Collect premiums
//     vault_facade.collect_premiums(*liquidity_providers,[0]);
//     vault_facade.collect_premiums(*liquidity_providers,[1]);

//     // LP balances post collection
//     let lp2_balance_final = eth.balance_of(*liquidity_providers,[1]);
//     let lp1_balance_final = eth.balance_of(*liquidity_providers,[0]);
//     let mut _current_round = vault_facade.get_current_round();

//     // Check eth: current_round -> liquidity_providers
//     assert(
//         lp1_balance_final == lp1_balance_init + collectable_premiums, 'lp1 did not collect
//         premiums'
//     );
//     assert(
//         lp2_balance_final == lp2_balance_init + collectable_premiums, 'lp2 did not collect
//         premiums'
//     );
// }

// @note Add test that premiums earned are sent to vault (eth transfer)
// @note Add test that premiums go to vault::unlocked & vault::lp::unlocked

// @note Not needed since there is no longer a collect premiums function, just the single withdraw
// function
//#[test]
//#[available_gas(10000000)]
//fn test_premium_collection_emits_events() {
//    let (mut vault_facade, _) = setup_facade();
//    // Deposit and start auction
//    // @note Replace with accelerators post sync
//    let liquidity_providers = array![liquidity_provider_1(), liquidity_provider_2(),];
//    let amounts = array![50 * decimals(), 50 * decimals()];
//    _test_premiums_collectable_helper(ref vault_facade, liquidity_providers.span(),
//    amounts.span());
//    let mut option_round = vault_facade.get_current_round();
//    // Clear events
//    clear_event_logs(array![vault_facade.contract_address(), option_round.contract_address()]);
//    // Initial protocol spread
//    let (lp1_locked_init, lp1_unlocked_init) = vault_facade
//        .get_lp_balance_spread(*liquidity_providers,.at(0));
//    let (lp2_locked_init, lp2_unlocked_init) = vault_facade
//        .get_lp_balance_spread(*liquidity_providers,.at(1));
//    let lp1_total_balance_before = lp1_locked_init + lp1_unlocked_init;
//    let lp2_total_balance_before = lp2_locked_init + lp2_unlocked_init;
//
//    // Collect premiums
//    let collected_amount1 = vault_facade.withdraw(*liquidity_providers,.at(0));
//    let collected_amount2 = vault_facade.collect_premiums(*liquidity_providers,.at(1));
//
//    assert_event_vault_withdrawal(
//        vault_facade.contract_address(),
//        *liquidity_providers,.at(0),
//        lp1_total_balance_before,
//        lp1_total_balance_before - collected_amount1,
//    );
//    assert_event_vault_withdrawal(
//        vault_facade.contract_address(),
//        *liquidity_providers,.at(1),
//        lp2_total_balance_before,
//        lp2_total_balance_before - collected_amount2,
//    );
//}

// @note Test that vault::unlocked updates not round's
// Test collecting premiums updates lp/round unallocated
// #[test]
// #[available_gas(10000000)]
// fn test_premium_collection_updates_unallocated_amounts() {
//     let (mut vault_facade, _) = setup_facade();
//     // LPs
//     let liquidity_providers = liquidity_providers_get(2);
//     // Deposit amounts
//     let amounts = array![50 * decimals(), 50 * decimals()];

//     _test_premiums_collectable_helper(ref vault_facade, liquidity_providers.span(),
//     amounts.span());

//     // Unallocated balances pre collection
//     let mut current_round = vault_facade.get_current_round();
//     let round_unallocated_init = current_round.total_unallocated_liquidity();
//     let lp2_unallocated_init =
//     vault_facade.get_unallocated_balance_for(*liquidity_providers,[1]);
//     // Collect premiums (lp 1 only)
//     vault_facade.collect_premiums(*liquidity_providers,[0]);

//     // Unallocated balaances post collection
//     let lp1_unallocated_final =
//     vault_facade.get_unallocated_balance_for(*liquidity_providers,[0]);
//     let lp2_unallocated_final =
//     vault_facade.get_unallocated_balance_for(*liquidity_providers,[1]);
//     let round_unallocated_final = current_round.total_unallocated_liquidity();

//     // Check unallocated balances for round/liquidity_providers is correct
//     assert(lp1_unallocated_final == 0, 'lp1 did not collect premiums');
//     assert(lp2_unallocated_final == lp2_unallocated_init, 'lp2 shd not collect premiums');
//     assert(
//         round_unallocated_final == round_unallocated_init - lp2_unallocated_init,
//         'round unallocated wrong'
//     );
// }

// @note This is essentailly testing withdraw amount > unlocked balance, so should be a withdraw
// test, but we still should test LP cannot double collect prmeiums
// Test collecting premiums twice fails
// @note Maybe this shouldnt fail, but just do nothing instead ?
// #[test]
// #[available_gas(10000000000)]
// #[should_panic(expected: ('No premiums to collect', 'ENTRYPOINT_FAILED'))]
// fn test_premium_collect_none_fails() {
//     let (mut vault_facade, _) = setup_facade();
//     // LPs
//     let liquidity_providers = liquidity_providers_get(1);
//     let amounts = array![50 * decimals()];
//     // Deposit amounts

//     _test_premiums_collectable_helper(ref vault_facade, liquidity_providers.span(),
//     amounts.span());

//     // Collect premiums
//     vault_facade.collect_premiums(*liquidity_providers,[0]);

//     // Try to collect premiums again
//     vault_facade.collect_premiums(*liquidity_providers,[0]);
// }

// Internal tester to check the premiums collectable for LPs is correct
fn _test_premiums_collectable_helper(
    ref vault: VaultFacade, liquidity_providers: Span<ContractAddress>, amounts: Span<u256>,
) {
    assert(liquidity_providers.len() == amounts.len(), 'Span missmatch');

    // Deposit liquidity and start the auction
    accelerate_to_auctioning_custom(ref vault, liquidity_providers, amounts);

    // End auction
    accelerate_to_running(ref vault);

    let mut current_round = vault.get_current_round();
    let sold_liq = current_round.sold_liquidity();
    let unsold_liq = current_round.unsold_liquidity();
    let total_liq = sold_liq + unsold_liq;
    let total_premium = current_round.total_premiums();

    // Check each LP's collectable premiums matches expected
    for i in 0..liquidity_providers.len() {
        let deposit_amount = *amounts.at(i);

        let exp_lp_unlocked = (deposit_amount * (unsold_liq + total_premium)) / (total_liq);
        let lp_unlocked = vault.get_lp_unlocked_balance(*liquidity_providers.at(i));

        assert(lp_unlocked == exp_lp_unlocked, 'LP unlocked wrong');
    };
}
