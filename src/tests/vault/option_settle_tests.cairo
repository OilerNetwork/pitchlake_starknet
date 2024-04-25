use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait,
    OptionRoundCreated
};
use pitch_lake_starknet::option_round::{OptionRoundParams, OptionRoundState};
use result::ResultTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};

use pitch_lake_starknet::tests::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};
use starknet::contract_address::ContractAddressZeroable;
use openzeppelin::utils::serde::SerializedAppend;

use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{
    setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    zero_address, vault_manager, weth_owner, option_round_contract_address, mock_option_params,
    pop_log, assert_no_events_left, month_duration, setup_return_mkt_agg_facade,
    assert_event_option_settle
};
use pitch_lake_starknet::option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};
use pitch_lake_starknet::tests::mocks::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait,
};
use pitch_lake_starknet::market_aggregator::{
    IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait,
    IMarketAggregatorSafeDispatcher, IMarketAggregatorSafeDispatcherTrait
};

/// helpers
// used ?
fn assert_event_option_created(
    prev_round: ContractAddress,
    new_round: ContractAddress,
    collaterized_amount: u256,
    option_round_params: OptionRoundParams
) {
    let event = pop_log::<OptionRoundCreated>(zero_address()).unwrap();
    assert(event.prev_round == prev_round, 'Invalid prev_round');
    assert(event.new_round == new_round, 'Invalid new_round');
    assert(event.collaterized_amount == collaterized_amount, 'Invalid collaterized_amount');
    assert(event.option_round_params == option_round_params, 'Invalid option_round_params');
    assert_no_events_left(zero_address());
}

// @note move to option_round/state_transition_tests or /option_settle_tests
// Test options cannot settle before expiry date
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'Options cannot settle before expiry',))]
fn test_options_settle_before_expiry_date_failure() {
    let (mut vault_facade, _) = setup_facade();
    // Add liq. to next round
    let deposit_amount_wei = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());

    // Start the option round
    vault_facade.start_auction();

    // OptionRoundDispatcher
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round.get_params();

    // Place bid
    let option_amount: u256 = params.total_options_available;
    let option_price: u256 = params.reserve_price;
    let bid_amount: u256 = option_amount * option_price;
    current_round.place_bid(bid_amount, option_price, option_bidder_buyer_1());

    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    current_round.end_auction();

    // Settle option round before expiry
    set_block_timestamp(params.option_expiry_time - 1);
    vault_facade.settle_option_round(option_bidder_buyer_1());
}

#[test]
#[available_gas(10000000)]
fn test_option_round_settle_success() {
    let (mut vault_facade, _, mut mkt_agg) = setup_return_mkt_agg_facade();
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
    let option_round_params: OptionRoundParams = current_round_facade.get_params();
    set_block_timestamp(option_round_params.auction_end_time + 1);
    let clearing_price: u256 = vault_facade.end_auction();
    assert(clearing_price == option_round_params.reserve_price, 'clearing price wrong');
    // Settle option round
    set_block_timestamp(option_round_params.option_expiry_time + 1);
    vault_facade.settle_option_round(liquidity_provider_1());
    // Check that state is Settled now, auction clearing price is set, and the round is still the current round (round transition period just started)
    let state: OptionRoundState = current_round_facade.get_state();
    let settlement_price: u256 = mkt_agg.get_current_base_fee();
    assert(state == OptionRoundState::Settled, 'state should be Settled');
    assert_event_option_settle(settlement_price);
    assert(vault_facade.current_option_round_id() == 1, 'current round should still be 1');
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('option has already settled', 'ENTRYPOINT_FAILED',))]
fn test_option_round_settle_twice_failure() {
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
    let option_round_params: OptionRoundParams = current_round_facade.get_params();
    set_block_timestamp(option_round_params.auction_end_time + 1);
    vault_facade.end_auction();
    // Settle option round

    vault_facade.timeskip_and_settle_round();
    // Try to settle the option round again
    vault_facade.timeskip_and_settle_round();
}
// @note Add test that eth transfers to next round on settlement
// @note test collateral + unallocated (not claimed) move to next round (unallocated in next round)
//  - test roll over if LP collects from unallocated before roll over (partial and full tests maybe)
// @note add test that unallocated/collateral is 0 when round settles (all rolled over)


