use starknet::testing::{set_block_timestamp, set_contract_address};
use openzeppelin::token::erc20::interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait,};
use pitch_lake_starknet::tests::{
    vault_facade::{VaultFacade, VaultFacadeTrait},
    option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
    utils_new::{
        event_helpers::{
            assert_event_transfer, assert_event_vault_withdrawal, assert_event_options_exercised
        },
        accelerators::{
            accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled,
            accelerate_to_running_custom,
        },
        test_accounts::{
            liquidity_provider_1, option_bidder_buyer_1, option_bidder_buyer_2,
            option_bidder_buyer_3, option_bidders_get
        },
    },
    utils::{setup_facade, decimals, vault_manager, clear_event_logs,},
    mocks::mock_market_aggregator::{
        MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
        IMarketAggregatorSetterDispatcherTrait
    },
};

// @note If collection fails/is 0, should we fire an event or no ?

// Test that an OB with 0 options gets 0 payout
#[test]
#[available_gas(10000000)]
fn test_user_with_no_options_gets_no_payout() {
    let (mut vault_facade, _) = setup_facade();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();
    // Place the bid and end the auction
    accelerate_to_running(ref vault_facade);
    // Settle option round
    // @dev This ensures the market aggregator returns the mocked current price
    accelerate_to_settled(ref vault_facade, params.strike_price + 5);
    // OB 2 tries to claim a payout
    let claimed_payout_amount: u256 = current_round_facade
        .exercise_options(option_bidder_buyer_2());
    assert(
        claimed_payout_amount == 0, 'nothing should be claimed'
    ); // option_bidder_buyer_2 never auction_place_bid in the auction, so should not be able to claim payout
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_sends_eth() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();
    // Place the bid and end the auction
    accelerate_to_running(ref vault_facade);
    // Settle option round
    // @dev This ensures the market aggregator returns the mocked current price
    accelerate_to_settled(ref vault_facade, params.strike_price + 10);
    // Collect payout
    let ob_balance_before = eth_dispatcher.balance_of(option_bidder_buyer_1());
    let payout = current_round_facade.exercise_options(option_bidder_buyer_1());
    let ob_balance_after = eth_dispatcher.balance_of(option_bidder_buyer_1());
    // Check balance updates
    assert(payout > 0, 'payout shd be > 0');
    assert(ob_balance_after == ob_balance_before + payout, 'payout not received');
    // Check eth transfer to OB
    assert_event_transfer(
        eth_dispatcher.contract_address,
        current_round_facade.contract_address(),
        option_bidder_buyer_1(),
        payout
    );
}

// Test withdrawing payouts emits correct events
#[test]
#[available_gas(10000000)]
fn test_option_payout_events() {
    let (mut vault_facade, _) = setup_facade();

    // Deposit liquidity and start auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();

    // Make bids
    let option_bidders = option_bidders_get(2);
    let bid_amount: u256 = 2;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_amount * bid_price;
    // @note: this test is failing for different reason now because of assert in multiple bids
    accelerate_to_running_custom(
        ref vault_facade,
        option_bidders.span(),
        array![bid_amount, bid_amount].span(),
        array![bid_price, bid_price].span()
    );

    // Settle option round with payout
    let settlement_price = params.strike_price + 10;
    accelerate_to_settled(ref vault_facade, settlement_price);
    // Initial balances
    let (lp1_collateral_before, lp1_unallocated_before) = vault_facade
        .get_lp_balance_spread(option_bidder_buyer_1());
    let (lp2_collateral_before, lp2_unallocated_before) = vault_facade
        .get_lp_balance_spread(option_bidder_buyer_2());
    let lp1_total_balance_before = lp1_collateral_before + lp1_unallocated_before;
    let lp2_total_balance_before = lp2_collateral_before + lp2_unallocated_before;

    // Collect payout
    clear_event_logs(
        array![vault_facade.contract_address(), current_round_facade.contract_address()]
    );
    let payout1 = current_round_facade.exercise_options(option_bidder_buyer_1());
    let payout2 = current_round_facade.exercise_options(option_bidder_buyer_2());

    // Check OptionRound events
    assert_event_options_exercised(
        current_round_facade.contract_address(), option_bidder_buyer_1(), bid_amount, payout1
    );
    assert_event_options_exercised(
        current_round_facade.contract_address(), option_bidder_buyer_2(), bid_amount, payout2
    );
}


#[test]
#[available_gas(10000000)]
fn test_option_payout_amount_index_higher_than_strike() {
    let (mut vault_facade, _) = setup_facade();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();
    // Place the bid and end the auction
    accelerate_to_running(ref vault_facade);
    // Settle option round
    // @dev This ensures the market aggregator returns the mocked current price
    let settlement_price = params.strike_price + 11;
    accelerate_to_settled(ref vault_facade, settlement_price);
    // Check payout balance is expected
    let payout_balance = current_round_facade.get_payout_balance_for(option_bidder_buyer_1());
    let payout_balance_expected = current_round_facade.total_options_sold()
        * (settlement_price - params.strike_price);
    assert(payout_balance == payout_balance_expected, 'expected payout doesnt match');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_amount_index_less_than_strike() {
    let (mut vault_facade, _) = setup_facade();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();
    // Place the bid and end the auction
    accelerate_to_running(ref vault_facade);
    // Settle option round
    // @dev This ensures the market aggregator returns the mocked current price
    // @note: if there are no mock values, the strike price here would be zero creating
    //        'u256_sub Overflow'
    let settlement_price = params.strike_price - 10;
    accelerate_to_settled(ref vault_facade, settlement_price);
    // Check payout balance is expected
    let payout_balance = current_round_facade.get_payout_balance_for(option_bidder_buyer_1());
    assert(payout_balance == 0, 'expected payout doesnt match');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_amount_index_at_strike() {
    let (mut vault_facade, _) = setup_facade();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round_facade.get_params();
    // Place the bid and end the auction
    accelerate_to_running(ref vault_facade);
    // Settle option round
    // @dev This ensures the market aggregator returns the mocked current price
    let settlement_price = params.strike_price;
    accelerate_to_settled(ref vault_facade, settlement_price);

    // Check payout balance is expected
    let payout_balance = current_round_facade.get_payout_balance_for(option_bidder_buyer_1());
    assert(payout_balance == 0, 'expected payout doesnt match');
}


#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot exercise before round settles ', 'ENTRYPOINT_FAILED',))]
fn test_exercise_options_too_early_failure() {
    let (mut vault_facade, _) = setup_facade();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Make bids
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let _params = current_round_facade.get_params();
    // Place the bid and end the auction
    accelerate_to_running(ref vault_facade);
    // Should fail as option has not settled
    current_round_facade.exercise_options(option_bidder_buyer_1());
}
// @note Add test that payout is capped even if index >>> strike


