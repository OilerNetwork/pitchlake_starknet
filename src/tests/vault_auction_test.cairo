

use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;

use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin::token::erc20::interface::{
    IERC20,
    IERC20Dispatcher,
    IERC20DispatcherTrait,
    IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait};
use pitch_lake_starknet::option_round::{IOptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundParams};
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{setup, deployVault, allocated_pool_address, unallocated_pool_address
                                        , timestamp_start_month, timestamp_end_month, liquidity_provider_1, 
                                        liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2,
                                         option_bidder_buyer_3, option_bidder_buyer_4, vault_manager, weth_owner, mock_option_params, month_duration};

use result::ResultTrait;
use starknet::{
    ClassHash,
    ContractAddress,
    contract_address_const,
    deploy_syscall,
    Felt252TryIntoContractAddress,
    get_contract_address,
    get_block_timestamp, testing::{set_block_timestamp, set_contract_address}
};

use starknet::contract_address::ContractAddressZeroable;

use traits::Into;
use traits::TryInto;


#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'auction expired, cannot bid',))]
fn test_bid_after_expiry() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount = 50;
    let option_price = 2 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    set_contract_address(option_bidder_buyer_1());
    set_block_timestamp(option_params.expiry_time + 10 );
    round_dispatcher.bid(option_amount, option_price);

}


#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'multiple parallel rounds not allowed'))]
fn test_multiple_parallel_rounds_failure() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount = 50;
    let option_price = 2 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params = vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);
    // following line should generate an exception
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

}


#[test]
#[available_gas(10000000)]
fn test_current_round_round_is_new_round() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount = 50;
    let option_price = 2 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params = vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);
    let (curr_option_params, curr_round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.current_option_round();
    assert (option_params == curr_option_params, 'current round is new round');

}

#[test]
#[available_gas(10000000)]
fn test_settled_and_new_round_sets_prev_round() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params = vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);
    

    let bid_count: u256 = option_params.total_options_available;
    let bid_price_user_1 : u256 = option_params.reserve_price;

    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, bid_price_user_1 );

    round_dispatcher.end_auction();
    set_block_timestamp(option_params.expiry_time);
    round_dispatcher.settle(option_params.reserve_price + 10, ArrayTrait::new()); 

    let new_option_params : OptionRoundParams = vault_dispatcher.generate_option_round_params(timestamp_end_month(), timestamp_end_month() +  month_duration()  );
    let new_round_dispatcher: IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(new_option_params);
    let (previous_option_params, previous_round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.previous_option_round();
    assert(previous_option_params == option_params, 'curr round = prev round ');
}



#[test]
#[available_gas(10000000)]
fn test_new_round_after_settle() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params = vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);
 
    let bid_count: u256 = option_params.total_options_available;
    let bid_price_user_1 : u256 = option_params.reserve_price;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, bid_price_user_1 );

    round_dispatcher.end_auction();
    set_block_timestamp(option_params.expiry_time);
    round_dispatcher.settle(option_params.reserve_price + 10, ArrayTrait::new()); 

    let new_option_params : OptionRoundParams = vault_dispatcher.generate_option_round_params(timestamp_end_month(), timestamp_end_month() +  month_duration()  );
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(new_option_params);
    // should not throw an exception, TODO better way to check round_dispatcher is valid

}


// #[test]#[available_gas(10000000)]
// fn test_withdrawal_after_premium() {

//     let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
//     let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
//     let option_amount = 50;
//     let option_price = 2 * vault_dispatcher.decimals().into();

//     set_contract_address(liquidity_provider_1());
//     let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    
//     let unallocated_wei_before_premium = vault_dispatcher.total_unallocated_liquidity();
//     // start_new_option_round will also starts the auction
//     let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
        // let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);
//     set_contract_address(option_bidder_buyer_1());
//     round_dispatcher.bid(option_amount, option_params.reserve_price); 
//     round_dispatcher.end_auction();
//     round_dispatcher.settle(option_params.strike_price - 100 , ArrayTrait::new()); // means there is no payout.
//     let unallocated_wei_after_premium = vault_dispatcher.total_unallocated_liquidity();
//     assert(unallocated_wei_before_premium < unallocated_wei_after_premium, 'premium should have paid out');
// }

#[test]
#[available_gas(10000000)]
fn test_clearing_price_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    round_dispatcher.end_auction();
 
    let clearing_price: u256 = round_dispatcher.get_auction_clearing_price();
    assert(clearing_price == option_params.reserve_price, 'clear price equal reserve price');
}

#[test]
#[available_gas(10000000)]
fn test_clearing_price_2() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count: u256 = option_params.total_options_available;
    let bid_price_user_1 : u256 = option_params.reserve_price;
    let bid_price_user_2 : u256 = option_params.reserve_price + 10;

    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, bid_price_user_1 );
    set_contract_address(option_bidder_buyer_2());
    round_dispatcher.bid(bid_count,  bid_price_user_2);

    round_dispatcher.end_auction();
 
    let clearing_price: u256 = round_dispatcher.get_auction_clearing_price();
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
}   

#[test]
#[available_gas(10000000)]
fn test_clearing_price_3() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count_user_1: u256 = option_params.total_options_available - 20;
    let bid_count_user_2: u256 = 20;

    let bid_price_user_1 : u256 = option_params.reserve_price + 100;
    let bid_price_user_2 : u256 = option_params.reserve_price ;

    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count_user_1, bid_price_user_1 );

    set_contract_address(option_bidder_buyer_2());
    round_dispatcher.bid(bid_count_user_2,  bid_price_user_2);

    round_dispatcher.end_auction();
 
    let clearing_price: u256 = round_dispatcher.get_auction_clearing_price();
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
}

#[test]
#[available_gas(10000000)]
fn test_clearing_price_4() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count_user_1: u256 = option_params.total_options_available/ 3;
    let bid_count_user_2: u256 = option_params.total_options_available/ 2;
    let bid_count_user_3: u256 = option_params.total_options_available/ 3;

    let bid_price_user_1 : u256 = option_params.reserve_price + 100;
    let bid_price_user_2 : u256 = option_params.reserve_price + 5 ;
    let bid_price_user_3 : u256 = option_params.reserve_price ;

    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count_user_1, bid_price_user_1 );

    set_contract_address(option_bidder_buyer_2());
    round_dispatcher.bid(bid_count_user_2,  bid_price_user_2);

    set_contract_address(option_bidder_buyer_3());
    round_dispatcher.bid(bid_count_user_3,  bid_price_user_3);

    round_dispatcher.end_auction();
 
    let clearing_price: u256 = round_dispatcher.get_auction_clearing_price();
    assert(clearing_price == bid_price_user_3, 'clear price equal reserve price');
}

#[test]
#[available_gas(10000000)]
fn test_clearing_price_5() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count_user_1: u256 = option_params.total_options_available/ 2;
    let bid_count_user_2: u256 = option_params.total_options_available/ 2;
    let bid_count_user_3: u256 = option_params.total_options_available/ 3;

    let bid_price_user_1 : u256 = option_params.reserve_price + 100;
    let bid_price_user_2 : u256 = option_params.reserve_price + 5 ;
    let bid_price_user_3 : u256 = option_params.reserve_price ;

    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count_user_1, bid_price_user_1 );

    set_contract_address(option_bidder_buyer_2());
    round_dispatcher.bid(bid_count_user_2,  bid_price_user_2);

    set_contract_address(option_bidder_buyer_3());
    round_dispatcher.bid(bid_count_user_3,  bid_price_user_3);

    round_dispatcher.end_auction();
    
    let clearing_price: u256 = round_dispatcher.get_auction_clearing_price();
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
}   


#[test]
#[available_gas(10000000)]
fn test_bid_below_reserve_price() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);

    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);
    // bid below reserve price
    let bid_below_reserve :u256 =  option_params.reserve_price - 1;

    set_contract_address(option_bidder_buyer_1());
    let success = round_dispatcher.bid(2, bid_below_reserve );
    assert(success == false, 'should not be able to bid');
}


#[test]
#[available_gas(10000000)]
fn test_lock_of_bid_funds() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    let wei_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    let wei_balance_after_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());

    assert(wei_balance_before_bid == wei_balance_after_bid + (bid_count * option_params.reserve_price), 'bid amounts should be locked up');
}


#[test]
#[available_gas(10000000)]
fn test_zero_bid_count() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count: u256 = 0;
    set_contract_address(option_bidder_buyer_1());
    let wei_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    let wei_balance_after_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());

    assert(wei_balance_before_bid == wei_balance_after_bid , 'balance should match');
}

#[test]
#[available_gas(10000000)]
fn test_zero_bid_price() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    let wei_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, 0);
    let wei_balance_after_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());

    assert(wei_balance_before_bid == wei_balance_after_bid , 'balance should match');
}

#[test]
#[available_gas(10000000)]
fn test_eth_unused_for_rejected_bids() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());

    let wei_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price - 100);
    let wei_balance_after_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());

    assert(wei_balance_before_bid == wei_balance_after_bid, 'bid should not be locked up');
}

#[test]
#[available_gas(10000000)]
fn test_eth_lockup_for_unused_bids() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count: u256 = option_params.total_options_available + 10;
    set_contract_address(option_bidder_buyer_1());
    let wei_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);

    round_dispatcher.end_auction();
    set_contract_address(option_bidder_buyer_1());
    // round_dispatcher.claim_premium_deposit();
    let wei_balance_after_auction :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    assert(wei_balance_before_bid == wei_balance_after_auction + ((bid_count ) * option_params.reserve_price), 'bid amounts should be locked up');
    assert(bid_count > option_params.total_options_available, 'bid count cannot be > total opt');
}

#[test]
#[available_gas(10000000)]
fn test_eth_transfer_for_unused_bids_after_claim() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count: u256 = option_params.total_options_available + 10;
    set_contract_address(option_bidder_buyer_1());
    let wei_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);

    round_dispatcher.end_auction();
    set_contract_address(option_bidder_buyer_1());

    let wei_balance_before_claim :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    let amount_transferred :u256 = round_dispatcher.claim_premium_deposit();
    let wei_balance_after_claim :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    

    assert(wei_balance_after_claim == wei_balance_before_claim + amount_transferred, 'bid amounts should be locked up');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * vault_dispatcher.decimals().into();
    let success:bool = vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);
    
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(option_params.total_options_available/2 + 1, option_params.reserve_price);

    set_contract_address(option_bidder_buyer_2());
    round_dispatcher.bid(option_params.total_options_available/2, option_params.reserve_price); 
    round_dispatcher.end_auction();

    let options_created_count = round_dispatcher.total_options_sold();
    assert( options_created_count == option_params.total_options_available, 'option shd match up');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_2() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    let deposit_amount_wei = 10000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);
    let bid_amount_user_1 :u256 =  (option_params.total_options_available/2) + 1;
    let bid_amount_user_2 :u256 =  (option_params.total_options_available/2) ;
    
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_amount_user_1, option_params.reserve_price);

    set_contract_address(option_bidder_buyer_2());
    round_dispatcher.bid(bid_amount_user_2, option_params.reserve_price - 10); 
    round_dispatcher.end_auction();

    let options_created_count = round_dispatcher.total_options_sold();
    assert( options_created_count == bid_amount_user_1, 'options shd match');
}


#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_3() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    round_dispatcher.end_auction();
 
    let options_created = round_dispatcher.total_options_sold();
    assert(options_created == bid_count, 'options equal successful bids');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_4() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price - 1);
    round_dispatcher.end_auction();
 
    let options_created = round_dispatcher.total_options_sold();
    assert(options_created == 0, 'options equal successful bids');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_5() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count: u256 = option_params.total_options_available + 10;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    round_dispatcher.end_auction();
 
    let options_created = round_dispatcher.total_options_sold();
    assert(options_created == option_params.total_options_available, 'options equal successful bids');
}




