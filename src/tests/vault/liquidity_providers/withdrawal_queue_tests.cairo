use core::option::OptionTrait;
use core::array::SpanTrait;
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcherTrait,};
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use pitch_lake_starknet::{
    types::Errors, library::{eth::Eth, utils::divide_with_precision}, vault::{contract::Vault},
    tests::{
        utils::{
            helpers::{
                general_helpers::{
                    get_erc20_balances, sum_u256_array, create_array_gradient, create_array_linear,
                    to_wei, to_wei_multi, get_portion_of_amount
                },
                event_helpers::{
                    pop_log, assert_no_events_left, assert_event_transfer,
                    assert_event_vault_withdrawal, clear_event_logs,
                    assert_event_vault_stashed_withdrawal
                },
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_auctioning_custom,
                    accelerate_to_running_custom, accelerate_to_running, accelerate_to_settled,
                    timeskip_and_start_auction,
                },
                setup::{setup_facade},
            },
            lib::{
                test_accounts::{
                    liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                    option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                    liquidity_providers_get,
                },
                variables::{decimals},
            },
            facades::{
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
                vault_facade::{VaultFacade, VaultFacadeTrait},
            }
        },
    },
};
use debug::PrintTrait;

/// Queueing

// Test that when an LP queues a withdrawal, it does not roll over after round settles
#[test]
#[available_gas(300000000)]
fn test_stashed_liquidity_does_not_roll_over() {
    /// ROUND 1 ///
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();

    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();

    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );

    accelerate_to_running_custom(
        ref vault,
        array![option_bidder_buyer_1()].span(),
        array![divide_with_precision(current_round.get_total_options_available(), 2)].span(),
        array![current_round.get_reserve_price()].span()
    );

    // Queue withdrawal
    vault.queue_withdrawal(liquidity_provider, deposit_amount);

    // Start round 2
    let total_payout = accelerate_to_settled(ref vault, 1); //no payout
    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());

    let (total_locked, total_unlocked, total_stashed) = vault
        .get_total_locked_and_unlocked_and_stashed_balance();
    let lp_stashed = vault.get_lp_stashed_balance(liquidity_provider);

    let starting_liq = current_round.starting_liquidity();
    let total_premiums = current_round.total_premiums();
    let unsold_liq = vault.get_unsold_liquidity(current_round.get_round_id());

    let total_remaining = starting_liq - unsold_liq - total_payout;
    let total_earned = total_premiums + unsold_liq;

    assert_eq!(total_locked, total_earned);
    assert_eq!(total_unlocked, 0);
    assert_eq!(total_stashed, total_remaining);
    assert_eq!(lp_stashed, total_remaining);

    /// ROUND 2 ///

    // Queue withdrawal
    let deposit_amount2 = vault.get_lp_locked_balance(liquidity_provider);
    vault.queue_withdrawal(liquidity_provider, deposit_amount2);

    // Skip to round 3 auction start
    let mut current_round2 = vault.get_current_round();
    let starting_liq2 = current_round2.starting_liquidity();

    accelerate_to_running(ref vault);
    let unsold_liq2 = vault.get_unsold_liquidity(current_round2.get_round_id());
    let total_premiums2 = current_round2.total_premiums();
    let total_payout2 = accelerate_to_settled(ref vault, 1); //no payout

    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());

    let (total_locked2, total_unlocked2, total_stashed2) = vault
        .get_total_locked_and_unlocked_and_stashed_balance();
    let lp_stashed2 = vault.get_lp_stashed_balance(liquidity_provider);

    let total_remaining2 = starting_liq2 - unsold_liq2 - total_payout2;
    let total_earned2 = total_premiums2 + unsold_liq2;

    assert_eq!(total_locked2, total_earned2);
    assert_eq!(total_unlocked2, 0);
    assert_eq!(total_stashed2, total_remaining + total_remaining2);
    assert_eq!(lp_stashed2, total_remaining + total_remaining2);
}

// Test that when an LP queues a withdrawal, it does not roll over after round settles (multiple LPs)
#[test]
#[available_gas(300000000)]
fn test_stashed_liquidity_does_not_roll_over_multiple_LPs() {
    /// ROUND 1 ///
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();

    let deposit_amount = 100 * decimals();
    let deposit_amounts = create_array_linear(deposit_amount, 3).span();
    let liquidity_providers = liquidity_providers_get(3).span();

    accelerate_to_auctioning_custom(ref vault, liquidity_providers, deposit_amounts);

    // 1/2 options sell at reserve price
    accelerate_to_running_custom(
        ref vault,
        array![option_bidder_buyer_1()].span(),
        array![divide_with_precision(current_round.get_total_options_available(), 2)].span(),
        array![current_round.get_reserve_price()].span()
    );

    // LP 1 & 2 Queue withdrawal
    vault.queue_withdrawal(*liquidity_providers.at(0), *deposit_amounts.at(0));
    vault.queue_withdrawal(*liquidity_providers.at(1), *deposit_amounts.at(1));

    // Start round 2
    let total_payout = accelerate_to_settled(ref vault, 1); //no payout
    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());

    let (total_locked, total_unlocked, total_stashed) = vault
        .get_total_locked_and_unlocked_and_stashed_balance();
    let lp_stashed = vault.get_lp_stashed_balances(liquidity_providers);

    let starting_liq = current_round.starting_liquidity();
    let total_premiums = current_round.total_premiums();
    let unsold_liq = vault.get_unsold_liquidity(current_round.get_round_id());

    let total_remaining = starting_liq - unsold_liq - total_payout;
    let total_earned = total_premiums + unsold_liq;

    let expected_not_stashed_amount = divide_with_precision(1 * total_remaining, 3);
    let expected_stashed_amount = 2 * expected_not_stashed_amount;
    let expected_lp_stashed = array![expected_stashed_amount / 2, expected_stashed_amount / 2, 0];

    assert_eq!(total_locked, total_earned + expected_not_stashed_amount);
    assert_eq!(total_unlocked, 0);
    assert_eq!(total_stashed, expected_stashed_amount);
    assert_eq!(lp_stashed, expected_lp_stashed);
}

// Tests below have not been fixed

// Test queuing a withdrawal does not affect the stashed balances while round is Auctioning | Running
#[test]
#[available_gas(300000000)]
fn test_queueing_withdrawal_does_not_affect_stashed_balance_before_round_settle() {
    let mut rounds_to_run = 3;
    let (mut vault, _) = setup_facade();
    let liquidity_providers = liquidity_providers_get(3).span();
    let deposit_amount = 100 * decimals();
    let deposit_amounts = create_array_linear(deposit_amount, 3).span();

    while rounds_to_run
        .is_non_zero() {
            let mut round = vault.get_current_round();

            // Stashed balances while Auctioning before queueing
            let stashed_balances_before_auctioning = vault
                .get_lp_stashed_balances(liquidity_providers);
            accelerate_to_auctioning_custom(ref vault, liquidity_providers, deposit_amounts);

            // Liquidity provider 1 queues withdrawal
            vault.queue_withdrawal(*liquidity_providers.at(0), *deposit_amounts.at(0));
            vault.queue_withdrawal(*liquidity_providers.at(0), *deposit_amounts.at(0));

            // Stashed balances while Auctioning after queueing
            let stashed_balances_before_running = vault
                .get_lp_stashed_balances(liquidity_providers);
            accelerate_to_running(ref vault);

            // Liquidity provider 1 & 2 queue withdrawal
            vault.queue_withdrawal(*liquidity_providers.at(0), *deposit_amounts.at(0));
            vault.queue_withdrawal(*liquidity_providers.at(1), *deposit_amounts.at(1));

            let stashed_balances_before_settled = vault
                .get_lp_stashed_balances(liquidity_providers);
            accelerate_to_settled(ref vault, round.get_strike_price());

            let stashed_balances_after_settled = vault.get_lp_stashed_balances(liquidity_providers);

            // Assert stashed balances are unchanged until auction settled
            assert!(
                stashed_balances_before_auctioning == stashed_balances_before_running,
                "stashed before auctioning != stashed before running"
            );
            assert!(
                stashed_balances_before_running == stashed_balances_before_settled,
                "stashed before running != stashed before settled"
            );

            assert!(
                stashed_balances_before_settled.at(0) != stashed_balances_after_settled.at(0),
                "stashed before settled 1 == stashed after settled 1"
            );
            assert!(
                stashed_balances_before_settled.at(1) != stashed_balances_after_settled.at(1),
                "stashed before settled 2 == stashed after settled 2"
            );
            assert!(
                stashed_balances_before_settled.at(2) == stashed_balances_after_settled.at(2),
                "stashed before settled 3 != stashed after settled 3"
            );

            rounds_to_run -= 1;
        }
}


// Test stashed balance is correct after round settles
#[test]
#[available_gas(500000000)]
fn test_stashed_balance_correct_after_round_settles() {
    let (mut vault, _) = setup_facade();
    let liquidity_providers = liquidity_providers_get(3).span();
    let deposit_amount = 100 * decimals();
    let deposit_amounts = create_array_linear(deposit_amount, 3).span();

    /// ROUND 1

    let mut round1 = vault.get_current_round();
    let starting_deposits1 = vault.deposit_multiple(deposit_amounts, liquidity_providers).span();
    timeskip_and_start_auction(ref vault);
    accelerate_to_running(ref vault);

    let total_premiums1 = round1.total_premiums();
    let individual_premiums1 = get_portion_of_amount(starting_deposits1, total_premiums1).span();

    // Liquidity provider 1 & 2 queue withdrawal
    vault.queue_withdrawal(*liquidity_providers.at(0), *deposit_amounts.at(0));
    vault.queue_withdrawal(*liquidity_providers.at(1), *deposit_amounts.at(1));

    let total_payout1 = accelerate_to_settled(ref vault, 101 * round1.get_strike_price() / 100);
    let individual_payout1 = get_portion_of_amount(starting_deposits1, total_payout1).span();
    let stashed_balances_after_settled1 = vault.get_lp_stashed_balances(liquidity_providers).span();
    let unlocked_balances_after_settled1 = vault
        .get_lp_unlocked_balances(liquidity_providers)
        .span();

    // Assert stashed balances are correct after round settles
    let expected_stashed_amounts1 = array![
        *starting_deposits1.at(0) - *individual_payout1.at(0),
        *starting_deposits1.at(1) - *individual_payout1.at(1),
        0
    ]
        .span();
    // Assert unlocked balances are correct after round settles
    let expected_unlocked_amounts1 = array![
        *individual_premiums1.at(0),
        *individual_premiums1.at(1),
        *starting_deposits1.at(2) - *individual_payout1.at(2) + *individual_premiums1.at(2)
    ]
        .span();

    assert!(
        stashed_balances_after_settled1 == expected_stashed_amounts1,
        "stashed balances after settled 1 incorrect"
    );
    assert!(
        unlocked_balances_after_settled1 == expected_unlocked_amounts1,
        "unlocked balances after settled 1 incorrect"
    );

    /// ROUND 2

    let mut round2 = vault.get_current_round();
    let starting_deposits2 = vault
        .get_lp_unlocked_balances(liquidity_providers)
        .span(); //vault.deposit_multiple(deposit_amounts, liquidity_providers);
    timeskip_and_start_auction(ref vault);
    accelerate_to_running(ref vault);
    let total_premiums2 = round2.total_premiums();
    let individual_premiums2 = get_portion_of_amount(starting_deposits2, total_premiums2).span();

    // Liquidity provider 1 & 2 queue withdrawal
    vault.queue_withdrawal(*liquidity_providers.at(0), *starting_deposits2.at(0));
    vault.queue_withdrawal(*liquidity_providers.at(1), *starting_deposits2.at(1));

    let total_payout2 = accelerate_to_settled(ref vault, 101 * round2.get_strike_price() / 100);
    let individual_payouts2 = get_portion_of_amount(starting_deposits2, total_payout2).span();
    //println!("total_payout2:\n{:?}\n\n", total_payout2);
    let stashed_balances_after_settled2 = vault.get_lp_stashed_balances(liquidity_providers).span();
    let unlocked_balances_after_settled2 = vault
        .get_lp_unlocked_balances(liquidity_providers)
        .span();

    // Assert stashed balances are correct after round settles
    let expected_stashed_amounts2 = array![
        *stashed_balances_after_settled1.at(0)
            + *starting_deposits2.at(0)
            - *individual_payouts2.at(0),
        *stashed_balances_after_settled1.at(1)
            + *starting_deposits2.at(1)
            - *individual_payouts2.at(1),
        0
    ]
        .span();

    let expected_unlocked_amounts2 = array![
        *individual_premiums2.at(0),
        *individual_premiums2.at(1),
        *starting_deposits2.at(2) - *individual_payouts2.at(2) + *individual_premiums2.at(2)
    ]
        .span();

    // Assert unlocked balances are correct after round settles
    assert!(
        stashed_balances_after_settled2 == expected_stashed_amounts2,
        "stashed balances after settled 2 incorrect"
    );
    assert!(
        unlocked_balances_after_settled2 == expected_unlocked_amounts2,
        "unlocked balances after settled 2 incorrect"
    );
}
//// ended here

//// Test collecting stashed balance transfers eth to liquidity provider
//#[test]
//#[available_gas(50000000)]
//fn test_queiting_before_round_settles_does_nothing() {
//    let (mut vault, eth) = setup_facade();
//    let liquidity_provider = liquidity_provider_1();
//    let unlocked_amount_after = vault.withdraw(withdraw_amount, liquidity_provider);
//    assert(
//        unlocked_amount_after == unlocked_amount_before - withdraw_amount, 'unlocked amount 3 wrong'
//    );
//}


