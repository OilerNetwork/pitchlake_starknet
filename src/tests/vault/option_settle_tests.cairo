use debug::PrintTrait;
use option::OptionTrait;
use result::ResultTrait;
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
        utils, vault::{utils::{accelerate_to_auctioning, accelerate_to_running}},
        vault_facade::{VaultFacade, VaultFacadeTrait},
        option_round_facade::{
            OptionRoundParams, OptionRoundState, OptionRoundFacade, OptionRoundFacadeTrait
        },
        mocks::mock_market_aggregator::{
            MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
            IMarketAggregatorSetterDispatcherTrait
        },
        utils::{
            setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
            timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
            option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
            option_bidder_buyer_4, zero_address, vault_manager, weth_owner,
            option_round_contract_address, mock_option_params, pop_log, assert_no_events_left,
            month_duration, assert_event_option_settle, assert_event_transfer, clear_event_logs
        },
    }
};

// @note move to option_round/state_transition_tests or /option_settle_tests
// Test options cannot settle before expiry date
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'Options cannot settle before expiry',))]
fn test_options_settle_before_expiry_date_failure() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity, start and end auction, minting all options at reserve price
    accelerate_to_running(ref vault_facade);

    // Settle option round before expiry
    let mut current_round = vault_facade.get_current_round();
    let params = current_round.get_params();
    set_block_timestamp(params.option_expiry_time - 1);
    vault_facade.settle_option_round(option_bidder_buyer_1());
}

#[test]
#[available_gas(10000000)]
fn test_option_round_settle_updates_round_states() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity, start and end auction, minting all options at reserve price
    accelerate_to_running(ref vault_facade);
    // Settle option round
    vault_facade.timeskip_and_settle_round();

    // Check that the current round is Settled, and the next round is Open
    let (mut current_round, mut next_round) = vault_facade.get_current_and_next_rounds();
    assert(
        current_round.get_state() == OptionRoundState::Settled, 'current round should be Settled'
    );
    assert(next_round.get_state() == OptionRoundState::Open, 'next round should be Open');
}

// Test the settling the round fires an event for the settlement price
#[test]
#[available_gas(10000000)]
fn test_option_round_settle_event() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity, start and end auction, minting all options at reserve price
    accelerate_to_running(ref vault_facade);
    // End auction with settlement price of 123
    utils::accelerate_to_settled(ref vault_facade, 123);

    // Assert event emits correctly
    let mut current_round = vault_facade.get_current_round();
    assert_event_option_settle(current_round.contract_address(), 123);
}

// @note If there needs to be a storage var for the settlement price, add test/facade/entrypoint for it

// Test settling the option round twice fails
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Round has already settled', 'ENTRYPOINT_FAILED',))]
fn test_option_round_settle_twice_failure() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit into the next round, start and end its auction, minting all options at reserve price
    accelerate_to_running(ref vault_facade);
    // Jump to option expiry time and settle the round
    vault_facade.timeskip_and_settle_round();
    // Try to settle the option round again
    vault_facade.timeskip_and_settle_round();
}

// Test current round's remaining liquidity adds to the next round's unallocated when there is no payout, and no premiums collected
#[test]
#[available_gas(1000000000)]
fn test_option_round_settle_moves_remaining_liquidity_to_next_round_without_payout_without_premiums_collected() {
    _test_option_round_settle_moves_remaining_liquidity_to_next_round_with_or_without_payout_AND_with_or_without_premiums_collected(
        false, false
    );
}

// Test current round's remaining liquidity adds to the next round's unallocated when there is a payout,
#[test]
#[available_gas(1000000000)]
fn test_option_round_settle_moves_remaining_liquidity_to_next_round_with_payout_without_premiums_collected() {
    _test_option_round_settle_moves_remaining_liquidity_to_next_round_with_or_without_payout_AND_with_or_without_premiums_collected(
        true, false
    );
}

// Test current round's remaining liquidity adds to the next round's unallocated when there is no payout, and some premiums collected
#[test]
#[available_gas(1000000000)]
fn test_option_round_settle_moves_remaining_liquidity_to_next_round_without_payout_with_premiums_collected() {
    _test_option_round_settle_moves_remaining_liquidity_to_next_round_with_or_without_payout_AND_with_or_without_premiums_collected(
        false, true
    );
}

// Test current round's remaining liquidity adds to the next round's unallocated when there is a payout, and some premiums collected
#[test]
#[available_gas(1000000000)]
fn test_option_round_settle_moves_remaining_liquidity_to_next_round_with_payout_with_premiums_collected() {
    _test_option_round_settle_moves_remaining_liquidity_to_next_round_with_or_without_payout_AND_with_or_without_premiums_collected(
        true, true
    );
}

// Internal test function to be called by external tests. Tests the correcnt remaining liquidity transfers to the next round
// and the round & lps collateral/unallocated updates correctly.
// @dev This internal test can be used to test multiple scenarios (with or without payouts, and with or without lps collecting premiums)
// @note Expand test to having LP1 and 2 deposit into the next round before current settles, will get better coverage

// @note Total collateral will remain fixed at the starting value (for now) in case we need it for conversion rates later
//  - Could have another variable option_round::starting_liquidity if we think setting collateral to 0 makes more sense upon settlement
fn _test_option_round_settle_moves_remaining_liquidity_to_next_round_with_or_without_payout_AND_with_or_without_premiums_collected(
    is_payouts: bool, is_premiums_collected: bool
) {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    // LP2 deposits liquidity into round 1
    // @dev The accelerator helper will deposit liquidity into the next round for LP1,
    // so we are matching that deposit for more test coverage (multiple lps)
    // @note Make sure this value matches lp1's deposit in the accelerate_to_auctioning function
    let deposit_amount = 100 * decimals();
    vault_facade.deposit(deposit_amount, liquidity_provider_1());
    // Start and end auction, minting all options at reserve price
    accelerate_to_running(ref vault_facade);

    // LP1 does or does not collect their premiums
    if is_premiums_collected {
        vault_facade.collect_premiums(liquidity_provider_1());
    }

    // ETH balance of current/next round before settlement
    let (mut current_round, mut next_round) = vault_facade.get_current_and_next_rounds();
    let current_round_eth_init = eth_dispatcher.balance_of(current_round.contract_address());
    let next_round_eth_init = eth_dispatcher.balance_of(next_round.contract_address());
    // Expected rollover amount for the current round and both LPs
    let mut expected_rollover_round = deposit_amount * 2;
    let mut expected_rollover_lp1 = deposit_amount;
    let mut expected_rollover_lp2 = deposit_amount;
    // Earned premiums rollover to the next round
    expected_rollover_round += current_round.total_premiums();
    expected_rollover_lp2 += current_round.total_premiums() / 2;
    expected_rollover_lp1 += current_round.total_premiums() / 2;
    // If premiums were collected, they are not included in the rollover
    if is_premiums_collected {
        let lp1_collected_amount = current_round.total_unallocated_liquidity_collected();
        expected_rollover_round -= lp1_collected_amount;
        expected_rollover_lp1 -= lp1_collected_amount;
    }
    // If there is a payout, it is not included in the rollover
    if is_payouts {
        // LPs share the round's loss
        expected_rollover_round -= current_round.total_payout();
        expected_rollover_lp1 -= current_round.total_payout() / 2;
        expected_rollover_lp2 -= current_round.total_payout() / 2;
    }

    // Clear eth transfer events log
    clear_event_logs(array![eth_dispatcher.contract_address]);

    // Settle option round with or without payout
    let settlement_price = match is_payouts {
        true => 2 * current_round.get_params().reserve_price,
        false => 0
    };

    utils::accelerate_to_settled(ref vault_facade, settlement_price);
    let remaining_liquidity = current_round.get_remaining_liquidity();

    // LP unallocated and round ETH balances before round settle
    let (_, lp1_unallocated_final) = vault_facade.get_all_lp_liquidity(liquidity_provider_1());
    let (_, lp2_unallocated_final) = vault_facade.get_all_lp_liquidity(liquidity_provider_2());
    let (_, next_round_unallocated_final) = next_round.get_all_round_liquidity();
    let current_round_eth_final = eth_dispatcher.balance_of(current_round.contract_address());
    let next_round_eth_final = eth_dispatcher.balance_of(next_round.contract_address());

    // Assert our get_remaining_liquidity helper is working as expected
    assert(
        expected_rollover_round == expected_rollover_lp1 + expected_rollover_lp2,
        'remaining liquidity wrong math'
    );
    assert(remaining_liquidity == expected_rollover_round, 'remaining liquidity incorrect');
    // Check rolled over liquidity becomes unallocated after settlement
    assert(lp1_unallocated_final == expected_rollover_lp1, 'lp1 rollover incorrect');
    assert(lp2_unallocated_final == expected_rollover_lp2, 'lp2 rollover incorrect');
    assert(next_round_unallocated_final == remaining_liquidity, 'settle shd set next rnd unalloc');
    // Check eth transfer
    assert(
        current_round_eth_final == current_round_eth_init - remaining_liquidity,
        'current round eth shd dec.'
    );
    assert(
        next_round_eth_final == next_round_eth_init + remaining_liquidity, 'next round eth shd inc.'
    );

    // Assert transfer event
    assert_event_transfer(
        eth_dispatcher.contract_address,
        current_round.contract_address(),
        next_round.contract_address(),
        remaining_liquidity
    );
}

