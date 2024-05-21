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
use pitch_lake_starknet::option_round::{
    OptionRoundParams, IOptionRoundDispatcher, IOptionRoundDispatcherTrait
};

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
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    vault_manager, weth_owner, mock_option_params, assert_event_auction_start,
    accelerate_to_auctioning, assert_event_option_round_created,
    liquidity_providers_get, 
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
    let lps = liquidity_providers_get(2);
    let amounts = array![1000 * decimals(), 10000 * decimals()];
    let deposit_total = *amounts[0] + *amounts[1];
    vault_facade.deposit(*amounts[0], liquidity_provider_1());
    vault_facade.deposit(*amounts[1], liquidity_provider_2());
    // Initial collateral/unallocated
    let (lp1_collateral, lp1_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_1());
    let (lp2_collateral, lp2_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_2());
    let (next_round_collateral, next_round_unallocated) = next_round.get_all_round_liquidity();
    let next_round_total_liquidity = next_round.total_liquidity();
    // Check initial spread
    assert(lp1_collateral == 0, 'lp1 collateral wrong');
    assert(lp2_collateral == 0, 'lp2 collateral wrong');
    assert(next_round_collateral == 0, 'next round collateral wrong');
    assert(next_round_total_liquidity == 0, 'next round total liq. wrong');
    assert(lp2_unallocated == *amounts[0], 'lp2 unallocated wrong');
    assert(lp1_unallocated == *amounts[1], 'lp1 unallocated wrong');
    assert(next_round_unallocated == deposit_total, 'next round unallocated wrong');
    // Start the auction
    vault_facade.start_auction();
    // Final collateral/unallocated spread
    let (lp1_collateral, lp1_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_1());
    let (lp2_collateral, lp2_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_2());
    let (next_round_collateral, next_round_unallocated) = next_round.get_all_round_liquidity();
    let next_round_total_liquidity = next_round.total_liquidity();
    // Check final spread
    assert(lp1_collateral == *amounts[0], 'lp1 collateral wrong');
    assert(lp2_collateral == *amounts[1], 'lp2 collateral wrong');
    assert(next_round_collateral == deposit_total, 'next round collateral wrong');
    assert(next_round_total_liquidity == deposit_total, 'next round total liq. wrong');
    assert(lp1_unallocated == 0, 'lp1 unallocated wrong');
    assert(lp2_unallocated == 0, 'lp2 unallocated wrong');
    assert(next_round_unallocated == 0, 'next round unallocated wrong');
}

// Test when an auction starts, it becomes the current round and the
// next round is deployed.
#[test]
#[available_gas(10000000)]
fn test_start_auction_becomes_current_round() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let mut next_round_facade: OptionRoundFacade = vault_facade.get_next_round();
    assert(vault_facade.get_current_round_id() == 0, 'current round should be 0');
    assert(
        current_round_facade.get_state() == OptionRoundState::Settled,
        'current round should be settled'
    );
    assert(next_round_facade.get_state() == OptionRoundState::Open, 'next round should be open');
    // LP deposits (into round 1) so its auction can start
    let deposit_amount_wei: u256 = 100 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start round 1's auction
    vault_facade.start_auction();
    // Get the current and next rounds
    current_round_facade = vault_facade.get_current_round();
    next_round_facade = vault_facade.get_next_round();
    // Check round 1 is auctioning
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
    let (mut current_round, mut next_round) = vault.get_current_and_next_rounds();
    accelerate_to_auctioning(ref vault);
    let params = next_round.get_params();

    // Check that auction start event was emitted with correct total_options_available
    assert_event_option_round_created(
        vault.contract_address(),
        current_round.contract_address(),
        next_round.contract_address(),
        //'replace with amnt in accelerator',// the amount of unallocateed liquidity in the next round that bec
        params
    );
}


/// Failures ///

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
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    set_block_timestamp(option_params.auction_end_time + 1);
    vault_facade.end_auction();
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
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    set_block_timestamp(option_params.auction_end_time + 1);
    vault_facade.end_auction();
    // Settle option round
    set_block_timestamp(option_params.option_expiry_time + 1);
    vault_facade.settle_option_round(liquidity_provider_1());
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

