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
            month_duration, assert_event_option_settle, assert_event_transfer, clear_event_logs,
            accelerate_to_settled, accelerate_to_auctioning, accelerate_to_running,
            accelerate_to_auctioning_custom, liquidity_providers_get
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
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);

    // Settle option round before expiry
    let mut current_round = vault_facade.get_current_round();
    let params = current_round.get_params();
    set_block_timestamp(params.option_expiry_time - 1);
    vault_facade.settle_option_round();
}

#[test]
#[available_gas(10000000)]
fn test_option_round_settle_updates_round_states() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);
    accelerate_to_settled(ref vault_facade, 0x123);

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
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);
    accelerate_to_settled(ref vault_facade, 0x123);

    // Assert event emits correctly
    let mut current_round = vault_facade.get_current_round();
    assert_event_option_settle(current_round.contract_address(), 0x123);
}

// @note If there needs to be a storage var for the settlement price, add test/facade/entrypoint for it

// Test settling the option round twice fails
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Round has already settled', 'ENTRYPOINT_FAILED',))]
fn test_option_round_settle_twice_failure() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit into the next round, start and end its auction, minting all options at reserve price, settle option round
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);
    accelerate_to_settled(ref vault_facade, 0x123);
    // Try to settle the option round again
    vault_facade.settle_option_round();
}

// Test eth transfers from vault to option round when round settles with a payout
#[test]
#[available_gas(10000000)]
fn test_option_settle_sends_payout_to_round_eth_transfer() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);

    let mut current_round = vault_facade.get_current_round();
    let vault_balance_init = eth_dispatcher.balance_of(vault_facade.contract_address());
    let round_balance_init = eth_dispatcher.balance_of(current_round.contract_address());

    accelerate_to_settled(ref vault_facade, 2 * current_round.get_strike_price());

    let payout = current_round.total_payout();
    let vault_balance_final = eth_dispatcher.balance_of(vault_facade.contract_address());
    let round_balance_final = eth_dispatcher.balance_of(current_round.contract_address());

    assert(vault_balance_final == vault_balance_init - payout, 'vault eth balance shd decrease');
    assert(round_balance_final == round_balance_init + payout, 'round eth balance shd increase');
}


// Test that when the round settles, the payout comes from the vault's (and lp's) locked balance
#[test]
#[available_gas(10000000)]
fn test_option_settle_payout_comes_from_locked() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning_custom(
        ref vault_facade,
        liquidity_providers_get(2).span(),
        array![100 * decimals(), 200 * decimals()].span()
    );
    accelerate_to_running(ref vault_facade);

    let mut current_round = vault_facade.get_current_round();
    let vault_locked_init = vault_facade.get_locked_balance();
    let lp1_locked_init = vault_facade.get_lp_locked_balance(liquidity_provider_1());
    let lp2_locked_init = vault_facade.get_lp_locked_balance(liquidity_provider_2());

    accelerate_to_settled(ref vault_facade, 2 * current_round.get_strike_price());

    // @dev Payout comes from locked balance, but once the round setltes, all liquidity is unlocked
    let payout = current_round.total_payout();
    let vault_unlocked_final = vault_facade.get_locked_balance();
    let lp1_unlocked_final = vault_facade.get_lp_unlocked_balance(liquidity_provider_1());
    let lp2_unlocked_final = vault_facade.get_lp_unlocked_balance(liquidity_provider_2());

    assert(vault_unlocked_final == vault_locked_init - payout, 'vault unlocked wrong');
    assert(lp1_unlocked_final == lp1_locked_init - payout / 3, 'lp1 unlocked wrong');
    assert(lp2_unlocked_final == lp2_locked_init - 2 * payout / 3, 'lp2 unlocked wrong');
}

// @note This test is similar to the ones in unallocated_liquidity_tests.cairo
// Test that when the round settles, locked and unlocked balances are updated (with additional deposits and withdraws)
#[test]
#[available_gas(10000000)]
fn test_option_settle_locked_becomes_unlocked() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning_custom(
        ref vault_facade,
        liquidity_providers_get(2).span(),
        array![100 * decimals(), 200 * decimals()].span()
    );
    accelerate_to_running(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();

    let vault_locked_init = vault_facade.get_locked_balance();
    let lp1_locked_init = vault_facade.get_lp_locked_balance(liquidity_provider_1());
    let lp2_locked_init = vault_facade.get_lp_locked_balance(liquidity_provider_2());

    // LP1 deposits another 100 eth, LP2 withdraw's 1/2 of their earned premiums, then the round settles
    let lp1_deposit_amount = 100 * decimals();
    vault_facade.deposit(lp1_deposit_amount, liquidity_provider_1());
    let lp2_premiums = (2 * current_round.total_premiums()) / 3;
    let lp2_withdraw_amount = lp2_premiums / 2;
    vault_facade.withdraw(lp2_withdraw_amount, liquidity_provider_2());
    accelerate_to_settled(ref vault_facade, 2 * current_round.get_strike_price());

    // @dev Payout comes from locked balance, but once the round setltes, all liquidity is unlocked
    let payout = current_round.total_payout();
    let vault_unlocked_final = vault_facade.get_locked_balance();
    let lp1_unlocked_final = vault_facade.get_lp_unlocked_balance(liquidity_provider_1());
    let lp2_unlocked_final = vault_facade.get_lp_unlocked_balance(liquidity_provider_2());

    assert(
        vault_unlocked_final == vault_locked_init
            - payout
            + lp1_deposit_amount
            - lp2_withdraw_amount,
        'vault unlocked wrong'
    );
    assert(
        lp1_unlocked_final == lp1_locked_init - payout / 3 + lp1_deposit_amount,
        'lp1 unlocked wrong'
    );
    assert(
        lp2_unlocked_final == lp2_locked_init - (2 * payout / 3) - lp2_withdraw_amount,
        'lp2 unlocked wrong'
    );
}

// Test option round settles with no payout does not send eth or effect locked balances
#[test]
#[available_gas(10000000)]
fn test_option_round_settle_no_payout_does_nothing() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);

    let mut current_round = vault_facade.get_current_round();
    let vault_balance_init = eth_dispatcher.balance_of(vault_facade.contract_address());
    let round_balance_init = eth_dispatcher.balance_of(current_round.contract_address());
    let vault_locked_init = vault_facade.get_locked_balance();
    let lp_locked_init = vault_facade.get_lp_locked_balance(liquidity_provider_1());

    accelerate_to_settled(ref vault_facade, 2 * current_round.get_strike_price());

    // @dev Locked balances become unlocked when round settles
    let vault_balance_final = eth_dispatcher.balance_of(vault_facade.contract_address());
    let round_balance_final = eth_dispatcher.balance_of(current_round.contract_address());
    let vault_unlocked_final = vault_facade.get_locked_balance();
    let lp_unlocked_final = vault_facade.get_lp_locked_balance(liquidity_provider_1());

    assert(vault_balance_final == vault_balance_init, 'vault eth bal. shd not change');
    assert(round_balance_final == round_balance_init, 'round eth bal. shd not change');
    assert(vault_unlocked_final == vault_locked_init, 'vault locked shd not change');
    assert(lp_unlocked_final == lp_locked_init, 'lp1 locked shd not change');
}

