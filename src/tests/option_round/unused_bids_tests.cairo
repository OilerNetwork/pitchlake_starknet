// use array::ArrayTrait;
// use debug::PrintTrait;
// use option::OptionTrait;

// use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

// use pitch_lake_starknet::vault::{
//     IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait
// };
// use pitch_lake_starknet::option_round::{OptionRoundParams};
// use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{
    setup_facade, decimals, liquidity_provider_1, option_bidder_buyer_1, assert_event_auction_bid,
    option_bidder_buyer_2, option_bidder_buyer_3
// , deploy_vault, allocated_pool_address, unallocated_pool_address,
// timestamp_start_month, timestamp_end_month, liquidity_provider_2,
// option_bidder_buyer_1, option_bidder_buyer_4
// , option_bidder_buyer_6, vault_manager, weth_owner, mock_option_params,
// month_duration
};
use pitch_lake_starknet::option_round::{OptionRoundParams};

// use result::ResultTrait;
use starknet::testing::{set_block_timestamp, set_contract_address};

use pitch_lake_starknet::tests::{
    vault_facade::{VaultFacade, VaultFacadeTrait},
    option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}
};
// use starknet::contract_address::ContractAddressZeroable;

// use traits::Into;
// use traits::TryInto;



#[test]
#[available_gas(10000000)]
fn test_unused_bids_for_ob_while_auctioning() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Make bid
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_amount = bid_count * bid_price;
    round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Check entire bid is 'unused' while still auctioning
    let ob_unused_bid_amount = round_facade.get_unused_bids_for(option_bidder_buyer_1());
    assert(ob_unused_bid_amount == bid_amount, 'unused bids wrong');
}

///////////////////// tests below are based on auction_reference_size_is_max_amount.py results/////////////////////////
#[test]
#[available_gas(10000000)]
fn test_unused_bids_for_ob_after_auctioning() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // OB 2 outbids OB 1 for all the options
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_price_2 = bid_price + 1;
    let bid_amount = bid_count * bid_price;
    let bid_amount_2 = bid_count * bid_price_2;

    round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    round_facade.place_bid(bid_amount_2, bid_price_2, option_bidder_buyer_2());
    // Settle auction
    vault_facade.timeskip_and_end_auction();
    // Check OB 1's unused bid is their entire bid, and OB 2's is 0
    let ob_unused_bid_amount = round_facade.get_unused_bids_for(option_bidder_buyer_1());
    let ob_unused_bid_amount_2 = round_facade.get_unused_bids_for(option_bidder_buyer_2());
    assert(ob_unused_bid_amount == bid_amount, 'unused bids wrong');
    assert(ob_unused_bid_amount_2 == 0, 'unused bids wrong');
}

#[test]
#[available_gas(10000000)]
fn test_collect_unused_bids_after_auction_end_success() {
    let (mut vault_facade, eth_dispatcher): (VaultFacade, IERC20Dispatcher) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();

    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // OB 2 outbids OB 1 for all the options
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_price_2 = bid_price + 1;
    let bid_amount = bid_count * bid_price;
    let bid_amount_2 = bid_count * bid_price_2;

    round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());

    round_facade.place_bid(bid_amount_2, bid_price_2, option_bidder_buyer_2());
    // Settle auction
    vault_facade.timeskip_and_end_auction();
    // OB 1 collects their unused bids
    let unused_amount = round_facade.get_unused_bids_for(option_bidder_buyer_1());
    let ob_balance_before_collect = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_facade.refund_bid(option_bidder_buyer_1());
    let ob_balance_after_collect = eth_dispatcher.balance_of(option_bidder_buyer_1());
    // Check OB gets their refunded depost and their amount updates to 0
    assert(ob_balance_before_collect + unused_amount == ob_balance_after_collect, 'refund fail');
    assert(
        round_facade.get_unused_bids_for(option_bidder_buyer_1()) == 0, 'collect amount should be 0'
    );
}




#[test]
#[available_gas(10000000)]
fn test_collect_unused_bids_none_left() {
    let (mut vault_facade, eth_dispatcher): (VaultFacade, IERC20Dispatcher) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // OB 2 outbids OB 1 for all the options
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_price_2 = bid_price + 1;
    let bid_amount = bid_count * bid_price;
    let bid_amount_2 = bid_count * bid_price_2;
    round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    round_facade.place_bid(bid_amount_2, bid_price_2, option_bidder_buyer_2());
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    vault_facade.timeskip_and_end_auction();
    // OB 1 collects their unused bids
    round_facade.refund_bid(option_bidder_buyer_1());
    // OB 1 collects again
    let ob_balance_before_collect = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_facade.refund_bid(option_bidder_buyer_1());
    let ob_balance_after_collect = eth_dispatcher.balance_of(option_bidder_buyer_1());
    // Check OB gets their refunded depost and their amount updates to 0
    assert(ob_balance_before_collect == ob_balance_after_collect, 'balance should not change');
}
