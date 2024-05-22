// use array::ArrayTrait;
// use debug::PrintTrait;
// use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher,
    IERC20DispatcherTrait, // IERC20SafeDispatcher,IERC20SafeDispatcherTrait,
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
    option_bidder_buyer_3, decimals, assert_event_transfer, vault_manager, accelerate_to_auctioning,
    accelerate_to_running, accelerate_to_settle, assert_event_vault_transfer,
    assert_event_option_withdraw_payout, clear_event_logs,option_bidders_get, accelerate_to_running_custom
};
use pitch_lake_starknet::tests::mocks::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait
};

// @note If collection fails/is 0, should we fire an event or no ?

// Test that an OB with 0 options gets 0 payout
#[test]
#[available_gas(10000000)]
fn test_user_with_no_options_gets_no_payout() {
    let (mut vault_facade, _) = setup_facade();
    let mut option_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = option_round.get_params();
    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Place the bid and end the auction
    accelerate_to_running(ref vault_facade);
    // Settle option round
    // @dev This ensures the market aggregator returns the mocked current price
    accelerate_to_settle(ref vault_facade, params.strike_price + 5);
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

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Place the bid and end the auction
    accelerate_to_running(ref vault_facade);
    // Settle option round
    // @dev This ensures the market aggregator returns the mocked current price
    accelerate_to_settle(ref vault_facade, params.strike_price + 10);
    // Collect payout
    let ob_balance_before = eth_dispatcher.balance_of(option_bidder_buyer_1());
    let payout = option_round.exercise_options(option_bidder_buyer_1());
    let ob_balance_after = eth_dispatcher.balance_of(option_bidder_buyer_1());
    // Check balance updates
    assert(payout > 0, 'payout shd be > 0');
    assert(ob_balance_after == ob_balance_before + payout, 'payout not received');
    // Check eth transfer to OB
    assert_event_transfer(
        eth_dispatcher.contract_address,
        option_round.contract_address(),
        option_bidder_buyer_1(),
        payout
    );
}

// Test withdrawing payouts emits correct events
#[test]
#[available_gas(10000000)]
fn test_option_payout_events() {
    let (mut vault_facade, _) = setup_facade();
    let mut option_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = option_round.get_params();
    
    // Deposit liquidity and start auction
    accelerate_to_auctioning(ref vault_facade);
    
    // Make bids
    let option_bidders = option_bidders_get(2);
    let bid_amount: u256 = 2;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_amount * bid_price;
    // @note: this test is failing for different reason now because of assert in multiple bids
    accelerate_to_running_custom(ref vault_facade, option_bidders.span(), array![bid_amount, bid_amount].span(), array![bid_price, bid_price].span());
    
    // Settle option round with payout
    let settlement_price = params.strike_price + 10;
    accelerate_to_settle(ref vault_facade, settlement_price);
    
    // Initial balances
    let (lp1_collateral_before, lp1_unallocated_before) = vault_facade
        .get_all_lp_liquidity(option_bidder_buyer_1());
    let (lp2_collateral_before, lp2_unallocated_before) = vault_facade
        .get_all_lp_liquidity(option_bidder_buyer_2());
    let lp1_total_balance_before = lp1_collateral_before + lp1_unallocated_before;
    let lp2_total_balance_before = lp2_collateral_before + lp2_unallocated_before;

    // Collect payout
    clear_event_logs(array![vault_facade.contract_address(), option_round.contract_address()]);
    let payout1 = option_round.exercise_options(option_bidder_buyer_1());
    let payout2 = option_round.exercise_options(option_bidder_buyer_2());

    // Check OptionRound events
    assert_event_option_withdraw_payout(
        option_round.contract_address(), option_bidder_buyer_1(), payout1
    );
    assert_event_option_withdraw_payout(
        option_round.contract_address(), option_bidder_buyer_2(), payout2
    );
    // Check Vault events
    assert_event_vault_transfer(
        vault_facade.contract_address(),
        option_bidder_buyer_1(),
        lp1_total_balance_before,
        lp1_total_balance_before - payout1,
        false
    );
    assert_event_vault_transfer(
        vault_facade.contract_address(),
        option_bidder_buyer_2(),
        lp2_total_balance_before,
        lp2_total_balance_before - payout2,
        false
    );
}


#[test]
#[available_gas(10000000)]
fn test_option_payout_amount_index_higher_than_strike() {
    let (mut vault_facade, _) = setup_facade();
    let mut option_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = option_round.get_params();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Place the bid and end the auction
    accelerate_to_running(ref vault_facade);
    // Settle option round
    // @dev This ensures the market aggregator returns the mocked current price
    let settlement_price = params.strike_price + 11;
    accelerate_to_settle(ref vault_facade, settlement_price);
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

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Place the bid and end the auction
    accelerate_to_running(ref vault_facade);
    // Settle option round
    // @dev This ensures the market aggregator returns the mocked current price
    // @note: if there are no mock values, the strike price here would be zero creating
    //        'u256_sub Overflow'
    let settlement_price = params.strike_price - 10;
    accelerate_to_settle(ref vault_facade, settlement_price);
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

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Place the bid and end the auction
    accelerate_to_running(ref vault_facade);
    // Settle option round
    // @dev This ensures the market aggregator returns the mocked current price
    let settlement_price = params.strike_price;
    accelerate_to_settle(ref vault_facade, settlement_price);

    // Check payout balance is expected
    let payout_balance = option_round.get_payout_balance_for(option_bidder_buyer_1());
    assert(payout_balance == 0, 'expected payout doesnt match');
}


#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot exercise before round settles ', 'ENTRYPOINT_FAILED',))]
fn test_exercise_options_too_early_failure() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let option_params: OptionRoundParams = current_round_facade.get_params();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);
    // Place the bid and end the auction
    accelerate_to_running(ref vault_facade);
    // Should fail as option has not settled
    current_round_facade.exercise_options(option_bidder_buyer_1());
}
// @note Add test that payout is capped even if index >>> strike


