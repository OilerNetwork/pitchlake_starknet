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

/// Round ids/states

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

/// Liquidity

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


// Test that the vualt and LP spreads update when the round settles
// @dev This is a simple test
#[test]
#[available_gas(10000000)]
fn test_settle_option_round_updates_vault_and_lp_spreads_simple() {
    let (mut vault, _) = setup_facade();
    let mut lps = liquidity_providers_get(4).span();
    let mut deposit_amounts = create_array_gradient(100 * decimals(), 100 * decimals(), lps.len())
        .span(); // [100, 200, 300, 400]
    let total_deposits = sum_u256_array(deposit_amounts);
    // Deposit and start auction
    accelerate_to_auctioning_custom(ref vault, lps, deposit_amounts);
    let mut round1 = vault.get_current_round();
    // End auction
    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
    let total_premiums = options_sold * clearing_price;
    let mut individual_premiums = get_portion_of_amount(deposit_amounts, total_premiums).span();

    // Vault and LP spreads before option round settles
    let mut lp_spreads_before = vault.get_lp_balance_spreads(lps);
    let vault_spread_before = vault.get_balance_spread();
    // Settle the round with a payout
    let total_payouts = accelerate_to_settled(ref vault, 2 * round1.get_strike_price());
    let remaining_liquidity = total_deposits + total_premiums - total_payouts;
    let mut individual_remaining_liquidty = get_portion_of_amount(
        deposit_amounts, remaining_liquidity
    )
        .span();
    // Vault and LP spreads after option round settles
    let mut lp_spreads_after = vault.get_lp_balance_spreads(lps);
    let vault_spread_after = vault.get_balance_spread();

    // Check vault spreads
    assert(vault_spread_before == (total_deposits, total_premiums), 'vault spread before wrong');
    assert(vault_spread_after == (0, remaining_liquidity), 'vault spread after wrong');
    // Check LP spreads
    loop {
        match lp_spreads_before.pop_front() {
            Option::Some(lp_spread_before) => {
                let lp_spread_after = lp_spreads_after.pop_front().unwrap();
                let lp_deposit_amount = deposit_amounts.pop_front().unwrap();
                let lp_premium = individual_premiums.pop_front().unwrap();
                let lp_remaining_liquidity = individual_remaining_liquidty.pop_front().unwrap();
                assert(
                    lp_spread_before == (*lp_deposit_amount, *lp_premium), 'LP spread before wrong'
                );
                assert(lp_spread_after == (0, *lp_remaining_liquidity), 'LP spread after wrong');
            },
            Option::None => { break (); }
        }
    };
}

// Test that the vualt and LP spreads update when the round settles
// @dev This is a simple test
#[test]
#[available_gas(10000000)]
fn test_settle_option_round_updates_vault_and_lp_spreads_complex() {
    // Accelerate through round 1 with premiums and a payout
    let (mut vault, _) = setup_facade();
    let mut lps = liquidity_providers_get(4).span();
    let round1_deposits = create_array_gradient(100 * decimals(), 100 * decimals(), lps.len())
        .span(); // (100, 200, 300, 400)
    let starting_liquidity1 = sum_u256_array(round1_deposits);
    accelerate_to_auctioning_custom(ref vault, lps, round1_deposits);
    let mut round1 = vault.get_current_round();
    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
    let total_premiums1 = clearing_price * options_sold;
    let total_payout1 = accelerate_to_settled(ref vault, 2 * round1.get_strike_price());
    // Total and individual remaining liquidity amounts after round 1
    let remaining_liquidity1 = starting_liquidity1 + total_premiums1 - total_payout1;
    let mut individual_remaining_liquidity1 = get_portion_of_amount(
        round1_deposits, remaining_liquidity1
    )
        .span();

    // Lp3 withdraws from premiums, lp4 adds a topup
    let lp3 = liquidity_provider_3();
    let lp4 = liquidity_provider_4();
    let withdraw_amount = 1;
    let topup_amount = 100 * decimals();
    vault.withdraw(withdraw_amount, lp3);
    vault.deposit(topup_amount, lp4);
    // Start round 2' auction with no additional deposits
    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());
    let mut round2 = vault.get_current_round();
    // Create array of round2's deposits
    let mut round2_deposits = array![
        *individual_remaining_liquidity1[0],
        *individual_remaining_liquidity1[1],
        *individual_remaining_liquidity1[2] - withdraw_amount,
        *individual_remaining_liquidity1[3] + topup_amount
    ]
        .span();
    let starting_liquidity2 = sum_u256_array(round2_deposits);

    // End round 2's auction
    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
    let total_premiums2 = clearing_price * options_sold;
    let mut individual_premiums2 = get_portion_of_amount(round2_deposits, total_premiums2).span();

    // Vault and LP spreads before round 2 settles
    let mut lp_spreads_before = vault.get_lp_balance_spreads(lps).span();
    let vault_spread_before = vault.get_balance_spread();
    // Settle round 2 with a payout
    let total_payout2 = accelerate_to_settled(ref vault, 2 * round2.get_strike_price());
    let remaining_liquidity2 = starting_liquidity2 + total_premiums2 - total_payout2;
    let mut individual_remaining_liquidity2 = get_portion_of_amount(
        round2_deposits, remaining_liquidity2
    )
        .span();
    // Vault and LP spreads after the round 2 settles
    let mut lp_spreads_after = vault.get_lp_balance_spreads(lps).span();
    let vault_spread_after = vault.get_balance_spread();

    // Check vault spreads
    assert(
        vault_spread_before == (starting_liquidity2, total_premiums2), 'vault spread before wrong'
    );
    assert(vault_spread_after == (0, remaining_liquidity2), 'vault spread after wrong');
    // Check LP spreads
    loop {
        match lp_spreads_before.pop_front() {
            Option::Some(lp_spread_before) => {
                let lp_spread_after = lp_spreads_after.pop_front().unwrap();
                let lp_starting_liquidity2 = round2_deposits.pop_front().unwrap();
                let lp_premiums2 = individual_premiums2.pop_front().unwrap();
                let lp_remaining_liquidity2 = individual_remaining_liquidity2.pop_front().unwrap();
                assert(
                    *lp_spread_before == (*lp_starting_liquidity2, *lp_premiums2),
                    'LP spread before wrong'
                );
                assert(*lp_spread_after == (0, *lp_remaining_liquidity2), 'LP spread after wrong');
            },
            Option::None => { break (); }
        }
    }
}
