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
    setup_facade, decimals, liquidity_provider_1, option_bidder_buyer_1, option_bidder_buyer_2,
    option_bidder_buyer_3, accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled,
    accelerate_to_running_custom, option_bidders_get, clear_event_logs,
// , deploy_vault, allocated_pool_address, unallocated_pool_address,
// timestamp_start_month, timestamp_end_month, liquidity_provider_2,
// option_bidder_buyer_1, option_bidder_buyer_4
// , option_bidder_buyer_6, vault_manager, weth_owner, mock_option_params,
// month_duration
};

// use result::ResultTrait;
use starknet::testing::{set_block_timestamp, set_contract_address};

use pitch_lake_starknet::tests::{
    utils, vault_facade::{VaultFacade, VaultFacadeTrait},
    option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}
};

// @note Should event emit if collecting 0 ?

// @note use multiple bidders
#[test]
#[available_gas(10000000)]
fn test_get_unused_bids_for_ob_during_auction() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();

    // Make bid
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_amount = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Check entire bid is 'unused' while still auctioning
    let ob_unused_bid_amount = current_round_facade.get_unused_bids_for(option_bidder_buyer_1());
    assert(ob_unused_bid_amount == bid_amount, 'unused bids wrong');
}

#[test]
#[available_gas(10000000)]
fn test_unused_bids_for_ob_after_auction() {
    let (mut vault_facade, _) = setup_facade();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();

    let bidders = option_bidders_get(2);
    // OB 2 outbids OB 1 for all the options
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_price_2 = params.reserve_price + 1;
    let bid_amount = bid_count * bid_price;
    let bid_amount_2 = bid_count * bid_price_2;

    accelerate_to_running_custom(
        ref vault_facade,
        bidders.span(),
        array![bid_amount, bid_amount_2].span(),
        array![bid_price, bid_price_2].span()
    );
    // Check OB 1's unused bid is their entire bid, and OB 2's is 0
    let ob_unused_bid_amount = current_round_facade.get_unused_bids_for(option_bidder_buyer_1());
    let ob_unused_bid_amount_2 = current_round_facade.get_unused_bids_for(option_bidder_buyer_2());
    assert(ob_unused_bid_amount == bid_amount, 'unused bids wrong');
    assert(ob_unused_bid_amount_2 == 0, 'unused bids wrong');
}

#[test]
#[available_gas(10000000)]
fn test_collect_unused_bids_after_auction_end_success() {
    let (mut vault_facade, eth_dispatcher): (VaultFacade, IERC20Dispatcher) = setup_facade();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();

    let bidders = option_bidders_get(2);

    // OB 2 outbids OB 1 for all the options
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_price_2 = bid_price + 1;
    let bid_amount = bid_count * bid_price;
    let bid_amount_2 = bid_count * bid_price_2;

    accelerate_to_running_custom(
        ref vault_facade,
        bidders.span(),
        array![bid_amount, bid_amount_2].span(),
        array![bid_price, bid_price_2].span()
    );

    // OB 1 collects their unused bids (at any time post auction)
    let now = starknet::get_block_timestamp();
    set_block_timestamp(now + 10000000000);
    let unused_amount = current_round_facade.get_unused_bids_for(option_bidder_buyer_1());
    let ob_balance_before_collect = eth_dispatcher.balance_of(option_bidder_buyer_1());
    current_round_facade.refund_bid(option_bidder_buyer_1());
    let ob_balance_after_collect = eth_dispatcher.balance_of(option_bidder_buyer_1());
    // Check OB gets their refunded depost and their amount updates to 0
    assert(ob_balance_before_collect + unused_amount == ob_balance_after_collect, 'refund fail');
    assert(
        current_round_facade.get_unused_bids_for(option_bidder_buyer_1()) == 0,
        'collect amount should be 0'
    );
}


// Test collecting unused bids emits event correctly
#[test]
#[available_gas(10000000)]
fn test_collect_unused_bids_events() {
    let (mut vault_facade, _) = setup_facade();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();

    // OB 2 outbids OB 1 for all the options
    let bidders = option_bidders_get(2);
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_price_2 = params.reserve_price + 1;
    let bid_amount = bid_count * bid_price;
    let bid_amount_2 = bid_count * bid_price_2;

    accelerate_to_running_custom(
        ref vault_facade,
        bidders.span(),
        array![bid_amount, bid_amount_2].span(),
        array![bid_price, bid_price_2].span()
    );
    // Clear event logs
    clear_event_logs(
        array![vault_facade.contract_address(), current_round_facade.contract_address()]
    );
    // Initial balance and collectable amount
    let (lp1_collateral_before, lp1_unallocated_before) = vault_facade
        .get_lp_balance_spread(liquidity_provider_1());
    let lp1_balance_before = lp1_collateral_before + lp1_unallocated_before;
    // OB 1 collects their unused bids
    let collected_amount = current_round_facade.refund_bid(option_bidder_buyer_1());

    // Check OptionRound event

    utils::assert_event_unused_bids_refunded(
        current_round_facade.contract_address(), option_bidder_buyer_1(), bid_amount
    )
}

// Test eth transfer when collecting unused bids
#[test]
#[available_gas(10000000)]
fn test_collect_unused_bids_eth_transfer() {
    let (mut vault_facade, eth) = setup_facade();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();

    // OB 2 outbids OB 1 for all the options
    let bidders = option_bidders_get(2);
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_price_2 = params.reserve_price + 1;
    let bid_amount = bid_count * bid_price;
    let bid_amount_2 = bid_count * bid_price_2;

    accelerate_to_running_custom(
        ref vault_facade,
        bidders.span(),
        array![bid_amount, bid_amount_2].span(),
        array![bid_price, bid_price_2].span()
    );
    // Initial balance
    let lp1_balance_before = eth.balance_of(liquidity_provider_1());
    let round_balance_before = eth.balance_of(current_round_facade.contract_address());
    // OB 1 collects their unused bids
    let collected_amount = current_round_facade.refund_bid(option_bidder_buyer_1());

    // Check eth transfer
    assert(
        eth.balance_of(liquidity_provider_1()) == lp1_balance_before + collected_amount,
        'eth shd go to lp'
    );
    assert(
        eth.balance_of(current_round_facade.contract_address()) == round_balance_before
            - collected_amount,
        'eth come from round'
    );
}

#[test]
#[available_gas(10000000)]
fn test_collect_unused_bids_again_does_nothing() {
    let (mut vault_facade, eth_dispatcher): (VaultFacade, IERC20Dispatcher) = setup_facade();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();

    let bidders = option_bidders_get(2);
    // OB 2 outbids OB 1 for all the options
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_price_2 = bid_price + 1;
    let bid_amount = bid_count * bid_price;
    let bid_amount_2 = bid_count * bid_price_2;

    accelerate_to_running_custom(
        ref vault_facade,
        bidders.span(),
        array![bid_amount, bid_amount_2].span(),
        array![bid_price, bid_price_2].span()
    );

    // OB 1 collects their unused bids
    current_round_facade.refund_bid(option_bidder_buyer_1());
    // OB 1 collects again
    let ob_balance_before_collect = eth_dispatcher.balance_of(option_bidder_buyer_1());
    current_round_facade.refund_bid(option_bidder_buyer_1());
    let ob_balance_after_collect = eth_dispatcher.balance_of(option_bidder_buyer_1());
    // Check OB gets their refunded depost and their amount updates to 0
    assert(ob_balance_before_collect == ob_balance_after_collect, 'balance should not change');
}

// Test that OB cannot refund bids before auction settles
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('The auction is still on-going', 'ENTRYPOINT_FAILED',))]
fn test_option_round_refund_unused_bids_too_early_failure() {
    let (mut vault_facade, _) = setup_facade();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let option_params = current_round_facade.get_params();

    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Try to refund bid before auction settles
    current_round_facade.refund_bid(option_bidder_buyer_1());
}

