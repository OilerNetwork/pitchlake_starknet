use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20,
    IERC20Dispatcher,
    IERC20DispatcherTrait,
    IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait};
use pitch_lake_starknet::option_round::{IOptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundParams};

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
use openzeppelin::utils::serde::SerializedAppend;

use traits::Into;
use traits::TryInto;
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{setup, deployVault, allocated_pool_address, unallocated_pool_address
                                        , timestamp_start_month, timestamp_end_month, liquidity_provider_1, 
                                        liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2,
                                         option_bidder_buyer_3, option_bidder_buyer_4, vault_manager, weth_owner, mock_option_params};



#[test]#[available_gas(10000000)]
fn test_withdrawal_after_settle() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount = 50;
    let option_price = 2 * vault_dispatcher.decimals().into();

    set_contract_address(liquidity_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    
    let unallocated_wei_before_premium = vault_dispatcher.total_unallocated_liquidity();
    // start_new_option_round will also starts the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(mock_option_params());
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(option_amount, option_params.reserve_price); 
    round_dispatcher.end_auction();

    set_block_timestamp(option_params.expiry_time);
    round_dispatcher.settle(option_params.strike_price - 100 , ArrayTrait::new()); // means there is no payout.
    let unallocated_wei_after_premium:u256 = vault_dispatcher.total_unallocated_liquidity();
    assert(unallocated_wei_before_premium < unallocated_wei_after_premium, 'premium should have paid out');
}

#[test]
#[available_gas(10000000)]
fn test_settle_before_expiry() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount = 50;
    let option_price = 2 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(mock_option_params());

    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(option_amount, option_price);
    round_dispatcher.end_auction();

    set_block_timestamp(option_params.expiry_time - 10000);
    let success = round_dispatcher.settle(option_params.strike_price + 10, ArrayTrait::new()) ;

    assert(success == false, 'no settle before expiry');
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected : ('some error','no settle before auction end'))]
fn test_settle_before_end_auction() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount:u256 = 50;
    let option_price:u256 = 2 * vault_dispatcher.decimals().into();
    let final_settlement_price:u256 = 30 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(mock_option_params());

    set_contract_address(option_bidder_buyer_1());
    set_block_timestamp(option_params.expiry_time );
    let success = round_dispatcher.settle(final_settlement_price, ArrayTrait::new());

    assert(success == false, 'no settle before auction end');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(mock_option_params());

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    round_dispatcher.end_auction();

    let settlement_price :u256 =  option_params.strike_price + 10;
    set_block_timestamp(option_params.expiry_time);
    round_dispatcher.settle(settlement_price, ArrayTrait::new());

    let payout_balance = round_dispatcher.payout_balance_of(option_bidder_buyer_1());
    let payout_balance_expected = round_dispatcher.option_balance_of(option_bidder_buyer_1()) * (settlement_price - option_params.strike_price);
    assert(payout_balance == payout_balance_expected, 'expected payout doesnt match');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_2() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(mock_option_params());

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    round_dispatcher.end_auction();

    let settlement_price :u256 =  option_params.strike_price - 10;
    set_block_timestamp(option_params.expiry_time);
    round_dispatcher.settle(settlement_price, ArrayTrait::new());

    let payout_balance = round_dispatcher.payout_balance_of(option_bidder_buyer_1());
    let payout_balance_expected = 0; // payout is zero because the settlement price is below the strike price
    assert(payout_balance == payout_balance_expected, 'expected payout doesnt match');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_claim_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(mock_option_params());

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    round_dispatcher.end_auction();

    let settlement_price :u256 =  option_params.strike_price + 10;
    set_block_timestamp(option_params.expiry_time);
    round_dispatcher.settle(settlement_price, ArrayTrait::new());

    let payout_balance : u256= round_dispatcher.payout_balance_of(option_bidder_buyer_1());
    let balance_before_claim:u256 = eth_dispatcher.balance_of(option_bidder_buyer_1()); 

    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.claim_payout();
    let balance_after_claim:u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    assert(balance_after_claim == payout_balance + balance_before_claim, 'expected payout doesnt match');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_collaterized_count() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(mock_option_params());

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    round_dispatcher.end_auction();

    let settlement_price :u256 =  option_params.cap_level;
    set_block_timestamp(option_params.expiry_time);
    round_dispatcher.settle(settlement_price, ArrayTrait::new());

    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.claim_payout();

    let total_collaterized_count_after_settle : u256= round_dispatcher.total_collateral();
    assert(total_collaterized_count_after_settle == 0, 'collaterized should be zero')
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_unallocated_count_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(mock_option_params());
    let total_collaterized_count_before_auction : u256= vault_dispatcher.total_unallocated_liquidity();

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    round_dispatcher.end_auction();

    let settlement_price :u256 =  option_params.strike_price + 10;
    set_block_timestamp(option_params.expiry_time);
    round_dispatcher.settle(settlement_price, ArrayTrait::new());

    let premium_paid: u256 = (bid_count*  option_params.reserve_price);
    let total_collaterized_count_after_settle : u256= vault_dispatcher.total_unallocated_liquidity();
    let claim_payout_amount:u256 = round_dispatcher.payout_balance_of(option_bidder_buyer_1()); 

    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.claim_payout();

    set_contract_address(liquidity_provider_1());
    round_dispatcher.transfer_premium_paid_to_vault();
    round_dispatcher.transfer_collateral_to_vault();

    let total_collaterized_count_after_claim : u256= round_dispatcher.total_collateral();
    assert(total_collaterized_count_after_settle == total_collaterized_count_before_auction - claim_payout_amount + premium_paid, 'expec collaterized doesnt match');
}
