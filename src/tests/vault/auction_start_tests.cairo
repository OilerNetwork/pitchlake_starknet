use core::array::SpanTrait;
use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait
};
use pitch_lake_starknet::option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};

use result::ResultTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};

use starknet::contract_address::ContractAddressZeroable;
use openzeppelin::utils::serde::SerializedAppend;

use traits::Into;
use traits::TryInto;
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{
    setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    liquidity_providers_get, option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
    create_array_linear, create_array_gradient, option_bidder_buyer_4, vault_manager, weth_owner,
    mock_option_params, assert_event_auction_start, accelerate_to_auctioning_custom,
    accelerate_to_running_custom, accelerate_to_auctioning, assert_event_option_round_deployed,
    accelerate_to_running, accelerate_to_settled,
};
use pitch_lake_starknet::tests::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};
use pitch_lake_starknet::option_round::{OptionRoundState};


// Test that round and lp's unallocated becomes collateral when auction starts (multiple LPs)
#[test]
#[available_gas(10000000)]
fn test_unallocated_becomes_collateral() {
    let (mut vault_facade, _) = setup_facade();
    // Get next round (open)
    let mut next_round: OptionRoundFacade = vault_facade.get_current_round();
    // Add liq. to next round (1)
    let lps = liquidity_providers_get(5);
    let len = lps.len();
    let mut amounts = create_array_gradient(1000 * decimals(), 5000 * decimals(), len);

    let deposit_total = vault_facade.deposit_mutltiple(lps.span(), amounts.span());

    // Start the auction
    vault_facade.start_auction();
    // Final collateral/unallocated spread
    let (next_round_collateral, next_round_unallocated) = next_round.get_all_round_liquidity();
    let next_round_starting_liquidity = next_round.starting_liquidity();
    // Individual spread
    let (mut arr_collateral, mut arr_unallocated) = vault_facade
        .get_all_liquidity_for_n(lps.span());
    loop {
        match arr_collateral.pop_front() {
            Option::Some(collateral) => {
                assert(collateral == amounts.pop_front().unwrap(), 'Collateral Mismatch');
                assert(arr_unallocated.pop_front().unwrap() == 0, 'Unallocated liquidity Mismatch');
            },
            Option::None => { break (); }
        }
    };

    //Check totals on the option round
    assert(next_round_collateral == deposit_total, 'next round collateral wrong');
    assert(next_round_starting_liquidity == deposit_total, 'next round total liq. wrong');
    assert(next_round_unallocated == 0, 'next round unallocated wrong');
}
// Test when an auction starts, it becomes the current round and the
// next round is deployed.
#[test]
#[available_gas(10000000)]
fn test_start_auction_becomes_current_round_deploys_next() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let mut next_round_facade: OptionRoundFacade = vault_facade.get_next_round();
    // LP deposits (into round 1) so its auction can start
    let deposit_amount_wei: u256 = 100 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start round 1's auction
    vault_facade.start_auction();
    // Get the current and next rounds
    let (mut current_round_facade, mut next_round_facade) = vault_facade
        .get_current_and_next_rounds();
    // Check round 1 is auctioning and round 2 is open
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
    let mut current_round: OptionRoundFacade = vault.get_current_round();
    let params = current_round.get_params();
    // Check that auction start event was emitted with correct total_options_available
    assert_event_auction_start(current_round.contract_address(), params.total_options_available);
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
    let _deposit_total = accelerate_to_auctioning_custom(
        ref vault_facade, lps.span(), amounts.span()
    );
    // Start auction
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid
    let option_params = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    vault_facade.timeskip_and_end_auction();
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
    vault_facade.timeskip_and_end_auction();
    // Settle option round
    vault_facade.timeskip_and_settle_round();
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

