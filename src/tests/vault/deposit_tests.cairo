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
    eth::Eth, vault::{Vault},
    option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait, OptionRoundState},
    tests::{
        utils_new::{
            event_helpers::{
                assert_event_transfer, pop_log, assert_no_events_left, assert_event_option_settle,
                assert_event_option_round_deployed, assert_event_vault_deposit,
                assert_event_auction_start, assert_event_auction_bid_accepted,
                assert_event_auction_bid_rejected, assert_event_auction_end,
                assert_event_vault_withdrawal, assert_event_unused_bids_refunded,
                assert_event_options_exercised
            },
            accelerators::{
                accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled,
                create_array_gradient, clear_event_logs,
            },
            test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                liquidity_providers_get
            },
        },
        utils::{
            setup_facade, decimals, deploy_vault, timestamp_start_month, timestamp_end_month,
            zero_address, vault_manager, weth_owner, mock_option_params,
        },
        vault_facade::{VaultFacade, VaultFacadeTrait},
        option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
    }
};
use debug::PrintTrait;

// Test when LP deposit, tokens are getting stored in unlocked pool in vault of the next round
#[test]
#[available_gas(10000000)]
fn test_deposit_vault_unlocked_liquidity() {
    let (mut vault_facade, _) = setup_facade();
    let mut _current_round = vault_facade.get_current_round();
    let mut _next_round = vault_facade.get_next_round();

    // get one liquidity provider
    let liquidity_providers = liquidity_providers_get(1);
    // get the initial liquidity of the vault
    let init_liquidity = vault_facade.get_lp_unlocked_balance(*liquidity_providers[0]);
    // @note test vault unlocked as well

    // deposit some amount in the vault
    let deposit_amount = 50 * decimals();
    vault_facade.deposit(deposit_amount, *liquidity_providers[0]);

    // get the liquidity after the first deposit
    let final_liquidity = vault_facade.get_lp_unlocked_balance(*liquidity_providers[0]);

    // liquidity should increase by deposit_amount
    assert(final_liquidity == init_liquidity + deposit_amount, 'vault balance should increase');
}

// test when LP multiple deposit, tokens are getting stored in the unlocked pool in vault of the next round
#[test]
#[available_gas(10000000)]
fn test_multi_deposit_vault_unlocked_liquidity() {
    let (mut vault_facade, _) = setup_facade();
    let mut _current_round = vault_facade.get_current_round();
    let mut _next_round = vault_facade.get_next_round();

    // get one liquidity provider
    let liquidity_providers = liquidity_providers_get(2);
    // get the initial liquidity of the vault
    let init_liquidity_1 = vault_facade.get_lp_unlocked_balance(*liquidity_providers[0]);
    let init_liquidity_2 = vault_facade.get_lp_unlocked_balance(*liquidity_providers[1]);
    // @note test vault unlocked as well

    // deposit some amount in the vault
    let deposit_amount = 50 * decimals();
    vault_facade.deposit(deposit_amount, *liquidity_providers[0]);
    vault_facade.deposit(deposit_amount + 1, *liquidity_providers[1]);

    // get the liquidity after the first deposit
    let final_liquidity_1 = vault_facade.get_lp_unlocked_balance(*liquidity_providers[0]);
    let final_liquidity_2 = vault_facade.get_lp_unlocked_balance(*liquidity_providers[1]);

    // liquidity should increase by deposited amount
    assert(final_liquidity_1 == init_liquidity_1 + deposit_amount, 'vault balance should increase');
    assert(
        final_liquidity_2 == init_liquidity_2 + deposit_amount + 1, 'vault balance should increase'
    );
}

// test when LP deposit, check the balance of the contracts (vault and the sender) are updating accordingly
#[test]
#[available_gas(10000000)]
fn test_deposit_eth_transfer() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    // Current round (settled) and next round (open)
    let mut current_round = vault_facade.get_current_round();
    let mut next_round = vault_facade.get_next_round();
    // Initital eth balances for lp, current round, next round
    let init_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
    let init_current_round_balance = eth_dispatcher.balance_of(current_round.contract_address());
    let init_next_round_balance = eth_dispatcher.balance_of(next_round.contract_address());
    // Deposit into next round
    let deposit_amount = 50 * decimals();
    vault_facade.deposit(deposit_amount, liquidity_provider_1());
    // Final eth balances for lp, current round, next round
    let final_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
    let final_current_round_balance = eth_dispatcher.balance_of(current_round.contract_address());
    let final_next_round_balance = eth_dispatcher.balance_of(next_round.contract_address());
    // Check liquidity changes
    assert(final_lp_balance == init_lp_balance - deposit_amount, 'lp shd send eth');
    assert(final_current_round_balance == init_current_round_balance, 'current eth shd be locked');
    assert(
        final_next_round_balance == init_next_round_balance + deposit_amount, 'next shd receive eth'
    );
    assert_event_transfer(
        eth_dispatcher.contract_address,
        liquidity_provider_1(),
        next_round.contract_address(),
        deposit_amount
    );
}

// test when LP deposit, deposit events are getting fired
#[test]
#[available_gas(10000000)]
fn test_deposit_to_vault_event() {
    let (mut vault_facade, _) = setup_facade();
    let mut _next_round = vault_facade.get_next_round();

    // get one liquidity provider
    let liquidity_providers = liquidity_providers_get(1);
    // get the initial liquidity of the vault
    let init_liquidity = vault_facade.get_lp_unlocked_balance(*liquidity_providers[0]);

    // deposit some amount in the vault
    let deposit_amount = 50 * decimals();
    vault_facade.deposit(deposit_amount, *liquidity_providers[0]);

    // Check vault events emit correctly
    assert_event_vault_deposit(
        vault_facade.contract_address(),
        *liquidity_providers[0],
        init_liquidity,
        init_liquidity + deposit_amount,
    );
}

// test when LP multiple deposit, all the events are getting fired in correct order
#[test]
#[available_gas(10000000)]
fn test_multi_deposit_to_vault_event() {
    let (mut vault_facade, _) = setup_facade();
    let mut _next_round = vault_facade.get_next_round();

    // get one liquidity provider
    let liquidity_providers = liquidity_providers_get(2);
    // get the initial liquidity of the vault
    let init_liquidity_1 = vault_facade.get_lp_unlocked_balance(*liquidity_providers[0]);
    let init_liquidity_2 = vault_facade.get_lp_unlocked_balance(*liquidity_providers[1]);

    // deposit some amount in the vault
    let deposit_amount = 50 * decimals();
    vault_facade.deposit(deposit_amount, *liquidity_providers[0]);
    vault_facade.deposit(deposit_amount, *liquidity_providers[1]);

    // Check vault events emit correctly
    assert_event_vault_deposit(
        vault_facade.contract_address(),
        *liquidity_providers[0],
        init_liquidity_1,
        init_liquidity_1 + deposit_amount,
    );
    assert_event_vault_deposit(
        vault_facade.contract_address(),
        *liquidity_providers[1],
        init_liquidity_2,
        init_liquidity_2 + deposit_amount,
    );
}


// Test that LP cannot deposit zero
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot deposit 0', 'ENTRYPOINT_FAILED'))]
fn test_deposit_zero_liquidity_failure() {
    let (mut vault_facade, _) = setup_facade();
    vault_facade.deposit(0, liquidity_provider_1());
}

// Move to different file
// Test to make sure the event testers are working as expected
#[test]
#[available_gas(100000000)]
fn test_event_testers() {
    let (mut v, e) = setup_facade();
    /// new test, make emission come from entry point on vault,
    let mut r = v.get_current_round();
    set_contract_address(liquidity_provider_1());
    clear_event_logs(array![e.contract_address, v.contract_address(), r.contract_address()]);
    e.transfer(liquidity_provider_2(), 100);
    assert_event_transfer(e.contract_address, liquidity_provider_1(), liquidity_provider_2(), 100);
    r.option_round_dispatcher.rm_me(100);
    assert_event_auction_start(r.contract_address(), 100);
    assert_event_auction_bid_accepted(r.contract_address(), r.contract_address(), 100, 100);
    assert_event_auction_bid_rejected(r.contract_address(), r.contract_address(), 100, 100);
    assert_event_auction_end(r.contract_address(), 100);
    assert_event_option_settle(r.contract_address(), 100);
    assert_event_option_round_deployed(v.contract_address(), 1, v.contract_address());
    assert_event_vault_deposit(v.contract_address(), v.contract_address(), 100, 100);
    assert_event_vault_withdrawal(v.contract_address(), v.contract_address(), 100, 100);
    assert_event_unused_bids_refunded(r.contract_address(), r.contract_address(), 100);
    assert_event_options_exercised(r.contract_address(), r.contract_address(), 100, 100);
}

// Test deposits always go to the vault's unlocked pool
#[test]
#[available_gas(10000000)]
fn test_deposit_is_always_into_unlocked() {
    let (mut vault_facade, _) = setup_facade();
    let deposit_amount = 100 * decimals();

    accelerate_to_auctioning(ref vault_facade);

    // Deposit while current is auctioning
    // @note Using LP2 to check. Allows us to ignore premiums earned from the auction (since they did not supply liquidity in the current round)
    let (lp_locked0, lp_unlocked0) = vault_facade.get_lp_balance_spread(liquidity_provider_2());
    vault_facade.deposit(deposit_amount, liquidity_provider_2());
    let (lp_locked1, lp_unlocked1) = vault_facade.get_lp_balance_spread(liquidity_provider_2());

    assert(lp_locked1 == lp_locked0, 'locked shd not change');
    assert(lp_unlocked1 == lp_unlocked0 + deposit_amount, 'unlocked wrong');

    accelerate_to_running(ref vault_facade);

    // Deposit while current is running
    vault_facade.deposit(deposit_amount, liquidity_provider_2());
    let (lp_locked2, lp_unlocked2) = vault_facade.get_lp_balance_spread(liquidity_provider_2());

    assert(lp_locked2 == lp_locked1, 'locked shd not change');
    assert(lp_unlocked2 == lp_unlocked1 + deposit_amount, 'unlocked wrong');

    accelerate_to_settled(ref vault_facade, 0);

    // Deposit while current is settled
    vault_facade.deposit(deposit_amount, liquidity_provider_2());
    let (lp_locked3, lp_unlocked3) = vault_facade.get_lp_balance_spread(liquidity_provider_2());

    assert(lp_locked3 == lp_locked2, 'locked shd not change');
    assert(lp_unlocked3 == lp_unlocked2 + deposit_amount, 'unlocked wrong');
}

