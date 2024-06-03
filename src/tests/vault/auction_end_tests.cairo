use core::array::SpanTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};
use pitch_lake_starknet::{
    eth::Eth,
    vault::{
        IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault,
        IVaultSafeDispatcherTrait,
    },
    tests::{
        utils::{
            event_helpers::{pop_log, assert_no_events_left, assert_event_auction_end},
            accelerators::{
                accelerate_to_auctioning, accelerate_to_running, accelerate_to_auctioning_custom,
                accelerate_to_running_custom, accelerate_to_settled,
                timeskip_past_round_transition_period, timeskip_and_end_auction,
            },
            utils::{
                create_array_gradient, create_array_linear, sum_u256_array, get_portion_of_amount,
                split_spreads,
            },
            test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                liquidity_providers_get, option_bidders_get, liquidity_provider_4,
                liquidity_provider_5,
            },
            variables::{decimals}, setup::{setup_facade},
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
            mocks::mock_market_aggregator::{
                MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
                IMarketAggregatorSetterDispatcherTrait
            },
        },
    },
    option_round::{OptionRoundState, IOptionRoundDispatcher, IOptionRoundDispatcherTrait},
};
use debug::PrintTrait;


/// Failures ///

// Test auction cannot end if the current round is auctioning and the auction end date has not been reached
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot end auction', 'ENTRYPOINT_FAILED'))]
fn test_end_auction_while_current_round_auctioning_too_early_fails() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);

    // Try to end auction before auction end date
    vault.end_auction();
}

// Test auction cannot end if the current round is running
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot end auction before it starts', 'ENTRYPOINT_FAILED',))]
fn test_end_auction_while_current_round_running_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);

    // Try to end auction after it has already ended
    vault_facade.end_auction();
}

// Test auction cannot end if the current round is settled
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'Auction cannot settle before due time',))]
fn test_auction_end_before_end_date_failure() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);
    accelerate_to_settled(ref vault_facade, 0);

    // Try to end auction before round transition period is over
    vault_facade.end_auction();
}


/// Event Tests ///

// Test that the auction end event emits correctly
#[test]
#[available_gas(10000000)]
fn test_end_auction_end_auction_event() {
    let mut rounds_to_run = 3;
    let (mut vault, _) = setup_facade();

    loop {
        match rounds_to_run {
            0 => { break (); },
            _ => {
                accelerate_to_auctioning(ref vault);

                let (clearing_price, _) = accelerate_to_running(ref vault);
                // Check the event emits correctly
                let mut current_round = vault.get_current_round();
                assert_event_auction_end(current_round.contract_address(), clearing_price);

                accelerate_to_settled(ref vault, 0);

                rounds_to_run -= 1;
            },
        }
    }
}


/// State Tests ///

// Test when an auction ends, the curent and next rounds do not change
#[test]
#[available_gas(10000000)]
fn test_end_auction_does_not_update_current_and_next_round_ids() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);

    // End current round stays the same when the auction ends
    assert(vault_facade.get_current_round_id() == 1, 'current shd be 0');
    accelerate_to_running(ref vault_facade);
    assert(vault_facade.get_current_round_id() == 1, 'current shd be 1');

    // Check consecutive rounds
    accelerate_to_settled(ref vault_facade, 0);
    accelerate_to_auctioning(ref vault_facade);
    assert(vault_facade.get_current_round_id() == 2, 'current shd be 2');
    accelerate_to_running(ref vault_facade);
    assert(vault_facade.get_current_round_id() == 2, 'current shd be 2');

    accelerate_to_settled(ref vault_facade, 0);
    accelerate_to_auctioning(ref vault_facade);
    assert(vault_facade.get_current_round_id() == 3, 'current shd be 3');
    accelerate_to_running(ref vault_facade);
    assert(vault_facade.get_current_round_id() == 3, 'current shd be 3');
}

// Test when an auction ends, the option round states update correctly
// @note should this be a state transition test in option round tests
#[test]
#[available_gas(10000000)]
fn test_end_auction_updates_current_and_next_round_states() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);

    // Check round 1 is running and round 2 is open
    let (mut round1, mut round2) = vault_facade.get_current_and_next_rounds();
    assert(round1.get_state() == OptionRoundState::Running, 'round1 shd be running');
    assert(round2.get_state() == OptionRoundState::Open, 'round2 shd be open');

    // Check consecutive rounds
    accelerate_to_settled(ref vault_facade, 0);
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);
    let mut round3 = vault_facade.get_next_round();
    assert(round2.get_state() == OptionRoundState::Running, 'round2 shd be running');
    assert(round3.get_state() == OptionRoundState::Open, 'round3 shd be open');
}

// Test that premiums are sent to the vault and unused bids remain in the round
#[test]
#[available_gas(10000000)]
fn test_end_auction_premiums_eth_transfer() {
    let (mut vault_facade, eth) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();

    // Balances before auction end
    let round_balance_before = eth.balance_of(current_round.contract_address());
    let vault_balance_before = eth.balance_of(vault_facade.contract_address());
    // End auction
    let bidders = option_bidders_get(2).span();
    let bid_count = current_round.get_total_options_available();
    let losing_price = current_round.get_reserve_price();
    let losing_amount = bid_count * losing_price;
    let winning_price = 2 * losing_price;
    let winning_amount = bid_count * winning_price;
    accelerate_to_running_custom(
        ref vault_facade,
        bidders,
        array![losing_amount, winning_amount].span(),
        array![losing_price, winning_price].span()
    );
    // Balances after auction end
    let round_balance_after = eth.balance_of(current_round.contract_address());
    let vault_balance_after = eth.balance_of(vault_facade.contract_address());

    // Check premiums transfer from round to vault, and unused bids remain in round
    assert(round_balance_before == losing_amount + winning_amount, 'round balance before wrong');
    assert(
        round_balance_after == round_balance_before - winning_amount, 'round balance after wrong'
    );
    assert(
        vault_balance_after == vault_balance_before + winning_amount, 'vault balance after wrong'
    );
}

// Test that the vault and LP spreads update when the auction ends
// @dev This is a simple example
#[test]
#[available_gas(10000000)]
fn test_end_auction_updates_vault_and_lp_spreads_simple() {
    let (mut vault, _) = setup_facade();
    let mut lps = liquidity_providers_get(4).span();
    let mut deposit_amounts = create_array_gradient(100 * decimals(), 100 * decimals(), lps.len())
        .span(); // (100, 200, 300, 400)
    let total_deposits = sum_u256_array(deposit_amounts);
    accelerate_to_auctioning_custom(ref vault, lps, deposit_amounts);

    // Vault and LP spreads before auction end
    let mut lp_spreads_before = vault.get_lp_balance_spreads(lps);
    let vault_spread_before = vault.get_balance_spread();
    // End auction
    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
    let total_premiums = options_sold * clearing_price;
    let mut individual_premiums = get_portion_of_amount(deposit_amounts, total_deposits).span();
    // Vault and LP spreads after auction end
    let mut lp_spreads_after = vault.get_lp_balance_spreads(lps);
    let vault_spread_after = vault.get_balance_spread();

    // Check vault spreads
    assert(vault_spread_before == (total_deposits, 0), 'vault spread before wrong');
    assert(vault_spread_after == (total_deposits, total_premiums), 'vault spread after wrong');
    // Check LP1, 2, 3 & 4's spread
    loop {
        match lp_spreads_before.pop_front() {
            Option::Some(lp_spread_before) => {
                let lp_spread_after = lp_spreads_after.pop_front().unwrap();
                let lp_deposit_amount = deposit_amounts.pop_front().unwrap();
                let lp_premium = individual_premiums.pop_front().unwrap();
                assert(lp_spread_before == (*lp_deposit_amount, 0), 'LP spread before wrong');
                assert(
                    lp_spread_after == (*lp_deposit_amount, *lp_premium), 'LP spread after wrong'
                );
            },
            Option::None => { break (); }
        }
    };
}

// Test that the vault and LP spreads update when the auction ends
// @dev This is a more complex example, performing the same logic as the above simpler test
// with liquidity participants adding deposits before the next auction ends
#[test]
#[available_gas(10000000)]
fn test_end_auction_updates_vault_and_lp_spreads_complex() {
    let (mut vault, _) = setup_facade();
    let mut lps = liquidity_providers_get(4).span();
    let deposit_amounts1 = create_array_gradient(100 * decimals(), 100 * decimals(), lps.len())
        .span(); // (100, 200, 300, 400)
    accelerate_to_auctioning_custom(ref vault, lps, deposit_amounts1);
    let mut round1 = vault.get_current_round();
    accelerate_to_running(ref vault);
    accelerate_to_settled(ref vault, 2 * round1.get_strike_price());
    let remaining_liquidity1 = round1.starting_liquidity()
        + round1.total_premiums()
        - round1.total_payout();
    let mut individual_remaining_liquidity1 = get_portion_of_amount(
        deposit_amounts1, remaining_liquidity1
    )
        .span();
    // LP4 makes an additional deposit before auction 2 starts, then start auction 2
    let lp4 = liquidity_provider_4();
    let topup_amount = 100 * decimals();
    accelerate_to_auctioning_custom(ref vault, array![lp4].span(), array![topup_amount].span());

    // Vault and LP spreads before auction 2 ends
    let mut lp_spreads_before = vault.get_lp_balance_spreads(lps).span();
    let vault_spread_before = vault.get_balance_spread();
    // End auction 2
    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
    // Vault and LP spreads after auction 2 ends
    let mut lp_spreads_after = vault.get_lp_balance_spreads(lps).span();
    let vault_spread_after = vault.get_balance_spread();
    let (deposit_amounts2, _) = split_spreads(lp_spreads_after);
    let total_premiums2 = clearing_price * options_sold;
    let mut individual_premiums2 = get_portion_of_amount(deposit_amounts2.span(), total_premiums2)
        .span();
    // @dev Remove lp4 from arrays, to test separately
    let lp4_spread_before = *lp_spreads_before.pop_back().unwrap();
    let lp4_spread_after = *lp_spreads_after.pop_back().unwrap();
    let lp4_remaining_liquidity1 = *individual_remaining_liquidity1.pop_back().unwrap();
    let lp4_individual_premium2 = *individual_premiums2.pop_back().unwrap();

    // Check vault spreads
    assert(
        vault_spread_before == (remaining_liquidity1 + topup_amount, 0), 'vault spread before wrong'
    );
    assert(
        vault_spread_after == (remaining_liquidity1 + topup_amount, total_premiums2),
        'vault spread after wrong'
    );
    // Check LP 1-3's spreads
    loop {
        match lp_spreads_before.pop_front() {
            Option::Some(lp_spread_before) => {
                let lp_spread_after = lp_spreads_after.pop_front().unwrap();
                let lp_premiums2 = individual_premiums2.pop_front().unwrap();
                let lp_remaining_liquidity1 = individual_remaining_liquidity1.pop_front().unwrap();
                assert(
                    *lp_spread_before == (*lp_remaining_liquidity1, 0), 'LP spread before wrong'
                );
                assert(
                    *lp_spread_after == (*lp_remaining_liquidity1, *lp_premiums2),
                    'LP spread after wrong'
                );
            },
            Option::None => { break (); }
        }
    };
    // Check LP4's spread
    assert(
        lp4_spread_before == (lp4_remaining_liquidity1 + topup_amount, 0), 'LP4 spread before wrong'
    );
    assert(
        lp4_spread_after == (lp4_remaining_liquidity1 + topup_amount, lp4_individual_premium2),
        'LP4 spread before wrong'
    );
}

