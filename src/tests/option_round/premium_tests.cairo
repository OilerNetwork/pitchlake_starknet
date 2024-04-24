// use array::ArrayTrait;
// use debug::PrintTrait;
// use option::OptionTrait;
// use openzeppelin::token::erc20::interface::{
//     IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
//     IERC20SafeDispatcherTrait,
// };
// use pitch_lake_starknet::option_round::{OptionRoundParams};

// use result::ResultTrait;
// use starknet::{
//     ClassHash, ContractAddress, contract_address_const, deploy_syscall,
//     Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
//     testing::{set_block_timestamp, set_contract_address}
// };

use starknet::testing::{set_block_timestamp, set_contract_address};
// use starknet::contract_address::ContractAddressZeroable;
// use openzeppelin::utils::serde::SerializedAppend;

// use traits::Into;
// use traits::TryInto;
// use pitch_lake_starknet::eth::Eth;

use pitch_lake_starknet::tests::{
    option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
    vault_facade::{VaultFacade, VaultFacadeTrait}
};
use pitch_lake_starknet::tests::utils::{
    setup_facade, liquidity_provider_1, decimals, option_bidder_buyer_1,
    option_bidder_buyer_2 // , deploy_vault, allocated_pool_address, unallocated_pool_address,
// timestamp_start_month, timestamp_end_month, liquidity_provider_2,
// , option_bidder_buyer_3, option_bidder_buyer_4,
// vault_manager, weth_owner, mock_option_params, assert_event_transfer
};
use pitch_lake_starknet::tests::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait
};

// Test that collected premiums do not roll over to the next round 
#[test]
#[available_gas(10000000)]
fn test_collected_premium_does_not_roll_over() {
    let (mut vault_facade, _) = setup_facade();
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
    vault_facade.timeskip_and_end_auction();
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
    IMarketAggregatorSetterDispatcher { contract_address: vault_facade.get_market_aggregator() }
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
    let (mut vault_facade, _) = setup_facade();
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
    vault_facade.timeskip_and_end_auction();
    set_contract_address(liquidity_provider_1());
    let claimable_premiums: u256 = params.total_options_available * params.reserve_price;
    // Settle option round with no payout
    set_block_timestamp(params.option_expiry_time + 1);
    IMarketAggregatorSetterDispatcher { contract_address: vault_facade.get_market_aggregator() }
        .set_current_base_fee(params.strike_price - 1);
    vault_facade.settle_option_round(liquidity_provider_1());
    // At this time, remaining liqudity was rolled to the next round (initial deposit + premiums)
    let mut next_option_round: OptionRoundFacade = vault_facade.get_next_round();
    // Check rolled over amount is correct
    let next_round_unallocated: u256 = next_option_round.total_unallocated_liquidity();
    assert(
        next_round_unallocated == deposit_amount_wei + claimable_premiums, 'Rollover amount wrong'
    );
}