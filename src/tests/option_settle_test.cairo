use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};
use pitch_lake_starknet::option_round::{OptionRoundParams};

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
use pitch_lake_starknet::tests::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};
use pitch_lake_starknet::tests::{
    utils::{
        setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
        timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
        option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
        vault_manager, weth_owner, mock_option_params
    },
    vault_liquidity_deposit_withdraw_test::assert_event_transfer
};
use pitch_lake_starknet::tests::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait
};

// @note add test that unallocated decrements when round settles (premiums + unsold were rolled over)

// @dev this test belongs (and i think might already exist) in the premium tests, test OB cannot collect premium after round settles

// Test that an OB with 0 options gets 0 payout
#[test]
#[available_gas(10000000)]
fn test_user_with_no_options_gets_no_payout() {
    let (mut vault_facade,_) = setup_facade();
    let mut option_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = option_round.get_params();
    // Deposit liquidity
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Make bid (ob1)
    vault_facade.start_auction();
    let bid_amount: u256 = params.total_options_available;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_amount * bid_price;
    option_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    option_round.end_auction();
    // Settle option round
    set_block_timestamp(params.option_expiry_time + 1);
    // @dev This ensures the market aggregator returns the mocked current price
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: vault_facade.get_market_aggregator()
    };
    mock_maket_aggregator_setter.set_current_base_fee(params.strike_price + 5);
    vault_facade.settle_option_round(liquidity_provider_1());
    // OB 2 tries to claim a payout
    let claimed_payout_amount: u256 = option_round.exercise_options(option_bidder_buyer_2());
    assert(
        claimed_payout_amount == 0, 'nothing should be claimed'
    ); // option_bidder_buyer_2 never auction_place_bid in the auction, so should not be able to claim payout
}

// @note add test that eth transfers to next round on settlement

// Test that collected premiums do not roll over to the next round 
#[test]
#[available_gas(10000000)]
fn test_collected_premium_does_not_roll_over() {
    let (mut vault_facade,_) = setup_facade();
    let mut option_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = option_round.get_params();
    // Deposit liquidity
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Make bid 
    let bid_amount: u256 = params.total_options_available;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_amount * bid_price;
    option_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    option_round.end_auction();
    // Collect premium 
    // @dev Since the round is running withdraw first come from unallocated liquidity
    // - @note need more tests for that
    let claimable_premiums: u256 = params.total_options_available * params.reserve_price;
    vault_facade.withdraw(claimable_premiums, liquidity_provider_1());

    // The round has no more unallocated liquidity because lp withdrew it
    let unallocated_liqudity_after_premium_claim: u256 = option_round.total_unallocated_liquidity();
    assert(unallocated_liqudity_after_premium_claim == 0, 'premium should not roll over');

    // Settle option round with no payout
    set_block_timestamp(params.option_expiry_time + 1);
    IMarketAggregatorSetterDispatcher {
        contract_address: vault_facade.get_market_aggregator()
    }
        .set_current_base_fee(params.strike_price - 1);
    vault_facade.settle_option_round(liquidity_provider_1());
    // At this time, remaining liqudity was rolled to the next round (just initial deposit since there is no payout and premiums were collected)
    let mut next_option_round: OptionRoundFacade = vault_facade.get_next_round();

    // Check rolled over amount is correct
    let next_round_unallocated: u256 = next_option_round.total_unallocated_liquidity();
    assert(next_round_unallocated == deposit_amount_wei, 'Rollover amount wrong');
}

// Test that uncollected premiums roll over
#[test]
#[available_gas(10000000)]
fn test_remaining_liqudity_rolls_over() {
    let (mut vault_facade,_) = setup_facade();
    let mut option_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = option_round.get_params();
    // Deposit liquidity
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Make bid 
    let bid_amount: u256 = params.total_options_available;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_amount * bid_price;
    option_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    option_round.end_auction();
    set_contract_address(liquidity_provider_1());
    let claimable_premiums: u256 = params.total_options_available * params.reserve_price;
    // Settle option round with no payout
    set_block_timestamp(params.option_expiry_time + 1);
    IMarketAggregatorSetterDispatcher {
        contract_address: vault_facade.get_market_aggregator()
    }
        .set_current_base_fee(params.strike_price - 1);
    vault_facade.settle_option_round(liquidity_provider_1());
    // At this time, remaining liqudity was rolled to the next round (initial deposit + premiums)
    let mut next_option_round:OptionRoundFacade=vault_facade.get_next_round();
    // Check rolled over amount is correct
    let next_round_unallocated: u256 = next_option_round.total_unallocated_liquidity();
    assert(
        next_round_unallocated == deposit_amount_wei + claimable_premiums, 'Rollover amount wrong'
    );
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_sends_eth() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    let mut option_round:OptionRoundFacade=vault_facade.get_next_round();
    let params = option_round.get_params();
    // Deposit liquidity
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Make bid (ob1)
    let bid_amount: u256 = 2;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_amount * bid_price;
    option_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    option_round.end_auction();
    // Settle option round with payout
    let settlement_price = params.reserve_price + 10;
    set_block_timestamp(params.option_expiry_time + 1);
    IMarketAggregatorSetterDispatcher {
        contract_address: vault_facade.get_market_aggregator()
    }
        .set_current_base_fee(settlement_price);
    vault_facade.settle_option_round(liquidity_provider_1());
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    option_round.end_auction();
    // Collect payout
    let ob_balance_before = eth_dispatcher.balance_of(option_bidder_buyer_1());
    let payout = option_round.exercise_options(option_bidder_buyer_1());
    let ob_balance_after = eth_dispatcher.balance_of(option_bidder_buyer_1());
    // Check balance updates
    assert(ob_balance_after == ob_balance_before + payout, 'payout not received');
    // Check eth transfer to OB
    assert_event_transfer(option_round.contract_address(), option_bidder_buyer_1(), payout);
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_amount_index_higher_than_strike() {
    let (mut vault_facade,_) = setup_facade();
    let mut option_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = option_round.get_params();
    // Deposit liquidity
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Make bid
    let bid_amount: u256 = 2;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_amount * bid_price;
    option_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    option_round.end_auction();
    // Settle option round with payout
    let settlement_price = params.reserve_price + 10;
    set_block_timestamp(params.option_expiry_time + 1);
    IMarketAggregatorSetterDispatcher {
        contract_address: vault_facade.get_market_aggregator()
    }
        .set_current_base_fee(settlement_price);
    vault_facade.settle_option_round(liquidity_provider_1());
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    option_round.end_auction();
    // Check payout balance is expected
    let payout_balance = option_round.get_payout_balance_for(option_bidder_buyer_1());
    let payout_balance_expected = option_round.total_options_sold()
        * (settlement_price - params.strike_price);
    assert(payout_balance == payout_balance_expected, 'expected payout doesnt match');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_amount_index_less_than_strike() {
    let (mut vault_facade,_) = setup_facade();
    let mut option_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = option_round.get_params();
    // Deposit liquidity
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Make bid (ob1)
    let bid_amount: u256 = 2;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_amount * bid_price;
    option_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    option_round.end_auction();
    // Settle option round with no payout
    let settlement_price = params.reserve_price - 10;
    set_block_timestamp(params.option_expiry_time + 1);
    IMarketAggregatorSetterDispatcher {
        contract_address: vault_facade.get_market_aggregator()
    }
        .set_current_base_fee(settlement_price);
    vault_facade.settle_option_round(liquidity_provider_1());
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    option_round.end_auction();
    // Check payout balance is expected
    let payout_balance = option_round.get_payout_balance_for(option_bidder_buyer_1());
    assert(payout_balance == 0, 'expected payout doesnt match');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_amount_index_at_strike() {
    let (mut vault_facade,_) = setup_facade();
    let mut option_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = option_round.get_params();
    // Deposit liquidity
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Make bid (ob1)
    let bid_amount: u256 = 2;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_amount * bid_price;
    option_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    option_round.end_auction();
    // Settle option round with no payout
    let settlement_price = params.reserve_price;
    set_block_timestamp(params.option_expiry_time + 1);
    IMarketAggregatorSetterDispatcher {
        contract_address: vault_facade.get_market_aggregator()
    }
        .set_current_base_fee(settlement_price);
    vault_facade.settle_option_round(liquidity_provider_1());
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    option_round.end_auction();
    // Check payout balance is expected
    let payout_balance = option_round.get_payout_balance_for(option_bidder_buyer_1());
    assert(payout_balance == 0, 'expected payout doesnt match');
}
// @note Add test that payout is capped even if index >>> strike


