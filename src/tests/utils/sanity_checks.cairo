use starknet::{testing::{set_contract_address}};
use openzeppelin::token::erc20::interface::{IERC20DispatcherTrait,};
use pitch_lake_starknet::{
    //vault::{IVaultDispatcherTrait},
    option_round::{IOptionRoundDispatcherTrait},
    tests::{
        utils::{
            accelerators::{
                accelerate_to_auctioning, accelerate_to_running, accelerate_to_running_custom,
                accelerate_to_settled
            },
            setup::{setup_facade}, test_accounts::{option_bidders_get},
            facades::{
                vault_facade::{VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}
            },
            test_accounts::{liquidity_provider_1, liquidity_provider_2}, event_helpers,
        }
    }
};


/// Vault ///

#[test]
#[available_gas(10000000)]
fn test_auction_start_sanity_check() {
    let (mut vault, _) = setup_facade();

    let total_options_available = accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();
    let total_options_available_ = current_round.get_total_options_available();

    assert_gt!(total_options_available, 0);
    assert_eq!(total_options_available, total_options_available_);
}

#[test]
#[available_gas(10000000)]
fn test_auction_end_sanity_check() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);

    let (clearing_price, total_options_sold) = accelerate_to_running(ref vault);
    let mut current_round = vault.get_current_round();

    let clearing_price_ = current_round.get_auction_clearing_price();
    let total_options_sold_ = current_round.total_options_sold();

    assert_gt!(clearing_price, 0);
    assert_gt!(total_options_sold, 0);

    assert_eq!(clearing_price, clearing_price_);
    assert_eq!(total_options_sold, total_options_sold_);
}

#[test]
#[available_gas(10000000)]
fn test_settle_option_round_sanity_check() {
    let (mut vault, _) = setup_facade();

    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    let mut current_round = vault.get_current_round();

    let total_payout = accelerate_to_settled(ref vault, 2 * current_round.get_strike_price());
    let total_payout_ = current_round.total_payout();

    assert_gt!(total_payout, 0);
    assert_eq!(total_payout, total_payout_);
}


/// Option Round ///

#[test]
#[available_gas(10000000)]
fn test_refund_unused_bids_sanity_check() {
    let (mut vault, _) = setup_facade();

    let total_options_available = accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();

    let bidders = option_bidders_get(2);
    let bid_count = total_options_available;
    let bid_price1 = current_round.get_reserve_price();
    let bid_price2 = 2 * bid_price1;
    accelerate_to_running_custom(
        ref vault,
        bidders.span(),
        array![bid_count * bid_price1, bid_count * bid_price2].span(),
        array![bid_price1, bid_price2].span()
    );

    let ob1_bid_balance = current_round.get_unused_bids_for(*bidders[0]);
    let refund_amount = current_round.refund_bid(*bidders[0]);

    assert_gt!(refund_amount, 0);
    assert_eq!(refund_amount, ob1_bid_balance);
}

#[test]
#[available_gas(10000000)]
fn test_exercise_options_sanity_check() {
    let (mut vault, _) = setup_facade();

    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    let mut current_round = vault.get_current_round();
    let total_payout = accelerate_to_settled(ref vault, 2 * current_round.get_strike_price());
    let total_payout_ = current_round.total_payout();

    assert_gt!(total_payout, 0);
    assert_eq!(total_payout, total_payout_);
}


/// Event Checks ///

// Test to make sure the event testers are working as expected
#[test]
#[available_gas(100000000)]
fn test_event_testers() {
    let (mut vault, eth) = setup_facade();
    /// new test, make emission come from entry point on vault,
    let mut round = vault.get_current_round();
    set_contract_address(liquidity_provider_1());
    event_helpers::clear_event_logs(
        array![eth.contract_address, vault.contract_address(), round.contract_address()]
    );
    eth.transfer(liquidity_provider_2(), 100);
    event_helpers::assert_event_transfer(
        eth.contract_address, liquidity_provider_1(), liquidity_provider_2(), 100
    );
    round.option_round_dispatcher.rm_me(100);
    event_helpers::assert_event_auction_start(round.contract_address(), 100);
    event_helpers::assert_event_auction_bid_accepted(
        round.contract_address(), round.contract_address(), 100, 100
    );
    event_helpers::assert_event_auction_bid_rejected(
        round.contract_address(), round.contract_address(), 100, 100
    );
    event_helpers::assert_event_auction_end(round.contract_address(), 100);
    event_helpers::assert_event_option_settle(round.contract_address(), 100);
    event_helpers::assert_event_option_round_deployed(
        vault.contract_address(), 1, vault.contract_address()
    );
    event_helpers::assert_event_vault_deposit(vault.contract_address(), vault.contract_address(), 100, 100);
    event_helpers::assert_event_vault_withdrawal(
        vault.contract_address(), vault.contract_address(), 100, 100
    );
    event_helpers::assert_event_unused_bids_refunded(
        round.contract_address(), round.contract_address(), 100
    );
    event_helpers::assert_event_options_exercised(
        round.contract_address(), round.contract_address(), 100, 100
    );
}
