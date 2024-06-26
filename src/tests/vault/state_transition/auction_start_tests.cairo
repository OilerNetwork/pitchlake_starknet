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
            IVaultSafeDispatcherTrait
        },
        option_round::{
            IOptionRoundDispatcher, IOptionRoundDispatcherTrait, OptionRoundState,
            OptionRound::OptionRoundError
        },
    },
    tests::{
        utils::{
            helpers::{
                event_helpers::{assert_event_auction_start, assert_event_option_round_deployed},
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled,
                    accelerate_to_auctioning_custom, accelerate_to_running_custom,
                    timeskip_and_settle_round, timeskip_and_end_auction,
                },
                general_helpers::{
                    create_array_linear, create_array_gradient, sum_u256_array,
                    get_portion_of_amount,
                },
                setup::{setup_facade},
            },
            lib::{
                test_accounts::{
                    liquidity_provider_1, liquidity_provider_2, liquidity_providers_get,
                    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
                    liquidity_provider_5, option_bidder_buyer_4, liquidity_provider_4,
                    liquidity_provider_3,
                },
                variables::{decimals},
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
        },
    },
};
use debug::PrintTrait;


/// Failures ///

// Test starting an auction while one is already on-going fails
#[test]
#[available_gas(10000000)]
fn test_starting_auction_while_round_auctioning_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);

    // Try to start auction while round is Auctioning
    let expected_error: felt252 = OptionRoundError::AuctionAlreadyStarted.into();
    match vault_facade.start_auction_raw() {
        Result::Ok(_) => { panic!("Error expected") },
        Result::Err(err) => {
            let felt: felt252 = err.into();
            assert(err.into() == expected_error, 'Error Mismatch')
        }
    }
}

// Test starting an auction after one ends fails
#[test]
#[available_gas(10000000)]
fn test_starting_auction_while_round_running_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);

    // Try to start auction while round is Running
    let expected_error: felt252 = OptionRoundError::AuctionAlreadyStarted.into();
    match vault_facade.start_auction_raw() {
        Result::Ok(_) => { panic!("Error expected") },
        Result::Err(err) => { assert(err.into() == expected_error, 'Error Mismatch') }
    }
}

// Test starting an auction before the round transition period is over fails
#[test]
#[available_gas(10000000)]
fn test_starting_auction_while_round_settled_before_round_transition_period_over_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);
    accelerate_to_settled(ref vault_facade, 0);

    // Try to start auction while round is Settled, before round transition period is over
    let expected_error: felt252 = OptionRoundError::AuctionStartDateNotReached.into();
    match vault_facade.start_auction_raw() {
        Result::Ok(_) => { panic!("Error expected") },
        Result::Err(err) => { assert(err.into() == expected_error, 'Error Mismatch') }
    }
}


/// Event Tests ///

/// OptionRound Test
// Test every time an auction starts, the auction started event emits correctly
// @note Move to optoin round state transition tests
#[test]
#[available_gas(10000000)]
fn test_auction_started_option_round_event() {
    let mut rounds_to_run = 3;
    let (mut vault, _) = setup_facade();

    while rounds_to_run > 0_u32 {
        let mut current_round = vault.get_current_round();
        let total_options_available = accelerate_to_auctioning(ref vault);
        // Check the event emits correctly
        assert_event_auction_start(current_round.contract_address(), total_options_available);

        accelerate_to_running(ref vault);
        accelerate_to_settled(ref vault, current_round.get_strike_price());

        rounds_to_run -= 1;
    }
}


/// State Tests ///

/// Round ids/states

// Test starting an auction does not update the current round id
#[test]
#[available_gas(1000000000)]
fn test_starting_auction_does_not_update_current_and_next_round_ids() {
    let mut rounds_to_run = 3;
    let (mut vault, _) = setup_facade();
    while rounds_to_run > 0_u32 {
        let current_round_id = vault.get_current_round_id();
        accelerate_to_auctioning(ref vault);
        let new_current_round_id = vault.get_current_round_id();

        assert(new_current_round_id == current_round_id, 'current round id shd not change');

        accelerate_to_running(ref vault);
        accelerate_to_settled(ref vault, 0);

        rounds_to_run -= 1;
    }
}


// Test starting an auction updates the current round's state
// Test when an auction starts, the option round states update correctly
// @note should this be a state transition test in option round tests
#[test]
#[available_gas(1000000000)]
fn test_starting_auction_updates_current_rounds_state() {
    let mut rounds_to_run = 3;
    let (mut vault, _) = setup_facade();

    while rounds_to_run > 0_u32 {
        accelerate_to_auctioning(ref vault);

        let mut current_round = vault.get_current_round();
        let stat = current_round.get_state();

        assert(
            current_round.get_state() == OptionRoundState::Auctioning,
            'current round shd be auctioning'
        );

        accelerate_to_running(ref vault);
        accelerate_to_settled(ref vault, 0);

        rounds_to_run -= 1;
    }
}

/// Liquidity

// Test unlocked balances become locked when the auction starts
#[test]
#[available_gas(10000000)]
fn test_starting_auction_updates_locked_and_unlocked_balances() {
    let (mut vault, _) = setup_facade();
    let mut liquidity_providers = liquidity_providers_get(4).span();
    // Amounts to deposit: [100, 200, 300, 400]
    let mut deposit_amounts = create_array_gradient(
        100 * decimals(), 100 * decimals(), liquidity_providers.len()
    )
        .span();
    let total_deposits = sum_u256_array(deposit_amounts);

    // Vault and liquidity provider balances before auction starts
    let mut liquidity_providers_locked_before = vault.get_lp_locked_balances(liquidity_providers);
    let mut liquidity_providers_unlocked_before = vault
        .deposit_multiple(deposit_amounts, liquidity_providers);
    let (vault_locked_before, vault_unlocked_before) = vault
        .get_total_locked_and_unlocked_balance();

    // Start auction
    timeskip_and_end_auction(ref vault);

    // Vault and liquidity provider balances after auction starts
    let mut liquidity_providers_locked_after = vault.get_lp_locked_balances(liquidity_providers);
    let mut liquidity_providers_unlocked_after = vault
        .get_lp_unlocked_balances(liquidity_providers);
    let (vault_locked_after, vault_unlocked_after) = vault.get_total_locked_and_unlocked_balance();

    // Check vault balance
    assert(
        (vault_locked_before, vault_unlocked_before) == (0, total_deposits),
        'vault spread before wrong'
    );
    assert(
        (vault_locked_after, vault_unlocked_after) == (total_deposits, 0),
        'vault spread after wrong'
    );

    // Check liquidity provider balances
    loop {
        match liquidity_providers_locked_before.pop_front() {
            Option::Some(lp_locked_before) => {
                let lp_locked_after = liquidity_providers_locked_after.pop_front().unwrap();
                let lp_unlocked_before = liquidity_providers_unlocked_before.pop_front().unwrap();
                let lp_unlocked_after = liquidity_providers_unlocked_after.pop_front().unwrap();
                let lp_deposit_amount = deposit_amounts.pop_front().unwrap();

                assert(
                    (lp_locked_before, lp_unlocked_before) == (0, *lp_deposit_amount),
                    'LP spread before wrong'
                );
                assert(
                    (lp_locked_after, lp_unlocked_after) == (*lp_deposit_amount, 0),
                    'LP spread after wrong'
                );
            },
            Option::None => { break (); }
        }
    };
}
// @note revisit later if needed
//// Test that the vault and LP spreads update when the auction starts.
//// @dev This is a more complex test. Tests rollover amounts with withdraw and topup
//#[test]
//#[available_gas(10000000)]
//fn test_start_auction_updates_vault_and_lp_spreads_complex() {
//    let (mut vault, _) = setup_facade();
//    let mut liquidity_providers = liquidity_providers_get(4).span();
//    let mut deposit_amounts = create_array_gradient(100 * decimals(), 100 * decimals(), liquidity_providers.len())
//        .span(); // (100, 200, 300, 400)
//    let total_deposits = sum_u256_array(deposit_amounts);
//
//    // Vault and liquidity providers' balances before auction starts
//    let mut liquidity_providers_locked_before = vault.get_lp_locked_balances(liquidity_providers);
//    let mut liquidity_providers_unlocked_before = vault.deposit_multiple(deposit_amounts, liquidity_providers);
//    let (vault_locked_before, vault_unlocked_before) = vault.get_balance_spread();
//    // Start auction
//    vault.start_auction();
//    // Vault and liquidity providers' balances after auction starts
//    let mut liquidity_providers_locked_after = vault.get_lp_locked_balances(liquidity_providers);
//    let mut liquidity_providers_unlocked_after = vault.get_lp_unlocked_balances(liquidity_providers);
//    let (vault_locked_after, vault_unlocked_after) = vault.get_balance_spread();
//
//    // Check vault balance
//    assert(
//        (vault_locked_before, vault_unlocked_before) == (0, total_deposits),
//        'vault spread before wrong'
//    );
//    assert(
//        (vault_locked_after, vault_unlocked_after) == (total_deposits, 0),
//        'vault spread after wrong'
//    );
//
//    // Check liquidity providers balances
//    loop {
//        match liquidity_providers_locked_before.pop_front() {
//            Option::Some(lp_locked_before) => {
//                let lp_locked_after = liquidity_providers_locked_after.pop_front().unwrap();
//                let lp_unlocked_before = liquidity_providers_unlocked_before.pop_front().unwrap();
//                let lp_unlocked_after = liquidity_providers_unlocked_after.pop_front().unwrap();
//                let lp_deposit_amount = deposit_amounts.pop_front().unwrap();
//
//                assert(
//                    (lp_locked_before, lp_unlocked_before) == (0, *lp_deposit_amount),
//                    'LP spread before wrong'
//                );
//                assert(
//                    (lp_locked_after, lp_unlocked_after) == (*lp_deposit_amount, 0),
//                    'LP spread after wrong'
//                );
//            },
//            Option::None => { break (); }
//        }
//    };
//
//    // Accelerate throught round 1 with premiums and payout
//
//    let (mut vault, _) = setup_facade();
//    let mut liquidity_providers = liquidity_providers_get(4).span();
//    let mut round1_deposits = create_array_gradient(100 * decimals(), 100 * decimals(), liquidity_providers.len())
//        .span(); // (100, 200, 300, 400)
//    let starting_liquidity1 = sum_u256_array(round1_deposits);
//    accelerate_to_auctioning_custom(ref vault, liquidity_providers, round1_deposits);
//    let mut round1 = vault.get_current_round();
//    let (clearing_price1, options_sold1) = accelerate_to_running(ref vault);
//    let total_premiums1 = clearing_price1 * options_sold1;
//    let total_payout1 = accelerate_to_settled(ref vault, 2 * round1.get_strike_price());
//    // Total and individual remaining liquidity amounts after round 1
//    let remaining_liquidity1 = starting_liquidity1 + total_premiums1 - total_payout1;
//    let mut individual_remaining_liquidity1 = get_portion_of_amount(
//        round1_deposits, remaining_liquidity1
//    )
//        .span();
//    // Lp3 withdraws from premiums, lp4 adds a topup
//    let lp3 = liquidity_provider_3();
//    let lp4 = liquidity_provider_4();
//    let withdraw_amount = 1;
//    let topup_amount = 100 * decimals();
//    vault.withdraw(withdraw_amount, lp3);
//    vault.deposit(topup_amount, lp4);
//
//    // Vault and LP spreads before auction 2 starts
//    let mut lp_spreads_before = vault.get_lp_balance_spreads(liquidity_providers);
//    let vault_spread_before = vault.get_balance_spread();
//    // Start round 2's auction with no additional deposits
//    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());
//    // Create array of round2's deposits (roll over)
//    let mut round2_deposits = array![
//        *individual_remaining_liquidity1[0],
//        *individual_remaining_liquidity1[1],
//        *individual_remaining_liquidity1[2] - withdraw_amount,
//        *individual_remaining_liquidity1[3] + topup_amount
//    ]
//        .span();
//    let starting_liquidity2 = sum_u256_array(round2_deposits);
//    // Vault and LP spreads after auction 2 starts
//    let mut lp_spreads_after = vault.get_lp_balance_spreads(liquidity_providers);
//    let vault_spread_after = vault.get_balance_spread();
//
//    // Check vault spreads
//    assert(vault_spread_before == (0, starting_liquidity2), 'vault spread before wrong');
//    assert(vault_spread_after == (starting_liquidity2, 0), 'vault spread after wrong');
//    // Check LP spreads
//    loop {
//        match lp_spreads_before.pop_front() {
//            Option::Some(lp_spread_before) => {
//                let lp_spread_after = lp_spreads_after.pop_front().unwrap();
//                let lp_starting_liquidity2 = round2_deposits.pop_front().unwrap();
//                assert(lp_spread_before == (0, *lp_starting_liquidity2), 'LP spread before wrong');
//                assert(lp_spread_after == (*lp_starting_liquidity2, 0), 'LP spread after wrong');
//            },
//            Option::None => { break (); }
//        }
//    }
//}
// @note this should be an auction end test
//// @note should be with other roll over tests
//// Test that round and lp's unlocked balance becomes locked when auction starts (multiple LPs)
//#[test]
//#[available_gas(10000000)]
//fn test_unlocked_becomes_locked() {
//    let (mut vault, _) = setup_facade();
//    // Accelerate the round to running
//    let liquidity_providers = liquidity_providers_get(5);
//    let mut deposit_amounts = create_array_gradient(100 * decimals(), 100 * decimals(), liquidity_providers.len()); // (100, 200, 300...500)
//    accelerate_to_auctioning_custom(ref vault, liquidity_providers.span(), deposit_amounts.span());
//    accelerate_to_running(ref vault);
//    let mut current_round = vault.get_current_round();
//
//    // Spreads for the vault and each lp (locked, unlocked) before option round settles
//    let mut all_lp_spreads_before: Array<(u256, u256)> = vault.deposit_multiple(deposit_amounts.span(), liquidity_providers.span());
//    let (vault_locked_init, vault_unlocked) = vault.get_balance_spread();
//    // Settle option round (with no payout)
//    accelerate_to_settled(ref vault, current_round.get_strike_price(), );
//    // Final vault locked/unlocked spread
//    let (vault_locked_after, vault_unlocked_after) = vault.get_balance_spread();
//    let all_lp_spreads_after = vault.get_lp_balance_spreads(liquidity_providers.span());
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


