// use array::ArrayTrait;
// use debug::PrintTrait;
// use option::OptionTrait;
use openzeppelin::token::erc20::interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait,// IERC20SafeDispatcher,IERC20SafeDispatcherTrait,
};
use pitch_lake_starknet::option_round::{OptionRoundParams};

// use result::ResultTrait;
// use starknet::{
//     ClassHash, ContractAddress, contract_address_const, deploy_syscall,
//     Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
//     testing::{set_block_timestamp}
// };
use starknet::testing::{set_block_timestamp, set_contract_address};

// use starknet::contract_address::ContractAddressZeroable;
// use openzeppelin::utils::serde::SerializedAppend;

// use traits::Into;
// use traits::TryInto;
// use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::{
    vault_facade::{VaultFacade, VaultFacadeTrait},
    option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}
};
use pitch_lake_starknet::tests::utils::{
    setup_facade, liquidity_provider_1, option_bidder_buyer_1, option_bidder_buyer_2,
    option_bidder_buyer_3, decimals, assert_event_transfer, vault_manager
// , deploy_vault, allocated_pool_address, unallocated_pool_address,
// timestamp_start_month, timestamp_end_month, liquidity_provider_2,
// , option_bidder_buyer_4,
// , weth_owner, mock_option_params
};
use pitch_lake_starknet::tests::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait
};

// Test that an OB with 0 options gets 0 payout
#[test]
#[available_gas(10000000)]
fn test_user_with_no_options_gets_no_payout() {
    let (mut vault_facade, _) = setup_facade();
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

    vault_facade.timeskip_and_end_auction();
    // Settle option round
    // @dev This ensures the market aggregator returns the mocked current price
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: vault_facade.get_market_aggregator()
    };
    mock_maket_aggregator_setter.set_current_base_fee(params.strike_price + 5);
    vault_facade.timeskip_and_settle_round();
    // OB 2 tries to claim a payout
    let claimed_payout_amount: u256 = option_round.exercise_options(option_bidder_buyer_2());
    assert(
        claimed_payout_amount == 0, 'nothing should be claimed'
    ); // option_bidder_buyer_2 never auction_place_bid in the auction, so should not be able to claim payout
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_sends_eth() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
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
    vault_facade.timeskip_and_end_auction();
    // Settle option round with payout
    let settlement_price = params.reserve_price + 10;
    IMarketAggregatorSetterDispatcher { contract_address: vault_facade.get_market_aggregator() }
        .set_current_base_fee(settlement_price);

    // Settle auction
    vault_facade.timeskip_and_settle_round();
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
    let (mut vault_facade, _) = setup_facade();
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
    vault_facade.timeskip_and_end_auction();
    // Settle option round with payout
    let settlement_price = params.reserve_price + 10;
    IMarketAggregatorSetterDispatcher { contract_address: vault_facade.get_market_aggregator() }
        .set_current_base_fee(settlement_price);
    vault_facade.settle_option_round(liquidity_provider_1());
    // Settle auction
    vault_facade.timeskip_and_settle_round();
    // Check payout balance is expected
    let payout_balance = option_round.get_payout_balance_for(option_bidder_buyer_1());
    let payout_balance_expected = option_round.total_options_sold()
        * (settlement_price - params.strike_price);
    assert(payout_balance == payout_balance_expected, 'expected payout doesnt match');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_amount_index_less_than_strike() {
    let (mut vault_facade, _) = setup_facade();
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
    vault_facade.timeskip_and_end_auction();
    // Settle option round with no payout
    let settlement_price = params.reserve_price - 10;
    IMarketAggregatorSetterDispatcher { contract_address: vault_facade.get_market_aggregator() }
        .set_current_base_fee(settlement_price);
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    vault_facade.timeskip_and_settle_round();
    // Check payout balance is expected
    let payout_balance = option_round.get_payout_balance_for(option_bidder_buyer_1());
    assert(payout_balance == 0, 'expected payout doesnt match');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_amount_index_at_strike() {
    let (mut vault_facade, _) = setup_facade();
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

    vault_facade.end_auction();
    // Settle option round with no payout
    let settlement_price = params.reserve_price;

    IMarketAggregatorSetterDispatcher { contract_address: vault_facade.get_market_aggregator() }
        .set_current_base_fee(settlement_price);
    // Settle auction

    vault_facade.timeskip_and_settle_round();
    // Check payout balance is expected
    let payout_balance = option_round.get_payout_balance_for(option_bidder_buyer_1());
    assert(payout_balance == 0, 'expected payout doesnt match');
}


#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot exercise before round settles ', 'ENTRYPOINT_FAILED',))]
fn test_exercise_options_too_early_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();

    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    set_contract_address(vault_manager());
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
    // Should fail as option has not settled
    current_round_facade.exercise_options(option_bidder_buyer_1());
}