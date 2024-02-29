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
use pitch_lake_starknet::option_round::{OptionRoundParams, OptionRoundState, OptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait};
use pitch_lake_starknet::market_aggregator::{
    IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait,
    IMarketAggregatorSafeDispatcher, IMarketAggregatorSafeDispatcherTrait
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
    setup, decimals, option_round_test_owner, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, vault_manager, weth_owner, mock_option_params,
    assert_event_auction_start, assert_event_auction_settle, assert_event_option_settle
};
use pitch_lake_starknet::tests::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait
};


/// TODO fix enum compares

#[test]
#[available_gas(10000000)]
fn test_round_initialized() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let state: OptionRoundState = vault_dispatcher.get_option_round_state();
    let expectedInitializedValue: OptionRoundState = OptionRoundState::Initialized;
// assert (expectedInitializedValue == state, "state should be Initialized");
// assert (expectedInitializedValue == OptionRoundState::Initialized, "state should be Initialized");
}

// matt:
// matt:
// questions:
// liq is added via vault ? and withdrawn via vault ? lp -> vault -> round & vault -> lp ?
    // when withdrawn from vault, the vault moves from round -> lp ? 
// bids are added via round ?
    // unused bids are refunded via round ? round -> bidder | round -> vault -> bidder ?
        // if $ moves through vault, is that a step of the txn or does bidder need another txn to move from vault -> bidder ?
// auction is 'settled' via round ? 
    // 
#[test]
#[available_gas(10000000)]
fn test_round_start_auction_success_matt() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10 * decimals();
    // depsoit liq
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();
    // get round dispatcher. todo: fetch actual address of round contract once deployed
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: contract_address_const::<'TODO'>()
    };
    // get state of option_round (no longer from vault)
    let state: OptionRoundState = round_dispatcher.get_option_round_state();
    let expectedState: OptionRoundState = OptionRoundState::AuctionStarted;
    assert (expectedState == state, "auction should be started");
}

// matt: what is different between this test and test on line: 196?
#[test]
#[available_gas(10000000)]
fn test_round_start_auction_success() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10 * decimals();
    set_contract_address(liquidity_provider_1());

    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();
    let state: OptionRoundState = vault_dispatcher.get_option_round_state();
    let expectedState: OptionRoundState = OptionRoundState::AuctionStarted;
// assert (expectedState == state, "state should be Initialized");
}

// matt:
#[test]
#[available_gas(10000000)]
fn test_round_clearing_price_pre_auction_end_matt() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10 * decimals();
    // depsoit liq
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();
    // get round dispatcher. todo: fetch actual address of round contract once deployed
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: contract_address_const::<'TODO'>()
    };
    // get clearing price
    let clearing_price: u256 = round_dispatcher.get_auction_clearing_price();
    // clearing price should be 0 as auction has not ended
    assert(
        clearing_price == 0, 'clearing price should be 0'
    ); 
    // todo: check this assert function works with round_dispatcher (vs prev. vault_dispatcher)
    assert_event_auction_start(
        round_dispatcher.get_option_round_params().total_options_available
    );
}

#[test]
#[available_gas(10000000)]
fn test_round_clearing_price_pre_auction_end() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10 * decimals();
    set_contract_address(liquidity_provider_1());

    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();
    let clearing_price: u256 = vault_dispatcher.get_auction_clearing_price(option_round_id);
    assert(
        clearing_price == 0, 'clearing price should be 0'
    ); // should be zero as auction has not ended
    assert_event_auction_start(
        vault_dispatcher.get_option_round_params(option_round_id).total_options_available
    );
}

// matt: 
#[test]
#[available_gas(10000000)]
fn test_round_option_sold_pre_auction_end_matt() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10 * decimals();
    // add liq
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // get round dispatcher. todo: fetch actual address of round contract once deployed
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: contract_address_const::<'TODO'>()
    };
    let options_sold: u256 = round_dispatcher.total_options_sold();
    assert(
        options_sold == 0, 'options_sold should be 0'
    ); // should be zero as auction has not ended
}

#[test]
#[available_gas(10000000)]
fn test_round_option_sold_pre_auction_end() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10 * decimals();
    set_contract_address(liquidity_provider_1());

    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    let options_sold: u256 = vault_dispatcher.total_options_sold();
    assert(
        options_sold == 0, 'options_sold should be 0'
    ); // should be zero as auction has not ended
}

// matt: 
#[test]
#[available_gas(10000000)]
fn test_round_state_started_matt() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // add liq
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();
    // get round dispatcher. todo: fetch actual address of round contract once deployed
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: contract_address_const::<'TODO'>()
    };
    let state: OptionRoundState = round_dispatcher.get_option_round_state();
    assert (state == OptionRoundState::AuctionStarted, "state should be AuctionStarted");
    assert_event_auction_start(
        vault_dispatcher.get_option_round_params(option_round_id).total_options_available
    );
}


#[test]
#[available_gas(10000000)]
fn test_round_state_started() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();
    let state: OptionRoundState = vault_dispatcher.get_option_round_state();
    // assert (state == OptionRoundState::AuctionStarted, "state should be AuctionStarted");
    assert_event_auction_start(
        vault_dispatcher.get_option_round_params(option_round_id).total_options_available
    );
}

// matt: AuctionEnded is no longer an enum, only AuctionSettled, duplicating tests for now
#[test]
#[available_gas(10000000)]
fn test_round_state_auction_ended_matt() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // add liq
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();
    // get round dispatcher. todo: fetch actual address of round contract once deployed
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: contract_address_const::<'TODO'>()
    };
    // todo: check this assert function works with round_dispatcher (vs prev. vault_dispatcher)
    assert_event_auction_start(
        round_dispatcher.get_option_round_params().total_options_available
    );
    // warp forward
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();
    let state: OptionRoundState = round_dispatcher.get_option_round_state();
    assert (state == OptionRoundState::AuctionSettled, "state should be AuctionEnded");
    // todo: check this assert function works with round_dispatcher (vs prev. vault_dispatcher)
    assert_event_auction_settle(round_dispatcher.get_auction_clearing_price());
}


#[test]
#[available_gas(10000000)]
fn test_round_state_auction_ended() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();
    assert_event_auction_start(
        vault_dispatcher.get_option_round_params(option_round_id).total_options_available
    );

    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();
    let state: OptionRoundState = vault_dispatcher.get_option_round_state();
    // assert (state == OptionRoundState::AuctionEnded, "state should be AuctionEnded");
    assert_event_auction_settle(vault_dispatcher.get_auction_clearing_price(option_round_id));
}

// test is identical to test_round_state_auction_ended(_matt) (see line 212)
#[test]
#[available_gas(10000000)]
fn test_round_state_auction_settled_matt() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // add liq
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();
    set_block_timestamp(option_params.auction_end_time + 1);
    // get round dispatcher. todo: fetch actual address of round contract once deployed
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: contract_address_const::<'TODO'>()
    };
    round_dispatcher.settle_auction();
    let state: OptionRoundState = round_dispatcher.get_option_round_state();
    assert (state == OptionRoundState::AuctionSettled, "state should be Settled");
}


#[test]
#[available_gas(10000000)]
fn test_round_state_auction_settled() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();
    let state: OptionRoundState = vault_dispatcher.get_option_round_state();
// assert (state == OptionRoundState::AuctionSettled, "state should be Settled");
}

// matt:
#[test]
#[available_gas(10000000)]
fn test_round_state_option_settled_matt() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // add liq
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();
    // warp forward
    set_block_timestamp(option_params.auction_end_time + 1);
    // get round dispatcher. todo: fetch actual address of round contract once deployed
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: contract_address_const::<'TODO'>()
    };
    round_dispatcher.settle_auction();
    let state: OptionRoundState = round_dispatcher.get_option_round_state();
    set_block_timestamp(option_params.option_expiry_time + 1);

    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: round_dispatcher.get_market_aggregator().contract_address
    };
    mock_maket_aggregator_setter.set_current_base_fee(option_params.reserve_price);

    round_dispatcher.settle_option_round();

    let state: OptionRoundState = round_dispatcher.get_option_round_state();
    let settlement_price: u256 = round_dispatcher.get_market_aggregator().get_current_base_fee();
    assert (state == OptionRoundState::OptionSettled, "state should be Settled");
    assert_event_option_settle(settlement_price);
}

#[test]
#[available_gas(10000000)]
fn test_round_state_option_settled() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();
    let state: OptionRoundState = vault_dispatcher.get_option_round_state();
    set_block_timestamp(option_params.option_expiry_time + 1);

    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: vault_dispatcher.get_market_aggregator().contract_address
    };
    mock_maket_aggregator_setter.set_current_base_fee(option_params.reserve_price);

    vault_dispatcher.settle_option_round();

    let state: OptionRoundState = vault_dispatcher.get_option_round_state();
    let settlement_price: u256 = vault_dispatcher.get_market_aggregator().get_current_base_fee();
    // assert (state == OptionRoundState::OptionSettled, "state should be Settled");
    assert_event_option_settle(settlement_price);
}

// matt:
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'option has already settled',))]
fn test_round_double_settle_failure_matt() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // add liq
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();
    // warp forward
    set_block_timestamp(option_params.auction_end_time + 1);
    // get round dispatcher. todo: fetch actual address of round contract once deployed
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: contract_address_const::<'TODO'>()
    };
    round_dispatcher.settle_auction();
    set_block_timestamp(option_params.option_expiry_time + 1);

    round_dispatcher.settle_option_round();
    round_dispatcher.settle_option_round();
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'option has already settled',))]
fn test_round_double_settle_failure() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();
    set_block_timestamp(option_params.option_expiry_time + 1);

    vault_dispatcher.settle_option_round();
    vault_dispatcher.settle_option_round();
}


// #[test]
// #[available_gas(10000000)]
// #[should_panic(expected: ('Some error', 'only owner can start auction',))]
// fn test_round_start_auction_failure() {
//     let vault_dispatcher: IOptionRoundDispatcher = deploy_option_round(option_round_test_owner());
//     set_contract_address(liquidity_provider_1());
//     vault_dispatcher.start_auction(mock_option_params());
// }

// matt:
#[test]
#[available_gas(10000000)]
#[should_panic(
    expected: ('Some error', 'auction has not ended, cannot claim auction_place_bid deposit',)
)]
fn test_refund_unused_bid_deposit_failure_matt() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // add liq
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();
    // get round dispatcher. todo: fetch actual address of round contract once deployed
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: contract_address_const::<'TODO'>()
    };
    // add bid (bid_amount, bid_price)
    set_contract_address(option_bidder_buyer_1());
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;
    round_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);
    round_dispatcher
        .refund_unused_bid_deposit(
            option_bidder_buyer_1()
        ); // should fail as auction has not ended
}

#[test]
#[available_gas(10000000)]
#[should_panic(
    expected: ('Some error', 'auction has not ended, cannot claim auction_place_bid deposit',)
)]
fn test_refund_unused_bid_deposit_failure() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);
    vault_dispatcher
        .refund_unused_bid_deposit(
            option_round_id, option_bidder_buyer_1()
        ); // should fail as auction has not ended
}

// matt:
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'option has not settled, cannot claim payout',))]
fn test_claim_payout_failure_matt() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // add liq
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();
    /// make bid
    set_contract_address(option_bidder_buyer_1());
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;
    // get round dispatcher. todo: fetch actual address of round contract once deployed
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: contract_address_const::<'TODO'>()
    };
    round_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);
    round_dispatcher
        .claim_option_payout(
             option_bidder_buyer_1()
        ); // should fail as option has not settled
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'option has not settled, cannot claim payout',))]
fn test_claim_payout_failure() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);
    vault_dispatcher
        .claim_option_payout(
            option_round_id, option_bidder_buyer_1()
        ); // should fail as option has not settled
}

// matt: why is this test commented out ? 

// #[test]
// #[available_gas(10000000)]
// #[should_panic(expected: ('Some error', 'auction has not ended, cannot claim premium collected',))]
// fn test_claim_premium_failure() {
//     let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

//     set_contract_address(liquidity_provider_1());
//     let deposit_amount_wei = 10000 * decimals();
//     let lp_id : u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);  
//     // start_new_option_round will also starts the auction
//     let (option_round_id, option_params) : (u256, OptionRoundParams) = vault_dispatcher.start_new_option_round();

//     let bid_count: u256 = option_params.total_options_available + 10;
//     let bid_price_user_1 : u256 = option_params.reserve_price;
//     let bid_amount_user_1 : u256 = bid_count * bid_price_user_1;

//     set_contract_address(option_bidder_buyer_1());
//     vault_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1 );
//     vault_dispatcher.transfer_premium_collected_to_vault(liquidity_provider_1()); // should fail as option has not ended
// }

// matt:
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'option has not settled, cannot transfer'))]
fn test_transfer_to_vault_failure_matt() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // add liq
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();
    // get round dispatcher. todo: fetch actual address of round contract once deployed
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: contract_address_const::<'TODO'>()
    };
    // add bid
    set_contract_address(option_bidder_buyer_1());
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;

    round_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();
    set_contract_address(liquidity_provider_1());
    // matt: this stays vault dispatcher ? 
    vault_dispatcher
        .withdraw_liquidity(lp_id, deposit_amount_wei); // should fail as option has not settled
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'option has not settled, cannot transfer'))]
fn test_transfer_to_vault_failure() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1;

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);
    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher
        .withdraw_liquidity(lp_id, deposit_amount_wei); // should fail as option has not settled
}

