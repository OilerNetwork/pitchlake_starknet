use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use openzeppelin::{
    token::erc20::interface::{
        IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
        IERC20SafeDispatcherTrait,
    },
};
use pitch_lake_starknet::{
    eth::Eth,
    vault::{
        IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault,
        IVaultSafeDispatcherTrait
    },
    option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait},
    tests::{
        vault_facade::{VaultFacade, VaultFacadeTrait},
        option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
        mocks::mock_market_aggregator::{
            MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
            IMarketAggregatorSetterDispatcherTrait
        },
        utils_new::{
            event_helpers::{
                assert_event_transfer, assert_event_auction_bid_accepted,
                assert_event_auction_bid_rejected, pop_log, assert_no_events_left,
            },
            accelerators::{accelerate_to_auctioning},
            test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                option_bidders_get,
            }
        },
        utils::{setup_facade, decimals, deploy_vault, clear_event_logs,},
    },
};
use debug::PrintTrait;

// @note should just assert x = next_round.place_bid(...) == false
// Test OB cannot bid before the auction starts
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot bid before auction starts', 'ENTRYPOINT_FAILED'))]
fn test_bid_before_auction_starts_failure() {
    let (mut vault_facade, _) = setup_facade();

    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();
    // Clear event logs for bids
    clear_event_logs(array![current_round_facade.contract_address()]);

    // Try to place bid before auction starts
    let option_amount: u256 = params.total_options_available;
    let option_price: u256 = params.reserve_price;
    let bid_amount: u256 = option_amount * option_price;
    current_round_facade.place_bid(bid_amount, option_price, option_bidder_buyer_1());

    // Check bid rejected event
    assert_event_auction_bid_rejected(
        current_round_facade.contract_address(), option_bidder_buyer_1(), bid_amount, option_price
    );
}

// Test OB cannot bid after the auction ends
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Auction over, cannot place bid', 'ENTRYPOINT_FAILED',))]
fn test_bid_after_auction_ends_failure() {
    // Add liq. to next round
    let (mut vault_facade, _) = setup_facade();
    let _deposit_amount_wei = 50 * decimals();

    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();
    // End the auction
    vault_facade.timeskip_and_end_auction();
    // Clear event logs for bids
    clear_event_logs(array![current_round_facade.contract_address()]);

    // Place bid after auction end
    set_block_timestamp(params.auction_end_time + 1);
    let option_amount = params.total_options_available;
    let option_price = params.reserve_price;
    let bid_amount = option_amount * option_price;
    current_round_facade.place_bid(bid_amount, option_price, option_bidder_buyer_1());

    // Check bid rejected event
    assert_event_auction_bid_rejected(
        current_round_facade.contract_address(), option_bidder_buyer_1(), bid_amount, option_price
    );
}

// Test OB cannot bid after the auction end date (if .end_auction() not called first)
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Auction over, cannot place bid', 'ENTRYPOINT_FAILED',))]
fn test_bid_after_auction_end_failure_2() {
    // Add liq. to next round
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();
    // Jump to after auction end time, but beat the call that ends the round's auction
    set_block_timestamp(params.auction_end_time + 1);
    // Clear event logs for bids
    clear_event_logs(array![current_round_facade.contract_address()]);

    // Place bid after auction end date
    let option_amount = params.total_options_available;
    let option_price = params.reserve_price;
    let bid_amount = option_amount * option_price;
    current_round_facade.place_bid(bid_amount, option_price, option_bidder_buyer_1());

    // Check bid rejected event
    assert_event_auction_bid_rejected(
        current_round_facade.contract_address(), option_bidder_buyer_1(), bid_amount, option_price,
    );
}

// Test eth transfers from bidder to round when bid is placed
#[test]
#[available_gas(10000000)]
fn test_bid_eth_transfer() {
    let (mut vault_facade, eth_dispatcher): (VaultFacade, IERC20Dispatcher) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);

    // Eth balances before bid
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let ob_balance_init = eth_dispatcher.balance_of(option_bidder_buyer_1());
    let round_balance_init = eth_dispatcher.balance_of(current_round.contract_address());

    // Make bid
    let params = current_round.get_params();
    let bid_count = 2;
    let bid_price = params.reserve_price;
    let bid_amount = bid_count * bid_count;
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());

    // Eth balances after bid
    let ob_balance_final: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    let round_balance_final: u256 = eth_dispatcher.balance_of(current_round.contract_address());

    // Check bids went from OB to round
    assert(ob_balance_final == ob_balance_init - bid_amount, 'bid did not leave obs account');
    assert(round_balance_final == round_balance_init + bid_amount, 'bid did not reach round');
}

// Test bid accepted events
#[test]
#[available_gas(10000000)]
fn test_bid_accepted_events() {
    let (mut vault_facade, _): (VaultFacade, IERC20Dispatcher) = setup_facade();
    // Deposit liquidity, start auction, and place bid
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();
    // Clear event logs for eth transfers and bids
    clear_event_logs(array![current_round_facade.contract_address()]);

    let mut obs = option_bidders_get(5);
    let mut step = 1;
    loop {
        match obs.pop_front() {
            Option::Some(ob) => {
                // Place bid
                let bid_count = step;
                let bid_price = params.reserve_price + step;
                let bid_amount = bid_count * bid_price;
                current_round_facade.place_bid(bid_amount, bid_price, ob);

                // Check bid accepted event
                assert_event_auction_bid_accepted(
                    current_round_facade.contract_address(),
                    option_bidder_buyer_1(),
                    bid_amount,
                    bid_price,
                );

                step += 1;
            },
            Option::None => { break; }
        };
    };
}

// Test bidding 0 is rejected
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Bid price must be >= reserve price', 'ENTRYPOINT_FAILED',))]
fn test_bid_zero_amount_failure() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();

    // Clear event logs for bids
    clear_event_logs(array![current_round_facade.contract_address()]);

    // Try to bid 0 amount
    current_round_facade.place_bid(0, params.reserve_price, option_bidder_buyer_1());

    // Check bid rejected event
    assert_event_auction_bid_rejected(
        current_round_facade.contract_address(), option_bidder_buyer_1(), 0, params.reserve_price
    );
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Bid price must be >= reserve price', 'ENTRYPOINT_FAILED',))]
fn test_bid_price_below_reserve_price_failure() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();

    // Clear event logs for bids
    clear_event_logs(array![current_round_facade.contract_address()]);

    // Try to bid below reserve price
    current_round_facade
        .place_bid(
            2 * (params.reserve_price - 1), params.reserve_price - 1, option_bidder_buyer_1()
        );

    // Check bid rejected event
    assert_event_auction_bid_rejected(
        current_round_facade.contract_address(),
        option_bidder_buyer_1(),
        2 * (params.reserve_price - 1),
        params.reserve_price - 1,
    );
}

