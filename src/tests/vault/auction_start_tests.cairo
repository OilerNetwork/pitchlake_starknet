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
                sum_u256_array,
            },
            test_accounts::{
                liquidity_provider_1, liquidity_provider_2, liquidity_providers_get,
                option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
                option_bidder_buyer_4,
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


// @note should be with other roll over tests, add/check for test like this but including premiums (rollover)
// Test that the vault and LP spreads update when the auction starts
#[test]
#[available_gas(10000000)]
fn test_unlocked_becomes_locked() {
    let (mut vault, _) = setup_facade();
    let lps = liquidity_providers_get(5);
    let mut deposit_amounts = create_array_gradient(
        100 * decimals(), 100 * decimals(), lps.len()
    ); // (100, 200, 300...500)

    // Vault and LP spreads before the auction starts (locked, unlocked)
    let vault_spread_before = vault.get_balance_spread();
    let mut lp_spreads_before = vault.deposit_multiple(deposit_amounts.span(), lps.span());
    // Start auction
    vault.start_auction();
    // Final vault and lp spreads
    let vault_spread_after = vault.get_balance_spread();
    let mut lp_spreads_after = vault.get_lp_balance_spreads(lps.span());

    // Check vault spread
    let deposit_total = sum_u256_array(deposit_amounts.span());
    assert(vault_spread_before == (0, deposit_total), 'vault spread before wrong');
    assert(vault_spread_after == (deposit_total, 0), 'vault spread after wrong');
    // Check LP spreads
    loop {
        match lp_spreads_before.pop_front() {
            Option::Some(lp_spread_before) => {
                let lp_spread_after = lp_spreads_after.pop_front().unwrap();
                let lp_deposit_amount = deposit_amounts.pop_front().unwrap();

                assert(lp_spread_before == (0, lp_deposit_amount), 'LP locked before wrong');
                assert(lp_spread_after == (lp_deposit_amount, 0), 'LP locked after wrong');
            },
            Option::None => { break (); }
        }
    };
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

// Test when an auction starts, it becomes the current round and the
// next round is deployed.
#[test]
#[available_gas(10000000)]
fn test_start_auction_becomes_current_round_deploys_next() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);

    // Check round 1 is auctioning and round 2 is open
    let (mut current_round_facade, mut next_round_facade) = vault_facade
        .get_current_and_next_rounds();
    assert(vault_facade.get_current_round_id() == 1, 'current round should be 1');
    assert(
        current_round_facade.get_state() == OptionRoundState::Auctioning,
        'current round should be settled'
    );
    assert(next_round_facade.get_state() == OptionRoundState::Open, 'next round should be open');
}

// Test when the auction starts, the auction_start event is emitted
#[test]
#[available_gas(10000000)]
fn test_start_auction_event() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);

    // Check that auction start event was emitted with correct total_options_available
    let mut current_round: OptionRoundFacade = vault.get_current_round();
    assert_event_auction_start(
        current_round.contract_address(), current_round.get_total_options_available()
    );
}

// Test when the next round is deployed, the correct event fires
#[test]
#[available_gas(10000000)]
fn test_start_next_round_event() {
    let (mut vault, _) = setup_facade();
    // Start auction, round 1 is now auctioning
    accelerate_to_auctioning(ref vault);
    let (_, mut round_2) = vault.get_current_and_next_rounds();

    // Check the next round deployed event emits correctly
    assert_event_option_round_deployed(vault.contract_address(), 2, round_2.contract_address(),);

    // Check consecutive rounds
    // Finish round 1 and start round 2's auction
    accelerate_to_running(ref vault);
    accelerate_to_settled(ref vault, 'does not matter'.into());
    // @note can remove once rtp skip is added to acclerate to auctioning
    set_block_timestamp(starknet::get_block_timestamp() + vault.get_round_transition_period() + 1);
    accelerate_to_auctioning(ref vault);
    let (_, mut round_3) = vault.get_current_and_next_rounds();

    // Check round 3 deployed event
    assert_event_option_round_deployed(vault.contract_address(), 3, round_3.contract_address())
}


/// Failures ///

// @note these tests can all be done in 1 test once call no longer reverts and returns and option
//  - assert the result is_err at each step, then passes once it jumps the rtp

// Test the next auction cannot start before the round transition period is over
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot start auction yet', 'ENTRYPOINT_FAILED'))]
fn test_start_auction_while_current_round_auctioning_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1) so its auction can start
    let deposit_amount_wei: u256 = 10 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // @dev The vault constructor already has the current round (0) settled, so we need to start round 1 first to make it Auctioning.
    // Start round 1 (Auctioning) and deploy round 2 (Open)
    vault_facade.start_auction();
    // Try to start auction 2 before round 1 has settled
    vault_facade.start_auction();
}

// Test that an auction cannot start while the current is Running
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot start auction yet', 'ENTRYPOINT_FAILED',))]
fn test_start_auction_while_current_round_running_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let lps = liquidity_providers_get(5);
    let amounts = create_array_linear(10000 * decimals(), 5);
    accelerate_to_auctioning_custom(ref vault_facade, lps.span(), amounts.span());
    // Start auction
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid
    let option_params = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    timeskip_and_end_auction(ref vault_facade);
    // Try to start the next auction while the current is Running
    vault_facade.start_auction();
}

// Test that an auction cannot start before the round transition period is over
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot start auction yet', 'ENTRYPOINT_FAILED',))]
fn test_start_auction_before_round_transition_period_over_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid
    let option_params = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    timeskip_and_end_auction(ref vault_facade);
    // Settle option round
    timeskip_and_settle_round(ref vault_facade);
    // Try to start the next auction before waiting the round transition period
    // @dev add in the round transition period either in option round params or vault
    let rtp = 111;
    set_block_timestamp(option_params.option_expiry_time + rtp - 1);
    vault_facade.start_auction();
}

// Test that an auction cannot start if the minimum_collateral_required is not reached
// @note Tomasz said this is unneccesary, we may introduce a maximum_collateral_required.
// Tomasz said too much collateral leads to problems with manipulation for premium
// This is a much later concern
#[ignore]
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot start auction yet', 'ENTRYPOINT_FAILED',))]
fn test_start_auction_under_minium_collateral_required_failure() {
    let (mut vault_facade, _) = setup_facade();

    // @dev Need to manually initialize round 1 unless it is initialed during the vault constructor
    // ... vault::_initialize_round_1()

    // Get round 1's minium collateral requirements
    let mut next_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = next_round.get_params();
    let minimum_collateral_required = params.minimum_collateral_required;
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = minimum_collateral_required - 1;
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Try to start auction
    vault_facade.start_auction();
}

