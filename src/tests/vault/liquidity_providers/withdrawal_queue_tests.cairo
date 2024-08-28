use core::option::OptionTrait;
use core::array::SpanTrait;
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcherTrait,};
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use pitch_lake_starknet::{
    types::{Errors, Consts::BPS}, library::eth::Eth, vault::{contract::Vault},
    tests::{
        utils::{
            helpers::{
                general_helpers::{
                    get_erc20_balances, get_erc20_balance, sum_u256_array, create_array_gradient,
                    create_array_linear, to_wei, to_wei_multi, get_portion_of_amount,
                    assert_u256s_equal_in_range,
                },
                event_helpers::{
                    pop_log, assert_no_events_left, assert_event_transfer,
                    assert_event_vault_withdrawal, clear_event_logs,
                    assert_event_queued_liquidity_collected, assert_event_withdrawal_queued
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

#[test]
#[available_gas(300000000)]
fn test_queueing_part_of_position_with_unsold() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();

    /// Deposit 100
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );
    /// Only sell 1/2 of the coll.
    accelerate_to_running_custom(
        ref vault,
        array![option_bidder_buyer_1()].span(),
        array![current_round.get_total_options_available() / 2].span(),
        array![current_round.get_reserve_price()].span()
    );

    // Queue 33% for stash
    vault.queue_withdrawal(liquidity_provider, deposit_amount / 3);

    // End round with no payout
    let payout = accelerate_to_settled(ref vault, 1);

    let (lp_locked, lp_unlocked, lp_stashed) = vault
        .get_lp_locked_and_unlocked_and_stashed_balance(liquidity_provider);
    let lp_total = lp_locked + lp_unlocked + lp_stashed;
    let vault_total = vault.get_total_balance();

    let unsold_liq = deposit_amount / 2;
    let premiums = current_round.total_premiums();
    let remaining_liq = deposit_amount - unsold_liq - payout;

    let expected_locked = 0;
    // remaining * stashed_percentage
    let expected_stashed = remaining_liq / 3;
    // gain + (remaining * not_stashed_percentage)
    let expected_unlocked = premiums + unsold_liq + (2 * remaining_liq / 3);
    let expected_total = deposit_amount - payout + premiums;

    assert_eq!(lp_locked, expected_locked);
    assert_eq!(lp_stashed, expected_stashed);
    assert_eq!(lp_unlocked, expected_unlocked);
    assert_u256s_equal_in_range(lp_total, expected_total, 1);

    assert_eq!(lp_locked, vault.get_total_locked_balance());
    assert_eq!(lp_stashed, vault.get_total_stashed_balance());
    assert_u256s_equal_in_range(lp_unlocked, vault.get_total_unlocked_balance(), 1);
    assert_u256s_equal_in_range(vault_total, lp_total, 1);
}

#[test]
#[available_gas(300000000)]
fn test_queueing_part_of_position_with_unsold_and_max_payout() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();

    /// Deposit 100
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );
    /// Only sell 1/3 of the coll.
    accelerate_to_running_custom(
        ref vault,
        array![option_bidder_buyer_1()].span(),
        array![current_round.get_total_options_available() / 3].span(),
        array![current_round.get_reserve_price()].span()
    );

    // Queue 20% for stash
    let queue_amount = deposit_amount / 5;
    vault.queue_withdrawal(liquidity_provider, queue_amount);

    // End round with max payout
    let payout = accelerate_to_settled(ref vault, 10 * current_round.get_strike_price());

    let (lp_locked, lp_unlocked, lp_stashed) = vault
        .get_lp_locked_and_unlocked_and_stashed_balance(liquidity_provider);
    let lp_total = vault.get_lp_total_balance(liquidity_provider);

    let unsold_liq = current_round.unsold_liquidity();
    let premiums = current_round.total_premiums();
    let remaining_liq = deposit_amount - unsold_liq - payout;

    let expected_locked = 0;
    let expected_stashed = (remaining_liq * queue_amount) / deposit_amount;
    let expected_not_stashed = remaining_liq - expected_stashed;
    // gain + (remaining * not_queued_percentage)
    let expected_unlocked = premiums + unsold_liq + expected_not_stashed;
    let expected_total = deposit_amount - payout + premiums;

    assert_eq!(lp_total, expected_total);
    assert_eq!(lp_locked, expected_locked);
    assert_eq!(lp_stashed, expected_stashed);
    assert_eq!(lp_unlocked, expected_unlocked);

    assert_eq!(vault.get_total_locked_balance(), lp_locked);
    assert_eq!(vault.get_total_stashed_balance(), lp_stashed);
    assert_eq!(vault.get_total_unlocked_balance(), lp_unlocked);
    assert_eq!(vault.get_total_balance(), lp_total);
}


// Test that when an LP queues a withdrawal, it does not roll over after round settles
#[test]
#[available_gas(300000000)]
fn test_stashed_liquidity_does_not_roll_over() {
    /// ROUND 1 ///
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();

    /// Deposit 100
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );
    accelerate_to_running_custom(
        ref vault,
        array![option_bidder_buyer_1()].span(),
        array![current_round.get_total_options_available() / 2].span(),
        array![current_round.get_reserve_price()].span()
    );
    let starting_liq = current_round.starting_liquidity();
    let premiums = current_round.total_premiums();
    let unsold_liq = vault.get_unsold_liquidity(current_round.get_round_id());

    // Queue 100/100 for stash
    vault.queue_withdrawal(liquidity_provider, deposit_amount);

    // Start round 2
    let total_payout = accelerate_to_settled(
        ref vault, current_round.get_strike_price()
    ); //no payout
    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());

    let (total_locked, total_unlocked, total_stashed) = vault
        .get_total_locked_and_unlocked_and_stashed_balance();
    let lp_stashed = vault.get_lp_stashed_balance(liquidity_provider);

    let total_remaining = starting_liq - unsold_liq - total_payout;
    let total_earned = premiums + unsold_liq;

    assert_eq!(total_locked, total_earned);
    assert_eq!(total_unlocked, 0);
    assert_eq!(total_stashed, total_remaining);
    assert_eq!(lp_stashed, total_remaining);

    /// ROUND 2 ///
    let mut current_round2 = vault.get_current_round();
    let starting_liq2 = current_round2.starting_liquidity();

    // Queue withdrawal
    let deposit_amount2 = vault.get_lp_locked_balance(liquidity_provider);
    vault.queue_withdrawal(liquidity_provider, deposit_amount2);

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
        array![current_round.get_total_options_available() / 2].span(),
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

    let expected_not_stashed_amount = total_remaining / 3;
    let expected_stashed_amount = 2 * expected_not_stashed_amount;
    let expected_lp_stashed = array![expected_stashed_amount / 2, expected_stashed_amount / 2, 0];

    assert_eq!(total_locked, total_earned + expected_not_stashed_amount);
    assert_eq!(total_unlocked, 0);
    assert_eq!(total_stashed, expected_stashed_amount);
    assert_eq!(lp_stashed, expected_lp_stashed);
}

// Test queueing for more than position value at start fails
#[test]
#[available_gas(300000000)]
fn test_queueing_more_than_position_value_at_start_fails() {
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
        array![current_round.get_total_options_available() / 2].span(),
        array![current_round.get_reserve_price()].span()
    );

    vault.queue_withdrawal(liquidity_provider, deposit_amount);
    let err = Errors::QueueingMoreThanPositionValue;
    vault.queue_withdrawal_expect_error(liquidity_provider, deposit_amount + 1, err);
}

// Test that queued amount can update in either direction
#[test]
#[available_gas(300000000)]
fn test_queueing_withdrawal_amount_can_be_updated() {
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
        array![current_round.get_total_options_available() / 2].span(),
        array![current_round.get_reserve_price()].span()
    );

    vault.queue_withdrawal(liquidity_provider, deposit_amount);
    let queued1 = vault.get_lp_queued_balance(liquidity_provider, current_round.get_round_id());
    vault.queue_withdrawal(liquidity_provider, deposit_amount / 2);
    let queued2 = vault.get_lp_queued_balance(liquidity_provider, current_round.get_round_id());
    vault.queue_withdrawal(liquidity_provider, deposit_amount - 1);
    let queued3 = vault.get_lp_queued_balance(liquidity_provider, current_round.get_round_id());

    assert_eq!(queued1, deposit_amount);
    assert_eq!(queued2, deposit_amount / 2);
    assert_eq!(queued3, deposit_amount - 1);
}

// Test queued amount is 0 after round settles
#[test]
#[available_gas(300000000)]
fn test_queued_amount_is_0_after_round_settles() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let liquidity_providers = liquidity_providers_get(3).span();
    let deposit_amounts = array![100 * decimals(), 200 * decimals(), 300 * decimals()].span();
    accelerate_to_auctioning_custom(ref vault, liquidity_providers, deposit_amounts);
    accelerate_to_running_custom(
        ref vault,
        array![option_bidder_buyer_1()].span(),
        array![current_round.get_total_options_available() / 2].span(),
        array![current_round.get_reserve_price()].span()
    );

    vault.queue_multiple_withdrawals(liquidity_providers, deposit_amounts);

    let c_id = current_round.get_round_id();
    let queued_before_settle = vault
        .get_lp_queued_balances(liquidity_providers, array![c_id, c_id, c_id].span());
    accelerate_to_settled(ref vault, 1);
    let queued_after_settle = vault
        .get_lp_queued_balances(liquidity_providers, array![c_id, c_id, c_id].span());

    assert_eq!(queued_before_settle.span(), deposit_amounts);
    assert_eq!(queued_after_settle.span(), deposit_amounts);
}


// Test queuing 0 puts nothing in stash
#[test]
#[available_gas(300000000)]
fn test_queuing_0_puts_nothing_in_stash() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );
    accelerate_to_running(ref vault);
    let premiums = current_round.total_premiums();

    vault.queue_withdrawal(liquidity_provider, deposit_amount);
    vault.queue_withdrawal(liquidity_provider, 0);

    let (locked_before, unlocked_before, stashed_before) = vault
        .get_lp_locked_and_unlocked_and_stashed_balance(liquidity_provider);
    let queued_before = vault
        .get_lp_queued_balance(liquidity_provider, current_round.get_round_id());
    accelerate_to_settled(ref vault, 1);

    let (locked_after, unlocked_after, stashed_after) = vault
        .get_lp_locked_and_unlocked_and_stashed_balance(liquidity_provider);
    let queued_after = vault
        .get_lp_queued_balance(liquidity_provider, current_round.get_round_id());

    assert_eq!(locked_before, deposit_amount);
    assert_eq!(locked_after, 0);

    assert_eq!(unlocked_before, premiums);
    assert_eq!(unlocked_after, premiums + deposit_amount);

    assert_eq!(queued_before, 0);
    assert_eq!(queued_after, 0);

    assert_eq!(stashed_before, 0);
    assert_eq!(stashed_after, 0);
}

// Test queuing some puts some in stash and rest in unlocked
#[test]
#[available_gas(300000000)]
fn test_queuing_some_gets_stashed() {
    let (mut vault, eth) = setup_facade();
    let mut current_round = vault.get_current_round();
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );
    accelerate_to_running(ref vault);
    let premiums = current_round.total_premiums();

    vault.queue_withdrawal(liquidity_provider, deposit_amount / 3);

    let (locked_before, unlocked_before, stashed_before) = vault
        .get_lp_locked_and_unlocked_and_stashed_balance(liquidity_provider);
    let queued_before = vault
        .get_lp_queued_balance(liquidity_provider, current_round.get_round_id());
    accelerate_to_settled(ref vault, 1);

    let (locked_after, unlocked_after, stashed_after) = vault
        .get_lp_locked_and_unlocked_and_stashed_balance(liquidity_provider);
    let queued_after = vault
        .get_lp_queued_balance(liquidity_provider, current_round.get_round_id());

    assert_eq!(locked_before, deposit_amount);
    assert_eq!(locked_after, 0);

    assert_eq!(unlocked_before, premiums);
    assert_eq!(unlocked_after, premiums + deposit_amount - (deposit_amount / 3));

    assert_eq!(queued_before, deposit_amount / 3);
    assert_eq!(queued_after, deposit_amount / 3);

    assert_eq!(stashed_before, 0);
    assert_eq!(stashed_after, deposit_amount / 3);

    assert_eq!(
        get_erc20_balance(eth.contract_address, vault.contract_address()),
        deposit_amount + premiums - 0 // payout is 0
    );
}

// Test claiming queued liquidity transfers eth
#[test]
#[available_gas(300000000)]
fn test_claiming_queued_liquidity_transfers_eth() {
    let (mut vault, eth) = setup_facade();
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );
    accelerate_to_running(ref vault);
    vault.queue_withdrawal(liquidity_provider, deposit_amount / 3);
    accelerate_to_settled(ref vault, 1);

    let eth_balance_before = get_erc20_balance(eth.contract_address, liquidity_provider);
    vault.claim_queued_liquidity(liquidity_provider);
    let eth_balance_after = get_erc20_balance(eth.contract_address, liquidity_provider);

    assert_eq!(eth_balance_after, eth_balance_before + (deposit_amount / 3));
}

// Test claiming queued liquidity sets stashed to 0
#[test]
#[available_gas(300000000)]
fn test_claiming_queued_liquidity_sets_stashed_to_0() {
    let (mut vault, _) = setup_facade();
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );
    accelerate_to_running(ref vault);
    vault.queue_withdrawal(liquidity_provider, deposit_amount / 3);
    accelerate_to_settled(ref vault, 1);

    let stashed_balance_before = vault.get_lp_stashed_balance(liquidity_provider);
    vault.claim_queued_liquidity(liquidity_provider);
    let stashed_balance_after = vault.get_lp_stashed_balance(liquidity_provider);

    assert_eq!(stashed_balance_before, deposit_amount / 3);
    assert_eq!(stashed_balance_after, 0);
}

// Test claiming queued liquidity twice does nothing
#[test]
#[available_gas(300000000)]
fn test_claiming_queued_liquidity_twice_does_nothing() {
    let (mut vault, eth) = setup_facade();
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );
    accelerate_to_running(ref vault);
    vault.queue_withdrawal(liquidity_provider, deposit_amount / 3);
    accelerate_to_settled(ref vault, 1);

    vault.claim_queued_liquidity(liquidity_provider);
    let eth_balance_before = get_erc20_balance(eth.contract_address, liquidity_provider);
    let stashed_balance_before = vault.get_lp_stashed_balance(liquidity_provider);
    vault.claim_queued_liquidity(liquidity_provider);
    let eth_balance_after = get_erc20_balance(eth.contract_address, liquidity_provider);
    let stashed_balance_after = vault.get_lp_stashed_balance(liquidity_provider);

    assert_eq!(eth_balance_after, eth_balance_before);
    assert_eq!(stashed_balance_after, stashed_balance_before);
}

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
#[available_gas(900000000)]
fn test_stashed_balance_correct_after_round_settles() {
    let (mut vault, eth) = setup_facade();
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

    assert_eq!(stashed_balances_after_settled1, expected_stashed_amounts1,);
    assert_eq!(unlocked_balances_after_settled1, expected_unlocked_amounts1,);

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
        *starting_deposits2.at(0)
            - *individual_payouts2.at(0)
            + *stashed_balances_after_settled1.at(0),
        *starting_deposits2.at(1)
            - *individual_payouts2.at(1)
            + *stashed_balances_after_settled1.at(1),
        0
    ]
        .span();
    let expected_unlocked_amounts2 = array![
        *individual_premiums2.at(0),
        *individual_premiums2.at(1),
        *starting_deposits2.at(2) - *individual_payouts2.at(2) + *individual_premiums2.at(2)
    ]
        .span();

    // Check eth balance checks out
    assert_eq!(
        get_erc20_balance(eth.contract_address, vault.contract_address()),
        sum_u256_array(deposit_amounts)
            + total_premiums1
            - total_payout1
            + total_premiums2
            - total_payout2
    );
    // Assert stashed & unlocked balances are correct after round settles
    let mut i = 0;
    while i < 3 {
        assert_u256s_equal_in_range(
            *stashed_balances_after_settled2.at(i), *expected_stashed_amounts2.at(i), 1
        );
        assert_u256s_equal_in_range(
            *unlocked_balances_after_settled2.at(i), *expected_unlocked_amounts2.at(i), 1
        );
        i += 1;
    };
//    assert_eq!(stashed_balances_after_settled2, expected_stashed_amounts2,);
//    assert_eq!(unlocked_balances_after_settled2, expected_unlocked_amounts2,);
}


// Test queueing withdrawal with next round deposit
#[test]
#[available_gas(500000000)]
fn test_unstashed_liquidity_adds_to_next_round_deposits() {
    let (mut vault, eth) = setup_facade();
    let mut current_round = vault.get_current_round();
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );
    accelerate_to_running(ref vault);
    let premiums = current_round.total_premiums();

    let topup_amount = 2 * deposit_amount;
    vault.deposit(topup_amount, liquidity_provider);
    vault.queue_withdrawal(liquidity_provider, deposit_amount / 3);

    let (locked_before, unlocked_before, stashed_before) = vault
        .get_lp_locked_and_unlocked_and_stashed_balance(liquidity_provider);
    let queued_before = vault
        .get_lp_queued_balance(liquidity_provider, current_round.get_round_id());
    accelerate_to_settled(ref vault, 1);

    let (locked_after, unlocked_after, stashed_after) = vault
        .get_lp_locked_and_unlocked_and_stashed_balance(liquidity_provider);
    let queued_after = vault
        .get_lp_queued_balance(liquidity_provider, current_round.get_round_id());

    assert_eq!(locked_before, deposit_amount);
    assert_eq!(locked_after, 0);

    assert_eq!(unlocked_before, premiums + 2 * deposit_amount);
    assert_eq!(unlocked_after, premiums + deposit_amount - (deposit_amount / 3) + topup_amount);

    assert_eq!(queued_before, deposit_amount / 3);
    assert_eq!(queued_after, deposit_amount / 3);

    assert_eq!(stashed_before, 0);
    assert_eq!(stashed_after, deposit_amount / 3);

    assert_eq!(
        get_erc20_balance(eth.contract_address, vault.contract_address()),
        deposit_amount + premiums - 0 + topup_amount // payout is 0
    );
}


#[test]
#[available_gas(500000000)]
fn test_queueing_multiple_rounds_stashed_amount_no_payouts() {
    let (mut vault, eth) = setup_facade();
    let mut current_round = vault.get_current_round();
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();

    /// Round 1
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );
    accelerate_to_running(ref vault);
    let premiums = current_round.total_premiums();
    vault.queue_withdrawal(liquidity_provider, deposit_amount);
    accelerate_to_settled(ref vault, current_round.get_strike_price());
    /// Round 2
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());
    accelerate_to_running(ref vault);
    let premiums2 = current_round.total_premiums();
    vault.queue_withdrawal(liquidity_provider, premiums);
    accelerate_to_settled(ref vault, current_round.get_strike_price());
    /// Round 3
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());
    accelerate_to_running(ref vault);
    let premiums3 = current_round.total_premiums();
    vault.queue_withdrawal(liquidity_provider, premiums2);
    accelerate_to_settled(ref vault, current_round.get_strike_price());

    let lp_stashed = vault.get_lp_stashed_balance(liquidity_provider);

    // after round 1 deposit is stashed & premiums roll over
    // after round 2 premiums are stashed and premiums2 roll over
    // after round 3 premiums2 are stashed and premiums3 roll over
    assert_eq!(lp_stashed, deposit_amount + premiums + premiums2);

    assert_eq!(
        get_erc20_balance(eth.contract_address, vault.contract_address()),
        deposit_amount + premiums + premiums2 + premiums3
    );
    assert_eq!(vault.get_total_balance(), deposit_amount + premiums + premiums2 + premiums3)
}

#[test]
#[available_gas(500000000)]
fn test_queueing_multiple_rounds_stashed_amount_payouts() {
    let (mut vault, eth) = setup_facade();
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();

    /// Round 1
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );
    accelerate_to_running(ref vault);
    let premiums = current_round.total_premiums();

    vault.queue_withdrawal(liquidity_provider, deposit_amount);
    let payout = accelerate_to_settled(ref vault, 110 * current_round.get_strike_price() / 100);
    /// Round 2
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());
    accelerate_to_running(ref vault);
    let premiums2 = current_round.total_premiums();

    vault.queue_withdrawal(liquidity_provider, premiums);
    let payout2 = accelerate_to_settled(ref vault, 150 * current_round.get_strike_price() / 100);
    /// Round 3
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());
    accelerate_to_running(ref vault);
    let premiums3 = current_round.total_premiums();

    vault.queue_withdrawal(liquidity_provider, premiums2);
    let payout3 = accelerate_to_settled(ref vault, 250 * current_round.get_strike_price() / 100);

    // after round 1, deposit - payout is stashed & premiums roll over.
    // after round 2, premiums - payout2 are stashed and premiums2 roll over.
    // after round 3, premiums2 - payout3 are stashed and premiums3 roll over.
    let lp_stashed = vault.get_lp_stashed_balance(liquidity_provider);
    assert_eq!(lp_stashed, deposit_amount - payout + premiums - payout2 + premiums2 - payout3);

    assert_eq!(
        get_erc20_balance(eth.contract_address, vault.contract_address()),
        deposit_amount - payout + premiums - payout2 + premiums2 - payout3 + premiums3
    );
    assert_eq!(
        vault.get_total_balance(),
        deposit_amount - payout + premiums - payout2 + premiums2 - payout3 + premiums3
    );
}

#[test]
#[available_gas(500000000)]
fn test_queueing_multiple_rounds_stashed_amount_payouts_and_unsold() {
    let (mut vault, eth) = setup_facade();
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();

    /// Round 1
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );
    accelerate_to_running_custom(
        ref vault,
        array![option_bidder_buyer_1()].span(),
        array![current_round.get_total_options_available() / 2].span(),
        array![current_round.get_reserve_price()].span()
    );
    let premiums = current_round.total_premiums();
    let unsold = current_round.unsold_liquidity();
    let sold = current_round.starting_liquidity() - unsold;
    vault.queue_withdrawal(liquidity_provider, deposit_amount);
    let payout = accelerate_to_settled(ref vault, current_round.get_strike_price());

    /// Round 2
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());
    accelerate_to_running_custom(
        ref vault,
        array![option_bidder_buyer_1()].span(),
        array![current_round.get_total_options_available() / 2].span(),
        array![current_round.get_reserve_price()].span()
    );
    let premiums2 = current_round.total_premiums();
    let unsold2 = current_round.unsold_liquidity();
    let sold2 = current_round.starting_liquidity() - unsold2;
    vault.queue_withdrawal(liquidity_provider, premiums + unsold);
    let payout2 = accelerate_to_settled(ref vault, 150 * current_round.get_strike_price() / 100);
    /// Round 3
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());
    accelerate_to_running_custom(
        ref vault,
        array![option_bidder_buyer_1()].span(),
        array![current_round.get_total_options_available() / 2].span(),
        array![current_round.get_reserve_price()].span()
    );
    let premiums3 = current_round.total_premiums();
    let unsold3 = current_round.unsold_liquidity();
    let sold3 = current_round.starting_liquidity() - unsold3;
    vault.queue_withdrawal(liquidity_provider, premiums2 + unsold2);
    let payout3 = accelerate_to_settled(ref vault, 250 * current_round.get_strike_price() / 100);

    let lp_stashed = vault.get_lp_stashed_balance(liquidity_provider);

    // after round 1, sold - payout is stashed & premiums + unsold roll over.
    // after round 2, sold2 - payout2 are stashed and premiums2 + unsold2 roll over.
    // after round 3, sold3 - payout3 are stashed and premiums3 + unsold 3 roll over.
    let r1_remaining = (sold - payout);
    let r2_remaining = (sold2 - payout2);
    let r3_remaining = (sold3 - payout3);

    assert_eq!(lp_stashed, r1_remaining + r2_remaining + r3_remaining);
    assert_eq!(vault.get_total_balance(), lp_stashed + premiums3 + unsold3);
    assert_eq!(
        get_erc20_balance(eth.contract_address, vault.contract_address()),
        lp_stashed + premiums3 + unsold3
    );
}

// Test queueing withdrawal fires event
#[test]
#[available_gas(300000000)]
fn test_queueing_withdrawal_event() {
    let (mut vault, _) = setup_facade();
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );
    accelerate_to_running(ref vault);
    clear_event_logs(array![vault.contract_address()]);

    vault.queue_withdrawal(liquidity_provider, deposit_amount / 3);
    assert_event_withdrawal_queued(
        vault.contract_address(), liquidity_provider, deposit_amount / 3
    );

    vault.queue_withdrawal(liquidity_provider, 123);
    assert_event_withdrawal_queued(vault.contract_address(), liquidity_provider, 123);
}

// Test claiming stashed liquidity fires event
#[test]
#[available_gas(300000000)]
fn test_claiming_stashed_liquidity_event() {
    let (mut vault, _) = setup_facade();
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 100 * decimals();
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );
    accelerate_to_running(ref vault);
    vault.queue_withdrawal(liquidity_provider, deposit_amount / 3);
    accelerate_to_settled(ref vault, 1);
    clear_event_logs(array![vault.contract_address()]);

    vault.claim_queued_liquidity(liquidity_provider);
    assert_event_queued_liquidity_collected(
        vault.contract_address(), liquidity_provider, deposit_amount / 3
    );
}
