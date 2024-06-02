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
        IVaultSafeDispatcherTrait,
    },
    tests::{
        utils::{
            event_helpers::{pop_log, assert_no_events_left, assert_event_auction_end},
            accelerators::{
                accelerate_to_auctioning, accelerate_to_running, create_array_linear,
                create_array_gradient, accelerate_to_auctioning_custom,
                accelerate_to_running_custom, accelerate_to_settled, sum_u256_array,
            },
            test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                liquidity_providers_get, option_bidders_get,
            },
            variables::{decimals}, setup::{setup_facade},
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
    option_round::{OptionRoundState, IOptionRoundDispatcher, IOptionRoundDispatcherTrait},
};
use debug::PrintTrait;

// @note these test can be put into 1 test, see not in auction_start_tests.cairo

// Test auction cannot end if it has not started
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot end auction before it starts', 'ENTRYPOINT_FAILED'))]
fn test_auction_end_before_start_failure() {
    let (mut vault_facade, _) = setup_facade();
    // OptionRoundDispatcher
    let mut next_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = next_round.get_params();

    // Add liq. to next round
    let deposit_amount_wei = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());

    // Try to end auction before it starts
    set_block_timestamp(params.option_expiry_time + 1);
    vault_facade.settle_option_round();
}

// Test auction cannot end before the auction end date
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'Auction cannot settle before due time',))]
fn test_auction_end_before_end_date_failure() {
    let (mut vault_facade, _) = setup_facade();
    // Add liq. to current round
    // note Why some deposits are by option_bidder
    let deposit_amount_wei = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, option_bidder_buyer_1());

    // Start the auction
    vault_facade.start_auction();

    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round.get_params();

    // Try to end auction before the end time
    set_block_timestamp(params.auction_end_time - 1);
    vault_facade.end_auction();
}

#[test]
#[available_gas(10000000)]
fn test_vault_end_auction_success_single() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    // Make bid and end auction
    let (clearing_price, _) = accelerate_to_running(ref vault_facade);
    // Check that state is running and clearing price set
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let state: OptionRoundState = current_round_facade.get_state();
    let expectedState: OptionRoundState = OptionRoundState::Running;
    assert(clearing_price == current_round_facade.get_reserve_price(), 'should be reserve_price');
    assert(expectedState == state, 'round should be Running');
}

// Test that the auction end event emits correctly
#[test]
#[available_gas(10000000)]
fn test_vault_end_auction_event() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    // Make bid and end auction
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let (clearing_price, _) = accelerate_to_running(ref vault_facade);

    // Assert event emitted correctly
    assert_event_auction_end(current_round_facade.contract_address(), clearing_price);
}

// @note This should be a clearing price test and might already be covered
// Test that the auction clearing price is set post auction end, and state updates to Running
#[test]
#[available_gas(10000000)]
fn test_vault_end_auction_success_multi() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let amounts = create_array_linear(10000 * decimals(), 5);
    let lps = liquidity_providers_get(5);
    accelerate_to_auctioning_custom(ref vault_facade, lps.span(), amounts.span());
    // Start auction

    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid
    let option_params = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    let bidders = option_bidders_get(5);
    let bid_amounts = create_array_gradient(bid_amount, 10 * decimals(), 5);
    let bid_prices = create_array_linear(bid_price, 5);

    // Settle auction
    let (clearing_price, _) = accelerate_to_running_custom(
        ref vault_facade, bidders.span(), bid_amounts.span(), bid_prices.span()
    );

    assert(clearing_price == *bid_prices[4], 'should be reserve_price');
    // Check that state is Running now, and auction clearing price is set
    let state: OptionRoundState = current_round_facade.get_state();
    let expectedState: OptionRoundState = OptionRoundState::Running;
    assert(expectedState == state, 'round should be Running');
    // Check auction clearing price event
    assert_event_auction_end(
        current_round_facade.contract_address(), current_round_facade.get_auction_clearing_price()
    );
}

// Test that the auction cannot be ended twice
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('The auction has already ended', 'ENTRYPOINT_FAILED',))]
fn test_option_round_end_auction_twice_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    // @note need accelerators
    //set_contract_address(vault_manager());
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid
    let option_params = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    set_block_timestamp(option_params.auction_end_time + 1);
    vault_facade.end_auction();
    // Try to settle auction a second time
    vault_facade.end_auction();
}
// @note Add tests that unallocated/collatera (lp and round) update at auction end
//    - test unallocate in current round goes from 0 -> premiums + unsold liq.

// @note Add test that premiums go to vault::unloccked and vault::lp::unlocked (and eth transfer to from round to vault)

// Test that premiums are sent to the vault and unused bids remain in the round
#[test]
#[available_gas(10000000)]
fn test_premiums_sent_to_vault_eth_transfer() {
    let (mut vault_facade, eth) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);

    // Make bids
    let (mut current_round, _) = vault_facade.get_current_and_next_rounds();
    let bid_count = current_round.get_total_options_available();
    let bid_price = current_round.get_reserve_price();
    let bid_amount = bid_count * bid_price;
    current_round
        .place_bids(
            array![bid_amount, 2 * bid_amount].span(),
            array![bid_price, 2 * bid_price].span(),
            array![option_bidder_buyer_1(), option_bidder_buyer_2()].span(),
        );

    // Balances before auction end
    let round_balance_before = eth.balance_of(current_round.contract_address());
    let vault_balance_before = eth.balance_of(vault_facade.contract_address());

    // End auction
    accelerate_to_running_custom(
        ref vault_facade,
        array![option_bidder_buyer_1()].span(),
        array![bid_amount].span(),
        array![bid_price].span()
    );

    // Balances after auction end
    let round_balance_after = eth.balance_of(current_round.contract_address());
    let vault_balance_after = eth.balance_of(vault_facade.contract_address());
    let total_premiums = 2
        * current_round.get_total_options_available()
        * current_round.get_reserve_price();
    assert(
        total_premiums == current_round.total_premiums(), 'total premium wrong'
    ); // makes sure the setup is correct

    // Check eth transfers from round to vault
    assert(round_balance_after == round_balance_before - total_premiums, 'round shd lose eth');
    assert(round_balance_after == total_premiums / 2, 'round shd keep some eth');
    assert(vault_balance_after == vault_balance_before + total_premiums, 'vault shd gain eth');
}

#[test]
#[available_gas(10000000)]
fn test_premiums_update_vault_and_lp_unlocked() {
    let (mut vault_facade, _) = setup_facade();
    let lps = liquidity_providers_get(2);
    let deposits = array![50 * decimals(), 100 * decimals()];
    let total_deposits = sum_u256_array(deposits.span());
    let total_options_available = accelerate_to_auctioning_custom(
        ref vault_facade, lps.span(), deposits.span()
    );
    accelerate_to_running(ref vault_facade);
    let (mut current_round, _) = vault_facade.get_current_and_next_rounds();

    let (vault_locked, vault_unlocked) = vault_facade.get_balance_spread();
    let (lp1_locked, lp1_unlocked) = vault_facade.get_lp_balance_spread(liquidity_provider_1());
    let (lp2_locked, lp2_unlocked) = vault_facade.get_lp_balance_spread(liquidity_provider_2());
    let total_premiums = current_round.total_premiums();

    // Check locked and unlocked balances correct
    assert(vault_locked == total_deposits, 'vault locked wrong');
    assert(vault_unlocked == total_premiums, 'vault unlocked wrong');

    assert(lp1_locked == *deposits[0], 'lp1 locked wrong');
    assert(lp1_unlocked == total_premiums / 3, 'lp1 unlocked wrong');

    assert(lp2_locked == *deposits[1], 'lp2 locked wrong');
    assert(lp2_unlocked == 2 * total_premiums / 3, 'lp2 unlocked wrong');
}
// @note Add test like one above but with an extra deposit into unlocked during auction. This will test that only the round partipants get the premium, not just unlocekd pool participants


