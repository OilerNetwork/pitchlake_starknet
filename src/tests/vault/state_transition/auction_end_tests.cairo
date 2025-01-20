use core::array::SpanTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use openzeppelin_token::erc20::interface::{ERC20ABIDispatcherTrait,};
use pitch_lake::{
    library::eth::Eth,
    vault::{
        contract::Vault,
        interface::{
            IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, IVaultSafeDispatcherTrait
        },
    },
    option_round::{
        interface::{OptionRoundState, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,},
    },
    option_round::contract::OptionRound::Errors,
    tests::{
        utils::{
            helpers::{
                event_helpers::{
                    pop_log, assert_no_events_left, assert_event_auction_end, clear_event_logs
                },
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running,
                    accelerate_to_auctioning_custom, accelerate_to_running_custom,
                    accelerate_to_settled, timeskip_past_round_transition_period,
                    timeskip_and_end_auction,
                },
                general_helpers::{
                    create_array_gradient, create_array_linear, sum_u256_array,
                    get_portion_of_amount, span_to_array,
                },
                setup::{setup_facade, setup_test_auctioning_providers, setup_test_running},
            },
            lib::{
                test_accounts::{
                    liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                    option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                    liquidity_providers_get, option_bidders_get, liquidity_provider_4,
                    liquidity_provider_5, liquidity_provider_3,
                },
                variables::{decimals},
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
        },
    },
};
use debug::PrintTrait;


/// Failures ///

// Test ending the auction before it starts fails
#[test]
#[available_gas(100000000)]
fn test_ending_auction_before_it_starts_fails() {
    let (mut vault_facade, _) = setup_facade();

    // Try to end auction before it starts
    vault_facade.end_auction_expect_error(Errors::AuctionEndDateNotReached);
}

// Test ending the auction before the auction end date fails
#[test]
#[available_gas(200000000)]
fn test_ending_auction_before_auction_end_date_fails() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);

    // Try to end auction before auction end date
    vault.end_auction_expect_error(Errors::AuctionEndDateNotReached);
}

// Test ending the auction after it already ended fails
#[test]
#[available_gas(100000000)]
fn test_ending_auction_while_round_running_fails() {
    let (mut vault_facade, _) = setup_test_running();

    // Try to end auction after it has already ended
    vault_facade.end_auction_expect_error(Errors::AuctionAlreadyEnded);
}

// Test ending the auction after the auction ends fails (next state)
#[test]
#[available_gas(100000000)]
fn test_ending_auction_while_round_settled_fails() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round = vault_facade.get_current_round();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);
    accelerate_to_settled(ref vault_facade, current_round.get_strike_price());

    // Try to end auction before round transition period is over
    vault_facade.end_auction_expect_error(Errors::AuctionAlreadyEnded);
}


/// Event Tests ///

// Test ending the auction emits the correct event
// @note shold move to option round state transition tests
#[test]
#[available_gas(100000000)]
fn test_auction_ended_option_round_event() {
    let mut rounds_to_run = 3;
    let (mut vault, _) = setup_facade();

    while rounds_to_run > 0_u32 {
        let mut current_round = vault.get_current_round();
        accelerate_to_auctioning(ref vault);

        // Make bids
        let bidder: ContractAddress = *option_bidders_get(1)[0];
        let bid_amount = current_round.get_total_options_available();
        let bid_price = current_round.get_reserve_price();
        let t1 = current_round.get_bid_tree_nonce();
        let b = current_round.place_bid(bid_amount, bid_price, bidder);
        let t2 = current_round.get_bid_tree_nonce();
        println!("Bid: {:?}", b);
        println!("Tree nonce before: {:?}", t1);
        println!("Tree nonce after: {:?}", t2);
        // current_round.place_bid(bid_amount, bid_price, bidder);

        // End auction
        clear_event_logs(array![vault.contract_address()]);
        let (clearing_price, total_options_sold) = timeskip_and_end_auction(ref vault);

        // Check the event emits correctly
        assert(clearing_price > 0, 'clearing price shd be > 0');
        assert_event_auction_end(
            vault.contract_address(),
            total_options_sold,
            clearing_price,
            current_round.unsold_liquidity(),
            0,
            current_round.get_round_id(),
            current_round.contract_address()
        );

        accelerate_to_settled(ref vault, current_round.get_strike_price() * 2);
        rounds_to_run -= 1;
    }
}


/// State Tests ///

/// Round ids/states

// Test ending an auction does not change the current round id
#[test]
#[available_gas(100000000)]
fn test_end_auction_does_not_update_current_and_next_round_ids() {
    let mut rounds_to_run = 3;
    let (mut vault, _) = setup_facade();

    while rounds_to_run > 0_u32 {
        accelerate_to_auctioning(ref vault);
        let mut current_round = vault.get_current_round();
        let current_round_id = vault.get_current_round_id();
        accelerate_to_running(ref vault);
        let new_current_round_id = vault.get_current_round_id();

        assert(new_current_round_id == current_round_id, 'current round id changed');

        accelerate_to_settled(ref vault, current_round.get_strike_price());
        rounds_to_run -= 1;
    }
}

// Test ending an auction updates the current round state
// @note should this be a state transition test in option round tests
#[test]
#[available_gas(100000000)]
fn test_end_auction_updates_current_round_state() {
    let mut rounds_to_run = 3;
    let (mut vault, _) = setup_facade();

    while rounds_to_run > 0_u32 {
        accelerate_to_auctioning(ref vault);

        accelerate_to_running(ref vault);
        let mut current_round = vault.get_current_round();
        assert(
            current_round.get_state() == OptionRoundState::Running, 'current round shd be running'
        );

        accelerate_to_settled(ref vault, current_round.get_strike_price());

        rounds_to_run -= 1;
    }
}

/// Liquidity

// Test that winning bids are sent to the vault as premiums, and
// refundable bids remain in the round
#[test]
#[available_gas(100000000)]
fn test_end_auction_eth_transfer() {
    let (mut vault_facade, eth) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();

    let option_bidders = option_bidders_get(2).span();
    let bid_amount = current_round.get_total_options_available();
    let losing_price = current_round.get_reserve_price();
    let winning_price = 2 * losing_price;
    current_round
        .place_bids(
            array![bid_amount, bid_amount].span(),
            array![losing_price, winning_price].span(),
            option_bidders
        );

    // Vault and round balances before auction ends
    let round_balance_before = eth.balance_of(current_round.contract_address());
    let vault_balance_before = eth.balance_of(vault_facade.contract_address());

    // End auction (2 bidders, first bid gets refunded, second bid is used for premiums
    let (clearing_price, options_sold) = timeskip_and_end_auction(ref vault_facade);

    // Vault and round balances after auction ends
    let round_balance_after = eth.balance_of(current_round.contract_address());
    let vault_balance_after = eth.balance_of(vault_facade.contract_address());

    // Check premiums transfer from round to vault, and unused bids remain in round
    assert(clearing_price * options_sold != 0, 'premiums shd be > 0');
    assert(
        round_balance_before == bid_amount * losing_price + bid_amount * winning_price,
        'round balance before wrong'
    );
    assert(
        round_balance_after == round_balance_before - bid_amount * winning_price,
        'round balance after wrong'
    );
    assert(
        vault_balance_after == vault_balance_before + bid_amount * winning_price,
        'vault balance after wrong'
    );
}

// Test ending the auction updates the vault and liquidity provider balances
#[test]
#[available_gas(100000000)]
fn test_end_auction_updates_locked_and_unlocked_balances() {
    let number_of_liquidity_providers = 4;
    let mut deposit_amounts = create_array_gradient(
        100 * decimals(), 100 * decimals(), number_of_liquidity_providers
    )
        .span();
    let (mut vault, _, liquidity_providers, _) = setup_test_auctioning_providers(
        number_of_liquidity_providers, deposit_amounts
    );
    let mut current_round = vault.get_current_round();
    // Amounts to deposit: [100, 200, 300, 400]

    // Vault and liquidity provider balances before auction ends
    let mut liquidity_providers_locked_before = vault
        .get_lp_locked_balances(liquidity_providers)
        .span();
    let mut liquidity_providers_unlocked_before = vault
        .get_lp_unlocked_balances(liquidity_providers)
        .span();
    let (vault_locked_before, vault_unlocked_before) = vault
        .get_total_locked_and_unlocked_balance();

    // End auction
    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
    let total_premiums = options_sold * clearing_price;
    let sold_liq = current_round.sold_liquidity();
    let unsold_liq = current_round.unsold_liquidity();
    let total_liq = sold_liq + unsold_liq;

    // Vault and liquidity provider balances after auction ends
    let mut liquidity_providers_locked_after = vault
        .get_lp_locked_balances(liquidity_providers)
        .span();
    let mut liquidity_providers_unlocked_after = vault
        .get_lp_unlocked_balances(liquidity_providers)
        .span();
    let (vault_locked_after, vault_unlocked_after) = vault.get_total_locked_and_unlocked_balance();

    // Check vault balances
    assert(
        (vault_locked_before, vault_unlocked_before) == (total_liq, 0), 'vault balance before wrong'
    );
    assert(
        (vault_locked_after, vault_unlocked_after) == (sold_liq, unsold_liq + total_premiums),
        'vault balance after'
    );
    assert(total_premiums > 0, 'premiums shd be greater than 0');

    // Check liquidity provider balances
    loop {
        match liquidity_providers_locked_before.pop_front() {
            Option::Some(lp_locked_before) => {
                let lp_unlocked_before = liquidity_providers_unlocked_before.pop_front().unwrap();
                let lp_locked_after = liquidity_providers_locked_after.pop_front().unwrap();
                let lp_unlocked_after = liquidity_providers_unlocked_after.pop_front().unwrap();

                let lp_deposit_amount = deposit_amounts.pop_front().unwrap();
                let lp_sold_liq = sold_liq * *lp_deposit_amount / total_liq;
                let lp_unsold_liq_and_prems = *lp_deposit_amount
                    * (unsold_liq + total_premiums)
                    / total_liq;

                assert(
                    (*lp_locked_before, *lp_unlocked_before) == (*lp_deposit_amount, 0),
                    'LP locked before wrong'
                );
                assert(
                    (
                        *lp_locked_after, *lp_unlocked_after
                    ) == (lp_sold_liq, lp_unsold_liq_and_prems),
                    'LP locked after wrong'
                );
            },
            Option::None => { break (); }
        }
    }
}

// Test that the vault and LP spreads update when the auction ends. Tests rollover
// amounts with withdraw and topup
#[test]
#[available_gas(150000000)]
fn test_end_auction_updates_vault_and_lp_spreads_complex() {
    let number_of_liquidity_providers = 4;
    let round1_deposits = create_array_gradient(
        100 * decimals(), 100 * decimals(), number_of_liquidity_providers
    )
        .span();
    // Accelerate through round 1 with premiums and a payout
    let (mut vault, _, liquidity_providers, _) = setup_test_auctioning_providers(
        number_of_liquidity_providers, round1_deposits
    );

    // (100, 200, 300, 400)

    let mut round1 = vault.get_current_round();
    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
    let total_premiums1 = clearing_price * options_sold;
    let sold_liq1 = round1.sold_liquidity();
    let unsold_liq1 = round1.unsold_liquidity();
    let total_payout1 = accelerate_to_settled(ref vault, 2 * round1.get_strike_price());
    let total_liq1 = sold_liq1 + unsold_liq1;
    // Total and individual remaining liquidity amounts after round 1
    let remaining_liq1 = sold_liq1 - total_payout1;
    let earned_liq1 = unsold_liq1 + total_premiums1;

    // Lp3 withdraws from premiums, lp4 adds a topup
    let lp3 = liquidity_provider_3();
    let lp4 = liquidity_provider_4();
    let withdraw_amount = 1;
    let topup_amount = 100 * decimals();
    vault.withdraw(withdraw_amount, lp3);
    vault.deposit(topup_amount, lp4);

    // Start round 2' auction with no additional deposits
    let mut round2 = vault.get_current_round();
    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());
    // Create array of round2's deposits
    let mut round2_deposits = array![
        (*round1_deposits.at(0) * (remaining_liq1 + earned_liq1)) / total_liq1,
        (*round1_deposits.at(1) * (remaining_liq1 + earned_liq1)) / total_liq1,
        ((*round1_deposits.at(2) * (remaining_liq1 + earned_liq1)) / total_liq1) - withdraw_amount,
        ((*round1_deposits.at(3) * (remaining_liq1 + earned_liq1)) / total_liq1) + topup_amount,
    ]
        .span();

    // Vault and LP spreads before auction 2 ends
    let mut lp_spreads_before = vault
        .get_lp_locked_and_unlocked_balances(liquidity_providers)
        .span();
    let vault_spread_before = vault.get_total_locked_and_unlocked_balance();
    // End round 2's auction
    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
    let total_premiums2 = clearing_price * options_sold;
    let sold_liq2 = round2.sold_liquidity();
    let unsold_liq2 = round2.unsold_liquidity();
    let total_liq2 = sold_liq2 + unsold_liq2;
    let earned_liq2 = unsold_liq2 + total_premiums2;
    // Vault and LP spreads after the auction ends
    let mut lp_spreads_after = vault
        .get_lp_locked_and_unlocked_balances(liquidity_providers)
        .span();
    let vault_spread_after = vault.get_total_locked_and_unlocked_balance();

    // Check vault spreads
    assert(total_premiums2 > 0, 'premiums shd be greater than 0');
    //remaining_liquidity1 + topup_amount - withdraw_amount, 0),
    assert(
        vault_spread_before == (remaining_liq1 + earned_liq1 + topup_amount - withdraw_amount, 0),
        'vault spread before wrong'
    );
    //            remaining_liquidity1 + topup_amount - withdraw_amount, total_premiums2
    assert_eq!(
        vault_spread_after,
        (
            remaining_liq1 + earned_liq1 + topup_amount - withdraw_amount - unsold_liq2,
            total_premiums2 + unsold_liq2
        )
    );
    // Check LP spreads
    loop {
        match lp_spreads_before.pop_front() {
            Option::Some(lp_spread_before) => {
                let lp_spread_after = lp_spreads_after.pop_front().unwrap();
                let lp_starting_liquidity2 = round2_deposits.pop_front().unwrap();
                assert(*lp_spread_before == (*lp_starting_liquidity2, 0), 'LP spread before wrong');
                assert(
                    *lp_spread_after == (
                        *lp_starting_liquidity2 * sold_liq2 / total_liq2,
                        *lp_starting_liquidity2 * earned_liq2 / total_liq2
                    ),
                    'LP spread after wrong'
                );
            },
            Option::None => { break (); }
        }
    }
}

