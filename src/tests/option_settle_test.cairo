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
use pitch_lake_starknet::tests::utils::{
    setup, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    vault_manager, weth_owner, mock_option_params
};
use pitch_lake_starknet::tests::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait
};
use pitch_lake_starknet::option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};

// q:
// allocated is the total funds currently in a round that are locked and waiting for the end of the round
// unallocated is the total funds currently in a round that are not locked and can be withdrawn until the round starts
// is it needed anymore ?

/// matt: why is this commented out ? 
// #[test]
// #[available_gas(10000000)]
// fn test_invalid_user_collection_of_premium_after_settle() {

//     let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
//     let deposit_amount_wei:u256 = 50 * decimals();
//     let option_amount : u256 = 50;
//     let option_price : u256 = 2 * decimals();

//     set_contract_address(liquidity_provider_1());
//     let lp_id:u256  = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

//     let unallocated_wei_before_premium: u256 = vault_dispatcher.total_unallocated_liquidity();
//     // start_new_option_round will also starts the auction
//     let (option_round_id, option_params) : (u256, OptionRoundParams) = vault_dispatcher.start_new_option_round();
//     set_contract_address(option_bidder_buyer_1());

//     let bid_amount : u256 = option_amount * option_price;
//     vault_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price); 
//     set_block_timestamp(option_params.auction_end_time + 1);
//     vault_dispatcher.settle_auction();

//     set_block_timestamp(option_params.option_expiry_time + 1);
//     // following makes sure the market aggregator returns the mocked current price
//     let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher = IMarketAggregatorSetterDispatcher{contract_address:vault_dispatcher.get_market_aggregator().contract_address};
//     mock_maket_aggregator_setter.set_current_base_fee(option_params.strike_price - 100); // means there is no payout. TODO confirm this is correct that there will be no payout if settle_option_round price is less than strike price?

//     vault_dispatcher.settle_option_round(); 
//     vault_dispatcher.claim_option_payout(option_round_id, option_bidder_buyer_1());

//     let claimed_premium_amount :u256 = vault_dispatcher.transfer_premium_collected_to_vault(liquidity_provider_2()); 
//     assert(claimed_premium_amount == 0, 'nothing should be claimed'); // since this user did not provider any liquidity initially, should not be able to collect premium 
// }

#[test]
#[available_gas(10000000)]
fn test_invalid_user_collection_of_payout_after_settle() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 50
        * decimals(); // matt changes all the vault_dispatcher.decimals().into() to decimals()
    let option_amount: u256 = 50;
    let option_price: u256 = 2 * decimals();

    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    let unallocated_wei_before_premium: u256 = vault_dispatcher.total_unallocated_liquidity();
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Make bid
    set_contract_address(option_bidder_buyer_1());
    let bid_amount: u256 = option_amount * option_price;
    round_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price);
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();

    // Settle option round
    set_block_timestamp(option_params.option_expiry_time + 1);
    // following makes sure the market aggregator returns the mocked current price
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: vault_dispatcher.get_market_aggregator().contract_address
    };
    mock_maket_aggregator_setter.set_current_base_fee(option_params.strike_price + 5);
    round_dispatcher.settle_option_round();

    let claimed_payout_amount: u256 = round_dispatcher.claim_option_payout(option_bidder_buyer_2());
    assert(
        claimed_payout_amount == 0, 'nothing should be claimed'
    ); // option_bidder_buyer_2 never auction_place_bid in the auction, so should not be able to claim payout
}

#[test]
#[available_gas(10000000)]
fn test_collection_of_premium_after_settle() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 50 * decimals();
    let option_amount: u256 = 50;
    let option_price: u256 = 2 * decimals();

    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    let unallocated_wei_before_premium: u256 = vault_dispatcher.total_unallocated_liquidity();
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Make bid and settle auction
    set_contract_address(option_bidder_buyer_1());
    let bid_amount: u256 = option_amount * option_price;
    round_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price);
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();

    // Settle option round
    set_block_timestamp(option_params.option_expiry_time + 1);
    // following makes sure the market aggregator returns the mocked current price
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: vault_dispatcher.get_market_aggregator().contract_address
    };
    mock_maket_aggregator_setter
        .set_current_base_fee(
            option_params.strike_price - 100
        ); // means there is no payout. TODO confirm this is correct that there will be no payout if settle_option_round price is less than strike price?
    round_dispatcher.settle_option_round();

    // Claim payout
    let claimed_payout_amount: u256 = round_dispatcher.claim_option_payout(option_bidder_buyer_1());

    let claimable_premium_amount: u256 = round_dispatcher
        .premium_balance_of(
            liquidity_provider_1()
        ); // this will collect the premium back into unallocated_pool in the vault   
    let unallocated_wei_after_premium: u256 = vault_dispatcher.total_unallocated_liquidity();

    assert(
        claimable_premium_amount == round_dispatcher.total_options_sold()
            * round_dispatcher.get_auction_clearing_price(),
        'premium amount shd match'
    );
    assert(
        claimed_payout_amount == 0, 'nothing should be claimed'
    ); // since there is no payout because settle_option_round price was lower than strike price
    assert(
        unallocated_wei_before_premium < unallocated_wei_after_premium,
        'premium should have paid out'
    );
}

/// matt: why is this commented out ? 
#[test]
#[available_gas(10000000)]
// fn test_failure_collection_of_multiple_premium_after_settle() {

//     let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
//     let deposit_amount_wei:u256 = 50 * decimals();
//     let option_amount : u256 = 50;

//     set_contract_address(liquidity_provider_1());
//     let lp_id:u256  = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

//     let unallocated_wei_before_premium = vault_dispatcher.total_unallocated_liquidity();
//     // start_new_option_round will also starts the auction
//     let (option_round_id, option_params) : (u256, OptionRoundParams) = vault_dispatcher.start_new_option_round();
//     set_contract_address(option_bidder_buyer_1());

//     let bid_amount : u256 = option_amount * option_params.reserve_price;
//     vault_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price); 
//     set_block_timestamp(option_params.auction_end_time + 1);
//     vault_dispatcher.settle_auction();

//     set_block_timestamp(option_params.option_expiry_time + 1);
//     // following makes sure the market aggregator returns the mocked current price
//     let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher = IMarketAggregatorSetterDispatcher{contract_address:vault_dispatcher.get_market_aggregator().contract_address};
//     mock_maket_aggregator_setter.set_current_base_fee(option_params.strike_price - 100);    // means there is no payout. TODO confirm this is correct that there will be no payout if settle_option_round price is less than strike price?
//     vault_dispatcher.settle_option_round(); 
//     let claimed_payout_amount :u256 = vault_dispatcher.claim_option_payout(option_round_id, option_bidder_buyer_1()); 

//     let claimed_premium_amount: u256 = vault_dispatcher.transfer_premium_collected_to_vault(liquidity_provider_1()); // this will collect the premium back into unallocated_pool in the vault   
//     assert(claimed_premium_amount == vault_dispatcher.total_options_sold() * vault_dispatcher.get_auction_clearing_price(option_round_id) , 'premium amount shd match');

//     let claimed_premium_amount_attempt_2: u256 = vault_dispatcher.transfer_premium_collected_to_vault(liquidity_provider_1()); // this will collect the premium back into unallocated_pool in the vault   
//     assert(claimed_premium_amount_attempt_2 == 0 , 'should not claim twice');
// }

#[test]
#[available_gas(10000000)]
fn test_option_payout_1() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Make bid
    let bid_count: u256 = 2;
    let bid_amount: u256 = bid_count * option_params.reserve_price;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price);
    // Settle auction
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();

    // Settle round
    let settlement_price: u256 = option_params.strike_price + 10;
    set_block_timestamp(option_params.option_expiry_time + 1);
    // following makes sure the market aggregator returns the mocked current price
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: vault_dispatcher.get_market_aggregator().contract_address
    };
    mock_maket_aggregator_setter.set_current_base_fee(settlement_price);
    round_dispatcher.settle_option_round();

    // Payout balance
    let payout_balance = round_dispatcher.payout_balance_of(option_bidder_buyer_1());
    let payout_balance_expected = round_dispatcher.option_balance_of(option_bidder_buyer_1())
        * (settlement_price
            - option_params.strike_price); // TODO convert this to gwei instead of wei
    assert(payout_balance == payout_balance_expected, 'expected payout doesnt match');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_2() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Make bid and settle auction
    let bid_count: u256 = 2;
    let bid_amount: u256 = bid_count * option_params.reserve_price;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price);
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();

    // Settle round
    let settlement_price: u256 = option_params.strike_price - 10;
    set_block_timestamp(option_params.option_expiry_time + 1);
    // following makes sure the market aggregator returns the mocked current price
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: vault_dispatcher.get_market_aggregator().contract_address
    };
    mock_maket_aggregator_setter.set_current_base_fee(settlement_price);
    round_dispatcher.settle_option_round();

    let payout_balance = round_dispatcher.payout_balance_of(option_bidder_buyer_1());
    let payout_balance_expected =
        0; // payout is zero because the settlement price is below the strike price
    assert(payout_balance == payout_balance_expected, 'expected payout doesnt match');
}


//
#[test]
#[available_gas(10000000)]
fn test_option_post_payout_collaterized_count_1() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Make bid and settle auction
    let bid_count: u256 = 2;
    let bid_amount: u256 = bid_count * option_params.reserve_price;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price);
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();
    // Settle round
    let settlement_price: u256 = option_params.cap_level;
    set_block_timestamp(option_params.option_expiry_time + 1);
    // following makes sure the market aggregator returns the mocked current price
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: vault_dispatcher.get_market_aggregator().contract_address
    };
    mock_maket_aggregator_setter.set_current_base_fee(settlement_price);

    round_dispatcher.settle_option_round();

    set_contract_address(option_bidder_buyer_1());
    let claimed_payout: u256 = round_dispatcher.claim_option_payout(option_bidder_buyer_1());

    let total_collaterized_count_after_payout_claimed: u256 = round_dispatcher
        .total_collateral(); // vault. ? 
    assert(
        total_collaterized_count_after_payout_claimed == deposit_amount_wei - claimed_payout,
        'collaterized should match'
    )
}


#[test]
#[available_gas(10000000)]
fn test_option_post_payout_collaterized_count_2() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Make bid and settle auction
    let bid_count: u256 = 2;
    let bid_amount: u256 = bid_count * option_params.reserve_price;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price);
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();
    // Settle round
    let settlement_price: u256 = option_params.cap_level;
    set_block_timestamp(option_params.option_expiry_time + 1);
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: vault_dispatcher.get_market_aggregator().contract_address
    };
    mock_maket_aggregator_setter.set_current_base_fee(settlement_price);
    round_dispatcher.settle_option_round();

    let claimed_payout: u256 = round_dispatcher.claim_option_payout(option_bidder_buyer_1());
    // let transferred_collateral :u256 = vault_dispatcher.transfer_collateral_to_vault(liquidity_provider_1());
    let total_collaterized_count_post_transfer: u256 = round_dispatcher
        .total_collateral(); //vault. ? 
    assert(total_collaterized_count_post_transfer == 0, 'collaterized should be zero')
// matt: because strike price = settlement price? what exactly is the collateral ? where is it from Lp or bids ? 
}

// here

#[test]
#[available_gas(10000000)]
fn test_option_post_payout_collaterized_count_3() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Make bid and settle auction
    let total_collaterized_count_before_auction: u256 = round_dispatcher.total_collateral();
    let bid_count: u256 = 2;
    let bid_amount: u256 = bid_count * option_params.reserve_price;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price);
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();
    // Settle round
    let settlement_price: u256 = option_params.strike_price + 10;
    set_block_timestamp(option_params.option_expiry_time + 1);
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: vault_dispatcher.get_market_aggregator().contract_address
    };
    mock_maket_aggregator_setter.set_current_base_fee(settlement_price);
    round_dispatcher.settle_option_round();

    let premium_paid: u256 = bid_amount;
    let total_collaterized_count_after_settle: u256 = vault_dispatcher
        .total_unallocated_liquidity();
    let claim_payout_amount: u256 = round_dispatcher.payout_balance_of(option_bidder_buyer_1());

    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.claim_option_payout(option_bidder_buyer_1());

    set_contract_address(liquidity_provider_1());

    // These 2 lines were commented out, why ?
    // > needs to be called on round_dispatcher, not vault
    // vault_dispatcher.transfer_premium_collected_to_vault(liquidity_provider_1());
    // vault_dispatcher.transfer_collateral_to_vault(liquidity_provider_1());

    let total_collaterized_count_after_claim: u256 = round_dispatcher.total_collateral();

    assert(
        total_collaterized_count_after_settle == total_collaterized_count_before_auction
            - claim_payout_amount
            + premium_paid,
        'expec collaterized doesnt match'
    );
// matt: yea, confused what collateral really means 
}


#[test]
#[available_gas(10000000)]
fn test_option_payout_buyer_eth_balance() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Make bid and settle auction
    let bid_count: u256 = 2;
    let bid_amount: u256 = bid_count * option_params.reserve_price;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price);
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();

    // Settle round
    let settlement_price: u256 = option_params.strike_price + 10;
    set_block_timestamp(option_params.option_expiry_time + 1);
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: vault_dispatcher.get_market_aggregator().contract_address
    };
    mock_maket_aggregator_setter
        .set_current_base_fee(
            settlement_price
        ); //TODO based on averages, TWAP an also pass in time.

    round_dispatcher.settle_option_round();

    let payout_balance: u256 = round_dispatcher.payout_balance_of(option_bidder_buyer_1());
    let balance_before_claim: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());

    round_dispatcher.claim_option_payout(option_bidder_buyer_1());
    let balance_after_claim: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    assert(
        balance_after_claim == payout_balance + balance_before_claim, 'expected payout doesnt match'
    );
}

