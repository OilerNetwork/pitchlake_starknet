use core::array::SpanTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};
use pitch_lake_starknet::{
    contracts::{
        eth::Eth,
        vault::{
            IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault,
            IVaultSafeDispatcherTrait, VaultError
        },
        option_round::{
            OptionRoundState, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,
            OptionRound::OptionRoundError
        },
    },
    tests::{
        utils::{
            helpers::{
                event_helpers::{pop_log, assert_no_events_left, assert_event_auction_end},
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running,
                    accelerate_to_auctioning_custom, accelerate_to_running_custom,
                    accelerate_to_settled, timeskip_past_round_transition_period,
                    timeskip_and_end_auction,
                },
                general_helpers::{
                    create_array_gradient, create_array_linear, sum_u256_array,
                    get_portion_of_amount, split_spreads, span_to_array,
                },
                setup::{setup_facade},
            },
            lib::{
                test_accounts::{
                    liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                    option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                    liquidity_providers_get, option_bidders_get, liquidity_provider_4,
                    liquidity_provider_5, liquidity_provider_3,
                },
                variables::{decimals},
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
            mocks::mock_market_aggregator::{
                MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
                IMarketAggregatorSetterDispatcherTrait
            },
        },
    },
};
use debug::PrintTrait;


/// Failures ///

// Test ending the auction before it starts fails
#[test]
#[available_gas(10000000)]
fn test_ending_auction_before_it_starts_fails() {
    let (mut vault_facade, _) = setup_facade();

    // Try to end auction before it starts
    let expected_error: felt252 = OptionRoundError::AuctionEndDateNotReached.into();
    match vault_facade.end_auction_raw() {
        Result::Ok(_) => { panic!("Error expected") },
        Result::Err(err) => { assert(err.into() == expected_error, 'Error Mismatch') }
    }
}

// Test ending the auction before the auction end date fails
#[test]
#[available_gas(10000000)]
fn test_ending_auction_before_auction_end_date_fails() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);

    // Try to end auction before auction end date
    let expected_error: felt252 = OptionRoundError::AuctionEndDateNotReached.into();
    match vault.end_auction_raw() {
        Result::Ok(_) => { panic!("Error expected") },
        Result::Err(err) => { assert(err.into() == expected_error, 'Error Mismatch') }
    }
}

// Test ending the auction after it already ended fails
#[test]
#[available_gas(10000000)]
fn test_ending_auction_while_round_running_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);

    // Try to end auction after it has already ended
    let expected_error: felt252 = OptionRoundError::AuctionEndDateNotReached.into();
    match vault_facade.end_auction_raw() {
        Result::Ok(_) => { panic!("Error expected") },
        Result::Err(err) => { assert(err.into() == expected_error, 'Error Mismatch') }
    }
}

// Test ending the auction after the auction ends fails (next state)
#[test]
#[available_gas(10000000)]
fn test_ending_auction_while_round_settled_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);
    accelerate_to_settled(ref vault_facade, 0);

    // Try to end auction before round transition period is over
    let expected_error: felt252 = OptionRoundError::AuctionEndDateNotReached.into();
    match vault_facade.end_auction_raw() {
        Result::Ok(_) => { panic!("Error expected") },
        Result::Err(err) => { assert(err.into() == expected_error, 'Error Mismatch') }
    }
}


/// Event Tests ///

// Test ending the auction emits the correct event
// @note shold move to option round state transition tests
#[test]
#[available_gas(10000000)]
fn test_auction_ended_option_round_event() {
    let mut rounds_to_run = 3;
    let (mut vault, _) = setup_facade();

    loop {
        match rounds_to_run {
            0 => { break (); },
            _ => {
                accelerate_to_auctioning(ref vault);

                let (clearing_price, _) = accelerate_to_running(ref vault);
                // Check the event emits correctly
                let mut current_round = vault.get_current_round();
                assert_event_auction_end(current_round.contract_address(), clearing_price);

                accelerate_to_settled(ref vault, 0);

                rounds_to_run -= 1;
            },
        }
    }
}


/// State Tests ///

/// Round ids/states

// Test ending an auction does not change the current round id
#[test]
#[available_gas(10000000)]
fn test_end_auction_does_not_update_current_and_next_round_ids() {
    let rounds_to_run = 3;
    let mut i = rounds_to_run;
    let (mut vault, _) = setup_facade();

    loop {
        match i {
            0 => { break (); },
            _ => {
                accelerate_to_auctioning(ref vault);

                let current_round_id_before = vault.get_current_round_id();
                accelerate_to_running(ref vault);
                let current_round_id_after = vault.get_current_round_id();

                assert(
                    current_round_id_before == current_round_id_after, 'current round id changed'
                );

                accelerate_to_settled(ref vault, 0);

                i -= 1;
            },
        }
    }
}

// Test ending an auction updates the current round state
// @note should this be a state transition test in option round tests
#[test]
#[available_gas(10000000)]
fn test_end_auction_updates_current_round_state() {
    let mut rounds_to_run = 3;
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

                rounds_to_run -= 1;
            },
        }
    }
}

/// Liquidity

// Test that winning bids are sent to the vault as premiums, and
// refundable bids remain in the round
#[test]
#[available_gas(10000000)]
fn test_end_auction_eth_transfer() {
    let (mut vault_facade, eth) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);

    // Vault and round balances before auction ends
    let mut current_round = vault_facade.get_current_round();
    let round_balance_before = eth.balance_of(current_round.contract_address());
    let vault_balance_before = eth.balance_of(vault_facade.contract_address());

    // End auction (2 bidders, first bid gets refuned, second's is converted to premium)
    let option_bidders = option_bidders_get(2).span();
    let bid_count = current_round.get_total_options_available();
    let losing_price = current_round.get_reserve_price();
    let losing_amount = bid_count * losing_price;
    let winning_price = 2 * losing_price;
    let winning_amount = 2 * bid_count * winning_price;
    accelerate_to_running_custom(
        ref vault_facade,
        option_bidders,
        array![losing_amount, winning_amount].span(),
        array![losing_price, winning_price].span()
    );
    // Vault and round balances after auction ends
    let round_balance_after = eth.balance_of(current_round.contract_address());
    let vault_balance_after = eth.balance_of(vault_facade.contract_address());

    // Check premiums transfer from round to vault, and unused bids remain in round
    assert(round_balance_before == losing_amount + winning_amount, 'round balance before wrong');
    assert(
        round_balance_after == round_balance_before - winning_amount, 'round balance after wrong'
    );
    assert(
        vault_balance_after == vault_balance_before + winning_amount, 'vault balance after wrong'
    );
}

// Test ending the auction updates the vault and liquidity provider balances
#[test]
#[available_gas(10000000)]
fn test_end_auction_updates_locked_and_unlocked_balances() {
    let (mut vault, _) = setup_facade();
    let mut liquidity_providers = liquidity_providers_get(4).span();
    // Amounts to deposit: [100, 200, 300, 400]
    let mut deposit_amounts = create_array_gradient(
        100 * decimals(), 100 * decimals(), liquidity_providers.len()
    )
        .span();
    let total_deposits = sum_u256_array(deposit_amounts);
    accelerate_to_auctioning_custom(ref vault, liquidity_providers, deposit_amounts);

    // Vault and liquidity provider balances before auction ends
    let mut liquidity_providers_locked_before = vault
        .get_lp_locked_balances(liquidity_providers)
        .span();
    let mut liquidity_providers_unlocked_before = vault
        .get_lp_unlocked_balances(liquidity_providers)
        .span();
    let (vault_locked_before, vault_unlocked_before) = vault.get_balance_spread();

    // End auction
    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
    let total_premiums = options_sold * clearing_price;
    let mut individual_premiums = get_portion_of_amount(deposit_amounts, total_premiums).span();

    // Vault and liquidity provider balances after auction ends
    let mut liquidity_providers_locked_after = vault
        .get_lp_locked_balances(liquidity_providers)
        .span();
    let mut liquidity_providers_unlocked_after = vault
        .get_lp_unlocked_balances(liquidity_providers)
        .span();
    let (vault_locked_after, vault_unlocked_after) = vault.get_balance_spread();

    // Check vault balances
    assert(
        (vault_locked_before, vault_unlocked_before) == (total_deposits, 0),
        'vault balance before wrong'
    );
    assert(
        (vault_locked_after, vault_unlocked_after) == (total_deposits, total_premiums),
        'vault balance after'
    );

    // Check liquidity provider balances
    loop {
        match liquidity_providers_locked_before.pop_front() {
            Option::Some(lp_locked_before) => {
                let lp_locked_after = liquidity_providers_locked_after.pop_front().unwrap();
                let lp_unlocked_before = liquidity_providers_unlocked_before.pop_front().unwrap();
                let lp_unlocked_after = liquidity_providers_unlocked_after.pop_front().unwrap();
                let lp_deposit_amount = deposit_amounts.pop_front().unwrap();
                let lp_premium = individual_premiums.pop_front().unwrap();
                assert(
                    (*lp_locked_before, *lp_unlocked_before) == (*lp_deposit_amount, 0),
                    'LP locked before wrong'
                );
                assert(
                    (*lp_locked_after, *lp_unlocked_after) == (*lp_deposit_amount, *lp_premium),
                    'LP locked after wrong'
                );
            },
            Option::None => { break (); }
        }
    }
}

// Test that the vault and LP spreads update when the auction ends. Tests rollover
// amounts with withdraw and topup
#[test]
#[available_gas(10000000)]
fn test_end_auction_updates_vault_and_lp_spreads_complex() {
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
    // Create array of round2's deposits
    let mut round2_deposits = array![
        *individual_remaining_liquidity1[0],
        *individual_remaining_liquidity1[1],
        *individual_remaining_liquidity1[2] - withdraw_amount,
        *individual_remaining_liquidity1[3] + topup_amount
    ]
        .span();

    // Vault and LP spreads before auction 2 ends
    let mut lp_spreads_before = vault.get_lp_balance_spreads(lps).span();
    let vault_spread_before = vault.get_balance_spread();
    // End round 2's auction
    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
    let total_premiums2 = clearing_price * options_sold;
    let mut individual_premiums2 = get_portion_of_amount(round2_deposits, total_premiums2).span();
    // Vault and LP spreads after the auction ends
    let mut lp_spreads_after = vault.get_lp_balance_spreads(lps).span();
    let vault_spread_after = vault.get_balance_spread();

    // Check vault spreads
    assert(
        vault_spread_before == (remaining_liquidity1 + topup_amount, 0), 'vault spread before wrong'
    );
    assert(
        vault_spread_after == (remaining_liquidity1 + topup_amount, total_premiums2),
        'vault spread after wrong'
    );
    // Check LP spreads
    loop {
        match lp_spreads_before.pop_front() {
            Option::Some(lp_spread_before) => {
                let lp_spread_after = lp_spreads_after.pop_front().unwrap();
                let lp_starting_liquidity2 = round2_deposits.pop_front().unwrap();
                let lp_premiums2 = individual_premiums2.pop_front().unwrap();
                assert(*lp_spread_before == (*lp_starting_liquidity2, 0), 'LP spread before wrong');
                assert(
                    *lp_spread_after == (*lp_starting_liquidity2, *lp_premiums2),
                    'LP spread after wrong'
                );
            },
            Option::None => { break (); }
        }
    }
}

