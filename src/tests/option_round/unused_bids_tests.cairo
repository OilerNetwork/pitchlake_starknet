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
    option_bidder_buyer_2, option_bidder_buyer_3, accelerate_to_auctioning, accelerate_to_running,
    accelerate_to_settle, accelerate_to_running_custom, option_bidders_get
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
fn test_get_unused_bids_for_ob_during_auction() {
    let (mut vault_facade, _) = setup_facade();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);

    // Make bid
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_amount = bid_count * bid_price;
    round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Check entire bid is 'unused' while still auctioning
    let ob_unused_bid_amount = round_facade.get_unused_bids_for(option_bidder_buyer_1());
    assert(ob_unused_bid_amount == bid_amount, 'unused bids wrong');
}

#[test]
#[available_gas(10000000)]
fn test_unused_bids_for_ob_after_auction() {
    let (mut vault_facade, _) = setup_facade();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);

    let bidders = option_bidders_get(2);
    // OB 2 outbids OB 1 for all the options
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_price_2 = params.reserve_price + 1;
    let bid_amount = bid_count * bid_price;
    let bid_amount_2 = bid_count * bid_price_2;

    accelerate_to_running_custom(
        ref vault_facade, bidders, array![bid_amount, bid_amount_2], array![bid_price, bid_price_2]
    );
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
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);

    let bidders = option_bidders_get(2);

    // OB 2 outbids OB 1 for all the options
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_price_2 = bid_price + 1;
    let bid_amount = bid_count * bid_price;
    let bid_amount_2 = bid_count * bid_price_2;

    accelerate_to_running_custom(
        ref vault_facade, bidders, array![bid_amount, bid_amount_2], array![bid_price, bid_price_2]
    );

    // OB 1 collects their unused bids (at any time post auction)
    let now = starknet::get_block_timestamp();
    set_block_timestamp(now + 10000000000);
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
fn test_collect_unused_bids_again_does_nothing() {
    let (mut vault_facade, eth_dispatcher): (VaultFacade, IERC20Dispatcher) = setup_facade();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);

    let bidders = option_bidders_get(2);
    // OB 2 outbids OB 1 for all the options
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_price_2 = bid_price + 1;
    let bid_amount = bid_count * bid_price;
    let bid_amount_2 = bid_count * bid_price_2;

    accelerate_to_running_custom(
        ref vault_facade, bidders, array![bid_amount, bid_amount_2], array![bid_price, bid_price_2]
    );

    // OB 1 collects their unused bids
    round_facade.refund_bid(option_bidder_buyer_1());
    // OB 1 collects again
    let ob_balance_before_collect = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_facade.refund_bid(option_bidder_buyer_1());
    let ob_balance_after_collect = eth_dispatcher.balance_of(option_bidder_buyer_1());
    // Check OB gets their refunded depost and their amount updates to 0
    assert(ob_balance_before_collect == ob_balance_after_collect, 'balance should not change');
}
// @note Add test for trying to refund bid while still auctioning (all bids locked until post auction, where some may become unlocked if not used)


