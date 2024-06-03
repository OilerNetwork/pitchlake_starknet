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
    vault::{
        IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault,
        IVaultSafeDispatcherTrait
    },
    eth::Eth, option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait},
    market_aggregator::{
        IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait,
        IMarketAggregatorSafeDispatcher, IMarketAggregatorSafeDispatcherTrait
    },
    tests::{
        utils::{
            utils::{
                get_portion_of_amount, split_spreads, create_array_linear, create_array_gradient,
                get_erc20_balances
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
                liquidity_providers_get
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

// Test option round cannot settle if the current round is auctioning
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'Options cannot settle before expiry',))]
fn test_settle_option_round_while_current_round_auctioning_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);

    // Settle option round before expiry
    vault_facade.settle_option_round();
}

// Test option round cannot settle if the current round is running and the option expiry date has not been reached
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'Options cannot settle before expiry',))]
fn test_settle_option_round_while_current_round_running_too_early_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);

    // Settle option round before expiry
    vault_facade.settle_option_round();
}

// Test option round cannot settle if the current round is settled
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'Options cannot settle before expiry',))]
fn test_settle_option_round_while_current_settled_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);
    accelerate_to_settled(ref vault_facade, 0x123);

    // Settle option round before expiry
    vault_facade.settle_option_round();
}


/// Event Tests ///

// Test settling an option round emits the correct event
#[test]
#[available_gas(10000000)]
fn test_settle_option_round_event() {
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

// Test when the option round settles the round state is updated
// @note should this be a state transition test in option round tests
#[test]
#[available_gas(10000000)]
fn test_settle_option_round_updates_round_states() {
    let mut rounds_to_run: felt252 = 3;
    let (mut vault, _) = setup_facade();
    loop {
        match rounds_to_run {
            0 => { break (); },
            _ => {
                accelerate_to_auctioning(ref vault);
                accelerate_to_running(ref vault);

                let (mut current_round, mut next_round) = vault.get_current_and_next_rounds();
                assert(
                    current_round.get_state() == OptionRoundState::Running,
                    'current round shd be running'
                );
                assert(next_round.get_state() == OptionRoundState::Open, 'next round shd be open');
                accelerate_to_settled(ref vault, 0);
                assert(
                    current_round.get_state() == OptionRoundState::Settled,
                    'current round shd be settled'
                );
                assert(next_round.get_state() == OptionRoundState::Open, 'next round shd be open');

                rounds_to_run -= 1;
            },
        }
    }
}

// Test when an option round settles the curent and next rounds do not change
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

// Test eth transfers from vault to option round when round settles with a payout
#[test]
#[available_gas(10000000)]
fn test_settle_option_round_sends_payout_to_round_eth_transfer() {
    let mut rounds_to_run: felt252 = 3;
    let (mut vault, eth_dispatcher) = setup_facade();
    loop {
        match rounds_to_run {
            0 => { break (); },
            _ => {
                accelerate_to_auctioning(ref vault);
                accelerate_to_running(ref vault);

                // Eth balances before the round settles
                let mut current_round = vault.get_current_round();
                let addrs = array![vault.contract_address(), current_round.contract_address()]
                    .span();
                let eth_balances_before = get_erc20_balances(
                    eth_dispatcher.contract_address, addrs
                );
                // Settle the round with a payout
                let total_payout = accelerate_to_settled(
                    ref vault, 2 * current_round.get_strike_price()
                );
                // Eth balances after the round settles
                let eth_balances_after = get_erc20_balances(eth_dispatcher.contract_address, addrs);
                // Check the eth transfers are correct (0: vault, 1: round)
                assert(
                    *eth_balances_after[0] == *eth_balances_before[0] - total_payout,
                    'vault eth bal. shd decrease'
                );
                assert(
                    *eth_balances_after[1] == *eth_balances_before[1] + total_payout,
                    'round eth bal. shd increase'
                );

                rounds_to_run -= 1;
            },
        }
    }
}


// Test that when the round settles, the payout comes from the vault's (and lp's) locked balance
#[test]
#[available_gas(10000000)]
fn test_settle_option_round_updates_vault_and_lp_spreads() {
    let mut rounds_to_run: felt252 = 3;
    let lps = liquidity_providers_get(2).span();
    let deposit_amounts = array![100 * decimals(), 200 * decimals()].span();

    let (mut vault, _) = setup_facade();
    loop {
        match rounds_to_run {
            0 => { break (); },
            _ => {
                accelerate_to_auctioning_custom(ref vault, lps, deposit_amounts);
                let (clearing_price, options_sold) = accelerate_to_running(ref vault);
                let total_premiums = options_sold * clearing_price;

                // Vault and LP spreads before round settles
                let mut current_round = vault.get_current_round();
                let (vault_locked_before, _) = vault.get_balance_spread();
                let mut lp_spreads_before = vault.get_lp_balance_spreads(lps).span();
                // Settle the round with a payout
                let total_payout = accelerate_to_settled(
                    ref vault, 2 * current_round.get_strike_price()
                );
                // Vault and LP spreads after round settles
                let vault_spread_after = vault.get_balance_spread();
                let mut lp_spreads_after = vault.get_lp_balance_spreads(lps).span();

                // Check vault spread
                // @dev Once the round setltes, all liquidity is unlocked
                assert(
                    vault_spread_after == (0, vault_locked_before + total_premiums - total_payout),
                    'vault spread wrong'
                );
                // Calculate how much premiums/payouts belong to each LP
                let (mut lp_locked_before_arr, _) = split_spreads(lp_spreads_before);
                let mut lp_premiums_arr = get_portion_of_amount(
                    lp_locked_before_arr.span(), total_premiums
                )
                    .span();
                let mut lp_payouts_arr = get_portion_of_amount(
                    lp_locked_before_arr.span(), total_payout
                )
                    .span();
                // Check lp spreads
                loop {
                    match lp_spreads_before.pop_front() {
                        Option::Some((
                            lp_locked_before, _
                        )) => {
                            let lp_spread_after = lp_spreads_after.pop_front().unwrap();
                            let lp_premiums = lp_premiums_arr.pop_front().unwrap();
                            let lp_payout = lp_payouts_arr.pop_front().unwrap();
                            // Check each LP's locked balance is 0 and their unlocked balance is their remaining liquidity from the previous round
                            assert(
                                *lp_spread_after == (
                                    0, *lp_locked_before + *lp_premiums - *lp_payout
                                ),
                                'lp spread after wrong'
                            );
                        },
                        Option::None => { break (); },
                    }
                };

                rounds_to_run -= 1;
            },
        }
    }
}
