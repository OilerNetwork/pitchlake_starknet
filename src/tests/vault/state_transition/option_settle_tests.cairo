use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}, contract_address::ContractAddressZeroable,
};
use openzeppelin::{
    utils::serde::SerializedAppend,
    token::erc20::interface::{
        IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
        IERC20SafeDispatcherTrait,
    }
};
use pitch_lake_starknet::{
    contracts::{
        vault::{
            IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault,
            IVaultSafeDispatcherTrait
        },
        eth::Eth,
        option_round::{
            IOptionRoundDispatcher, IOptionRoundDispatcherTrait, OptionRound::OptionRoundError
        },
        market_aggregator::{
            IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait,
            IMarketAggregatorSafeDispatcher, IMarketAggregatorSafeDispatcherTrait
        },
    },
    tests::{
        utils::{
            utils::{
                get_portion_of_amount, split_spreads, create_array_linear, create_array_gradient,
                get_erc20_balances, sum_u256_array,
            },
            event_helpers::{
                clear_event_logs, assert_event_option_settle, assert_event_transfer,
                assert_no_events_left, pop_log
            },
            accelerators::{
                accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled,
                accelerate_to_auctioning_custom
            },
            test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                liquidity_providers_get, liquidity_provider_3, liquidity_provider_4,
            },
            variables::{decimals}, setup::{setup_facade},
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{
                    OptionRoundParams, OptionRoundState, OptionRoundFacade, OptionRoundFacadeTrait
                },
            },
            mocks::mock_market_aggregator::{
                MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
                IMarketAggregatorSetterDispatcherTrait
            },
        },
    }
};
use debug::PrintTrait;


/// Failures ///

// Test settling an option round fails if the current round is not running
// @note Check whether all should return the same error felt
#[test]
#[available_gas(10000000)]
fn test_settling_option_round_while_current_round_auctioning_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);

    let expected_error: felt252 = OptionRoundError::OptionSettlementDateNotReached.into();
    // Try to end auction after it has already ended
    match vault_facade.settle_option_round_raw() {
        Result::Ok(_) => { panic!("Error expected") },
        Result::Err(err) => { assert(err.into() == expected_error, 'Error Mismatch') }
    }
// Settle option round before expiry
}

// Test settling an option if the current round is not running fails
// @dev First test is when current round is auctioning, this is when
// current round is settled
#[test]
#[available_gas(10000000)]
fn test_settling_option_round_while_current_settled_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);
    accelerate_to_settled(ref vault_facade, 0x123);

    // Settle option round before expiry
    let expected_error: felt252 = OptionRoundError::OptionSettlementDateNotReached.into();
    // Try to end auction after it has already ended
    match vault_facade.settle_option_round_raw() {
        Result::Ok(_) => { panic!("Error expected") },
        Result::Err(err) => { assert(err.into() == expected_error, 'Error Mismatch') }
    }
}

// Test settling an option round before the option expiry date fails
#[test]
#[available_gas(10000000)]
fn test_settling_option_round_before_settlement_date_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);

    // Settle option round before expiry
    let expected_error: felt252 = OptionRoundError::OptionSettlementDateNotReached.into();
    // Try to end auction after it has already ended
    match vault_facade.settle_option_round_raw() {
        Result::Ok(_) => { panic!("Error expected") },
        Result::Err(err) => { assert(err.into() == expected_error, 'Error Mismatch') }
    }
}


/// Event Tests ///

// Test settling an option round emits the correct event
#[test]
#[available_gas(10000000)]
fn test_option_round_settled_event() {
    let mut rounds_to_run = 3;
    let (mut vault, _) = setup_facade();

    loop {
        match rounds_to_run {
            0 => { break (); },
            _ => {
                accelerate_to_auctioning(ref vault);
                accelerate_to_running(ref vault);

                let mut round = vault.get_current_round();
                let settlement_price = round.get_strike_price() + rounds_to_run.into();
                accelerate_to_settled(ref vault, settlement_price);
                // Check the event emits correctly
                assert_event_option_settle(round.contract_address(), settlement_price);

                rounds_to_run -= 1;
            },
        }
    }
}


/// State Tests ///

/// Round ids/states

// Test settling an option round does not change the current round id
#[test]
#[available_gas(10000000)]
fn test_settle_option_round_does_not_update_current_and_next_round_ids() {
    let rounds_to_run: felt252 = 3;
    let mut i = rounds_to_run;
    let (mut vault, _) = setup_facade();
    loop {
        match i {
            0 => { break (); },
            _ => {
                accelerate_to_auctioning(ref vault);
                accelerate_to_running(ref vault);

                assert(
                    vault.get_current_round_id() == 1 + (rounds_to_run - i).into(),
                    'current round id before wrong'
                );

                accelerate_to_settled(ref vault, 0);

                assert(
                    vault.get_current_round_id() == 1 + (rounds_to_run - i).into(),
                    'current round id after wrong'
                );

                i -= 1;
            },
        }
    }
}

// Test settling an option round updates the current round's state
// @note should this be a state transition test in option round tests
#[test]
#[available_gas(10000000)]
fn test_settle_option_round_updates_round_state() {
    let mut rounds_to_run: felt252 = 3;
    let (mut vault, _) = setup_facade();
    loop {
        match rounds_to_run {
            0 => { break (); },
            _ => {
                accelerate_to_auctioning(ref vault);
                accelerate_to_running(ref vault);
                let mut current_round = vault.get_current_round();

                assert(
                    current_round.get_state() == OptionRoundState::Running,
                    'current round shd be running'
                );

                accelerate_to_settled(ref vault, 0);

                assert(
                    current_round.get_state() == OptionRoundState::Settled,
                    'current round shd be settled'
                );

                rounds_to_run -= 1;
            },
        }
    }
}

/// Liquidity

// Test settling transfers the payout from the vault to the option round
#[test]
#[available_gas(10000000)]
fn test_settling_option_round_transfers_payout() {
    let mut rounds_to_run: felt252 = 3;
    let (mut vault, eth) = setup_facade();
    loop {
        match rounds_to_run {
            0 => { break (); },
            _ => {
                accelerate_to_auctioning(ref vault);
                accelerate_to_running(ref vault);

                // Vault and round eth balances before the round settles
                let mut current_round = vault.get_current_round();
                let round_balance_before = eth.balance_of(current_round.contract_address());
                let vault_balance_before = eth.balance_of(vault.contract_address());

                // Settle the round with a payout
                let total_payout = accelerate_to_settled(
                    ref vault, 2 * current_round.get_strike_price()
                );

                // Vault and round eth balances after auction ends
                let round_balance_after = eth.balance_of(current_round.contract_address());
                let vault_balance_after = eth.balance_of(vault.contract_address());

                // Check the payout transfers from vault to round
                assert(
                    round_balance_after == round_balance_before + total_payout,
                    'round eth bal. wrong'
                );
                assert(
                    vault_balance_after == vault_balance_before - total_payout,
                    'vault eth bal. wrong'
                );

                rounds_to_run -= 1;
            },
        }
    }
}

// Test l
// Test that the vualt and LP spreads update when the round settles
#[test]
#[available_gas(10000000)]
fn test_settling_option_round_updates_locked_and_unlocked_balances() {
    let (mut vault, _) = setup_facade();
    let mut liquidity_providers = liquidity_providers_get(4).span();
    // Amounts to deposit: [100, 200, 300, 400]
    let mut deposit_amounts = create_array_gradient(
        100 * decimals(), 100 * decimals(), liquidity_providers.len()
    )
        .span();
    let total_deposits = sum_u256_array(deposit_amounts);
    accelerate_to_auctioning_custom(ref vault, liquidity_providers, deposit_amounts);

    // End auction
    let mut current_round = vault.get_current_round();
    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
    let total_premiums = options_sold * clearing_price;
    let mut liquidity_provider_premiums = get_portion_of_amount(deposit_amounts, total_premiums)
        .span();

    // Vault and liquidity provider balances before auction starts
    let mut liquidity_providers_locked_before = vault.get_lp_locked_balances(liquidity_providers);
    let mut liquidity_providers_unlocked_before = vault
        .get_lp_unlocked_balances(liquidity_providers);
    let (vault_locked_before, vault_unlocked_before) = vault.get_balance_spread();

    // Settle the round with a payout
    let total_payouts = accelerate_to_settled(ref vault, 2 * current_round.get_strike_price());
    let remaining_liquidity = total_deposits + total_premiums - total_payouts;
    let mut individual_remaining_liquidty = get_portion_of_amount(
        deposit_amounts, remaining_liquidity
    )
        .span();

    // Vault and liquidity provider balances after auction starts
    let mut liquidity_providers_locked_after = vault.get_lp_locked_balances(liquidity_providers);
    let mut liquidity_providers_unlocked_after = vault
        .get_lp_unlocked_balances(liquidity_providers);
    let (vault_locked_after, vault_unlocked_after) = vault.get_balance_spread();

    // Check vault balance
    assert(
        (vault_locked_before, vault_unlocked_before) == (total_deposits, total_premiums),
        'vault balance before wrong'
    );
    assert(
        (vault_locked_after, vault_unlocked_after) == (0, remaining_liquidity),
        'vault balance after wrong'
    );

    // Check liquidity provider balances
    loop {
        match liquidity_providers_locked_before.pop_front() {
            Option::Some(lp_locked_balance_before) => {
                let lp_locked_balance_after = liquidity_providers_locked_after.pop_front().unwrap();
                let lp_unlocked_balance_before = liquidity_providers_unlocked_before
                    .pop_front()
                    .unwrap();
                let lp_unlocked_balance_after = liquidity_providers_unlocked_after
                    .pop_front()
                    .unwrap();
                let lp_deposit_amount = deposit_amounts.pop_front().unwrap();
                let lp_premium = liquidity_provider_premiums.pop_front().unwrap();
                let lp_remaining_liquidity = individual_remaining_liquidty.pop_front().unwrap();

                assert(
                    (
                        lp_locked_balance_before, lp_unlocked_balance_before
                    ) == (*lp_deposit_amount, *lp_premium),
                    'LP balance before wrong'
                );
                assert(
                    (
                        lp_locked_balance_after, lp_unlocked_balance_after
                    ) == (0, *lp_remaining_liquidity),
                    'LP balance after wrong'
                );
            },
            Option::None => { break (); }
        }
    };
}
// @note revisit later if needed
//// Test that the vault and LP spreads update when the round settles with more complex behavior
//#[test]
//#[available_gas(10000000)]
//fn test_settle_option_round_updates_vault_and_lp_spreads_complex() {
//    // Accelerate through round 1 with premiums and a payout
//    let (mut vault, _) = setup_facade();
//    let mut lps = liquidity_providers_get(4).span();
//    let round1_deposits = create_array_gradient(100 * decimals(), 100 * decimals(), lps.len())
//        .span(); // (100, 200, 300, 400)
//    let starting_liquidity1 = sum_u256_array(round1_deposits);
//    accelerate_to_auctioning_custom(ref vault, lps, round1_deposits);
//    let mut round1 = vault.get_current_round();
//    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
//    let total_premiums1 = clearing_price * options_sold;
//    let total_payout1 = accelerate_to_settled(ref vault, 2 * round1.get_strike_price());
//    // Total and individual remaining liquidity amounts after round 1
//    let remaining_liquidity1 = starting_liquidity1 + total_premiums1 - total_payout1;
//    let mut individual_remaining_liquidity1 = get_portion_of_amount(
//        round1_deposits, remaining_liquidity1
//    )
//        .span();
//
//    // Lp3 withdraws from premiums, lp4 adds a topup
//    let lp3 = liquidity_provider_3();
//    let lp4 = liquidity_provider_4();
//    let withdraw_amount = 1;
//    let topup_amount = 100 * decimals();
//    vault.withdraw(withdraw_amount, lp3);
//    vault.deposit(topup_amount, lp4);
//    // Start round 2' auction with no additional deposits
//    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());
//    let mut round2 = vault.get_current_round();
//    // Create array of round2's deposits
//    let mut round2_deposits = array![
//        *individual_remaining_liquidity1[0],
//        *individual_remaining_liquidity1[1],
//        *individual_remaining_liquidity1[2] - withdraw_amount,
//        *individual_remaining_liquidity1[3] + topup_amount
//    ]
//        .span();
//    let starting_liquidity2 = sum_u256_array(round2_deposits);
//
//    // End round 2's auction
//    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
//    let total_premiums2 = clearing_price * options_sold;
//    let mut individual_premiums2 = get_portion_of_amount(round2_deposits, total_premiums2).span();
//
//    // Vault and LP spreads before round 2 settles
//    let mut lp_spreads_before = vault.get_lp_balance_spreads(lps).span();
//    let vault_spread_before = vault.get_balance_spread();
//    // Settle round 2 with a payout
//    let total_payout2 = accelerate_to_settled(ref vault, 2 * round2.get_strike_price());
//    let remaining_liquidity2 = starting_liquidity2 + total_premiums2 - total_payout2;
//    let mut individual_remaining_liquidity2 = get_portion_of_amount(
//        round2_deposits, remaining_liquidity2
//    )
//        .span();
//    // Vault and LP spreads after the round 2 settles
//    let mut lp_spreads_after = vault.get_lp_balance_spreads(lps).span();
//    let vault_spread_after = vault.get_balance_spread();
//
//    // Check vault spreads
//    assert(
//        vault_spread_before == (starting_liquidity2, total_premiums2), 'vault spread before wrong'
//    );
//    assert(vault_spread_after == (0, remaining_liquidity2), 'vault spread after wrong');
//    // Check LP spreads
//    loop {
//        match lp_spreads_before.pop_front() {
//            Option::Some(lp_spread_before) => {
//                let lp_spread_after = lp_spreads_after.pop_front().unwrap();
//                let lp_starting_liquidity2 = round2_deposits.pop_front().unwrap();
//                let lp_premiums2 = individual_premiums2.pop_front().unwrap();
//                let lp_remaining_liquidity2 = individual_remaining_liquidity2.pop_front().unwrap();
//                assert(
//                    *lp_spread_before == (*lp_starting_liquidity2, *lp_premiums2),
//                    'LP spread before wrong'
//                );
//                assert(*lp_spread_after == (0, *lp_remaining_liquidity2), 'LP spread after wrong');
//            },
//            Option::None => { break (); }
//        }
//    }
//}


