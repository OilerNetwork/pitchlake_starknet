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
    eth::Eth,
    vault::{
        IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault,
        IVaultSafeDispatcherTrait
    },
    option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait, OptionRoundState},
    tests::{
        utils::{
            event_helpers::{assert_event_auction_start, assert_event_option_round_deployed},
            accelerators::{
                accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled,
                accelerate_to_auctioning_custom, accelerate_to_running_custom,
                timeskip_and_settle_round, timeskip_and_end_auction,
            },
            utils::{
                create_array_linear, create_array_gradient, sum_spreads, split_spreads,
                sum_u256_array, get_portion_of_amount,
            },
            test_accounts::{
                liquidity_provider_1, liquidity_provider_2, liquidity_providers_get,
                option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
                liquidity_provider_5, option_bidder_buyer_4, liquidity_provider_4,
                liquidity_provider_3,
            },
            variables::{decimals}, setup::{setup_facade},
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
        },
    },
};
use debug::PrintTrait;


/// Failures ///

// Test an auction cannot start while the current round is auctioning
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot start auction yet', 'ENTRYPOINT_FAILED'))]
fn test_start_auction_while_current_round_auctioning_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);

    // Try to start round 2's auction while round 1 is auctioning
    vault_facade.start_auction();
}

// Test that an auction cannot start while the current round is Running
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot start auction yet', 'ENTRYPOINT_FAILED',))]
fn test_start_auction_while_current_round_running_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);

    // Try to start round 2's auction while round 1 is running
    vault_facade.start_auction();
}

// Test that an auction cannot start before the round transition period is over
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot start auction yet', 'ENTRYPOINT_FAILED',))]
fn test_start_auction_before_round_transition_period_over_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);
    accelerate_to_settled(ref vault_facade, 0);

    // Try to start round 2's auction while round 1 is settled but before the round transition period is over
    vault_facade.start_auction();
}


/// Event Tests ///

// Test when the auction starts the event emits correctly
#[test]
#[available_gas(10000000)]
fn test_start_auction_event() {
    let mut rounds_to_run = 3;

    let (mut vault, _) = setup_facade();
    loop {
        match rounds_to_run {
            0 => { break (); },
            _ => {
                let total_options_available = accelerate_to_auctioning(ref vault);
                let mut current_round = vault.get_current_round();
                // Check the event emits correctly
                assert_event_auction_start(
                    current_round.contract_address(), total_options_available
                );

                accelerate_to_running(ref vault);
                accelerate_to_settled(ref vault, current_round.get_strike_price());

                rounds_to_run -= 1;
            },
        }
    }
}

// Test when the auction starts, the next round deployed event emits correctly
// @dev Checks that when rounds 2, 3 & 4 deploy the events emit correctly
#[test]
#[available_gas(10000000)]
fn test_start_auction_deploy_next_round_event() {
    let rounds_to_run = 3;
    let mut i = rounds_to_run;
    let (mut vault, _) = setup_facade();

    loop {
        match i {
            0 => { break (); },
            _ => {
                accelerate_to_auctioning(ref vault);
                let mut next_round = vault.get_next_round();
                // Check the event emits correctly
                assert_event_option_round_deployed(
                    vault.contract_address(),
                    // @dev round 2 should be the first round to deploy post deployment
                    2 + (rounds_to_run - i).into(),
                    next_round.contract_address(),
                );

                accelerate_to_running(ref vault);
                accelerate_to_settled(ref vault, next_round.get_strike_price());

                i -= 1;
            },
        }
    }
}


/// State Tests ///

/// Round ids/states

// Test when an auction starts, the curent and next rounds are updated
#[test]
#[available_gas(10000000)]
fn test_start_auction_updates_current_and_next_round_ids() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);

    // Check current round is now 1
    assert(vault_facade.get_current_round_id() == 1, 'current shd be 1');

    // Check consecutive rounds
    accelerate_to_running(ref vault_facade);
    accelerate_to_settled(ref vault_facade, 0);
    accelerate_to_auctioning(ref vault_facade);
    assert(vault_facade.get_current_round_id() == 2, 'current shd be 2');
    accelerate_to_running(ref vault_facade);
    accelerate_to_settled(ref vault_facade, 0);
    accelerate_to_auctioning(ref vault_facade);
    assert(vault_facade.get_current_round_id() == 3, 'current shd be 3');
}

// Test when an auction starts, the option round states update correctly
// @note should this be a state transition test in option round tests
#[test]
#[available_gas(10000000)]
fn test_start_auction_updates_current_and_next_round_states() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);

    // Check round 1 is auctioning and round 2 is open
    let (mut round1, mut round2) = vault_facade.get_current_and_next_rounds();
    assert(round1.get_state() == OptionRoundState::Auctioning, 'round1 shd be auctioning');
    assert(round2.get_state() == OptionRoundState::Open, 'round2 shd be open');

    // Check consecutive rounds
    accelerate_to_running(ref vault_facade);
    accelerate_to_settled(ref vault_facade, 0);
    accelerate_to_auctioning(ref vault_facade);
    let mut round3 = vault_facade.get_next_round();
    assert(round2.get_state() == OptionRoundState::Auctioning, 'round2 shd be auctioning');
    assert(round3.get_state() == OptionRoundState::Open, 'round3 shd be open');
}

/// Liquidity

// Test that the vault and LP spreads update when the auction starts
// @dev This is a simple example
#[test]
#[available_gas(10000000)]
fn test_start_auction_updates_vault_and_lp_spreads_simple() {
    let (mut vault, _) = setup_facade();
    let mut lps = liquidity_providers_get(4).span();
    let mut deposit_amounts = create_array_gradient(100 * decimals(), 100 * decimals(), lps.len())
        .span(); // (100, 200, 300, 400)
    let total_deposits = sum_u256_array(deposit_amounts);

    // Vault and LP spreads before auction start
    let mut lp_spreads_before = vault.deposit_multiple(deposit_amounts, lps);
    let vault_spread_before = vault.get_balance_spread();
    // Start auction
    vault.start_auction();
    // Vault and LP spreads after auction start
    let mut lp_spreads_after = vault.get_lp_balance_spreads(lps);
    let vault_spread_after = vault.get_balance_spread();

    // Check vault spreads
    assert(vault_spread_before == (0, total_deposits), 'vault spread before wrong');
    assert(vault_spread_after == (total_deposits, 0), 'vault spread after wrong');
    // Check LP spreads
    loop {
        match lp_spreads_before.pop_front() {
            Option::Some(lp_spread_before) => {
                let lp_spread_after = lp_spreads_after.pop_front().unwrap();
                let lp_deposit_amount = deposit_amounts.pop_front().unwrap();
                assert(lp_spread_before == (0, *lp_deposit_amount), 'LP spread before wrong');
                assert(lp_spread_after == (*lp_deposit_amount, 0), 'LP spread after wrong');
            },
            Option::None => { break (); }
        }
    };
}

// Test that the vault and LP spreads update when the auction starts.
// @dev This is a more complex test. Tests rollover amounts with withdraw and topup
#[test]
#[available_gas(10000000)]
fn test_start_auction_updates_vault_and_lp_spreads_complex() {
    // Accelerate throught round 1 with premiums and payout
    let (mut vault, _) = setup_facade();
    let mut lps = liquidity_providers_get(4).span();
    let mut round1_deposits = create_array_gradient(100 * decimals(), 100 * decimals(), lps.len())
        .span(); // (100, 200, 300, 400)
    let starting_liquidity1 = sum_u256_array(round1_deposits);
    accelerate_to_auctioning_custom(ref vault, lps, round1_deposits);
    let mut round1 = vault.get_current_round();
    let (clearing_price1, options_sold1) = accelerate_to_running(ref vault);
    let total_premiums1 = clearing_price1 * options_sold1;
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

    // Vault and LP spreads before auction 2 starts
    let mut lp_spreads_before = vault.get_lp_balance_spreads(lps);
    let vault_spread_before = vault.get_balance_spread();
    // Start round 2's auction with no additional deposits
    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());
    // Create array of round2's deposits (roll over)
    let mut round2_deposits = array![
        *individual_remaining_liquidity1[0],
        *individual_remaining_liquidity1[1],
        *individual_remaining_liquidity1[2] - withdraw_amount,
        *individual_remaining_liquidity1[3] + topup_amount
    ]
        .span();
    let starting_liquidity2 = sum_u256_array(round2_deposits);
    // Vault and LP spreads after auction 2 starts
    let mut lp_spreads_after = vault.get_lp_balance_spreads(lps);
    let vault_spread_after = vault.get_balance_spread();

    // Check vault spreads
    assert(vault_spread_before == (0, starting_liquidity2), 'vault spread before wrong');
    assert(vault_spread_after == (starting_liquidity2, 0), 'vault spread after wrong');
    // Check LP spreads
    loop {
        match lp_spreads_before.pop_front() {
            Option::Some(lp_spread_before) => {
                let lp_spread_after = lp_spreads_after.pop_front().unwrap();
                let lp_starting_liquidity2 = round2_deposits.pop_front().unwrap();
                assert(lp_spread_before == (0, *lp_starting_liquidity2), 'LP spread before wrong');
                assert(lp_spread_after == (*lp_starting_liquidity2, 0), 'LP spread after wrong');
            },
            Option::None => { break (); }
        }
    }
}
// @note this should be an auction end test
//// @note should be with other roll over tests
//// Test that round and lp's unlocked balance becomes locked when auction starts (multiple LPs)
//#[test]
//#[available_gas(10000000)]
//fn test_unlocked_becomes_locked() {
//    let (mut vault, _) = setup_facade();
//    // Accelerate the round to running
//    let lps = liquidity_providers_get(5);
//    let mut deposit_amounts = create_array_gradient(100 * decimals(), 100 * decimals(), lps.len()); // (100, 200, 300...500)
//    accelerate_to_auctioning_custom(ref vault, lps.span(), deposit_amounts.span());
//    accelerate_to_running(ref vault);
//    let mut current_round = vault.get_current_round();
//
//    // Spreads for the vault and each lp (locked, unlocked) before option round settles
//    let mut all_lp_spreads_before: Array<(u256, u256)> = vault.deposit_multiple(deposit_amounts.span(), lps.span());
//    let (vault_locked_init, vault_unlocked) = vault.get_balance_spread();
//    // Settle option round (with no payout)
//    accelerate_to_settled(ref vault, current_round.get_strike_price(), );
//    // Final vault locked/unlocked spread
//    let (vault_locked_after, vault_unlocked_after) = vault.get_balance_spread();
//    let all_lp_spreads_after = vault.get_lp_balance_spreads(lps.span());
//
//    // Check vault locked/unlocked total
//    let deposit_total = sum_u256_array(deposit_amounts.span());
//    assert(total_locked == deposit_total, 'vault::locked wrong');
//    assert(total_unlocked == 0, 'vault::unlocked wrong');
//    // Check LP spreads
//    loop {
//        match all_lp_spreads.pop_front() {
//            Option::Some((
//                locked_amount, unlocked_amount
//            )) => {
//                assert(locked_amount == deposit_amounts.pop_front().unwrap(), 'Locked balance mismatch');
//                assert(unlocked_amount == 0, 'Unlocked balance mismatch');
//            },
//            Option::None => { break (); }
//        }
//    };
//}

//// Test that an auction cannot start if the minimum_collateral_required is not reached
//// @note Tomasz said this is unneccesary, we may introduce a maximum_collateral_required.
//// Tomasz said too much collateral leads to problems with manipulation for premium
//// This is a much later concern
//#[ignore]
//#[test]
//#[available_gas(10000000)]
//#[should_panic(expected: ('Cannot start auction yet', 'ENTRYPOINT_FAILED',))]
//fn test_start_auction_under_minium_collateral_required_failure() {
//    let (mut vault_facade, _) = setup_facade();
//
//    // @dev Need to manually initialize round 1 unless it is initialed during the vault constructor
//    // ... vault::_initialize_round_1()
//
//    // Get round 1's minium collateral requirements
//    let mut next_round: OptionRoundFacade = vault_facade.get_next_round();
//    let params = next_round.get_params();
//    let minimum_collateral_required = params.minimum_collateral_required;
//    // LP deposits (into round 1)
//    let deposit_amount_wei: u256 = minimum_collateral_required - 1;
//    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
//    // Try to start auction
//    vault_facade.start_auction();
//}


