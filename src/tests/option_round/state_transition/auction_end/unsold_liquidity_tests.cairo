use pitch_lake_starknet::{
    tests::{
        utils::{
            helpers::{
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_running_custom,
                    timeskip_and_end_auction, accelerate_to_auctioning_custom,
                },
                setup::{setup_facade, setup_test_auctioning_bidders},
                general_helpers::{
                    create_array_linear, create_array_gradient, create_array_gradient_reverse,
                    get_portion_of_amount, get_erc20_balance, get_erc20_balances,
                },
            },
            lib::{
                test_accounts::{
                    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
                    option_bidder_buyer_4, option_bidders_get, liquidity_providers_get,
                },
                variables::{decimals},
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait, OptionRoundParams},
            },
        },
    }
};
use starknet::testing::{set_block_timestamp, set_contract_address};
use debug::PrintTrait;


// Test unsold liquidity is 0 before auction end
#[test]
#[available_gas(50000000)]
fn test_unsold_liquidity_0_before_auction_end() {
    let (mut vault, _) = setup_facade();
    let total_options_available = accelerate_to_auctioning(ref vault);

    // Place bids but not end auction
    let mut current_round = vault.get_current_round();
    let bid_amount = total_options_available;
    let bid_price = current_round.get_reserve_price();
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());

    // Check that unsold liquidity is 0 before auction end
    let unsold_liq = vault.get_unsold_liquidity(current_round.get_round_id());
    assert(unsold_liq == 0, 'should be 0 pre auction end');
}

// Test unsold liquidity is 0 if all options sell
#[test]
#[available_gas(50000000)]
fn test_unsold_liquidity_0_if_all_options_sell() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);

    // Check that unsold liquidity is 0 if all options sell
    let unsold_liq = vault.get_unsold_liquidity(current_round.get_round_id());
    assert(unsold_liq == 0, 'should be 0');
}

// Test unsold liquidity is correct
#[test]
#[available_gas(50000000)]
fn test_unsold_liquidity_1() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let options_available = accelerate_to_auctioning(ref vault);

    // Get liquidity locked before auction ends
    let total_locked_before = vault.get_total_locked_balance();

    let liquidity_providers = liquidity_providers_get(2);
    let bid_amounts = array![options_available / 3, options_available / 3];
    let bid_prices = create_array_linear(current_round.get_reserve_price(), bid_amounts.len());
    accelerate_to_running_custom(
        ref vault, liquidity_providers.span(), bid_amounts.span(), bid_prices.span()
    );

    // Check 1/3 of the total locked liquidity is unsold
    let expected_unsold_liq = total_locked_before / 3;
    let unsold_liq = vault.get_unsold_liquidity(current_round.get_round_id());
    assert(unsold_liq == expected_unsold_liq, 'unsold liq wrong');
}

// Test unsold liquidity moves from locked to unlocked
#[test]
#[available_gas(50000000)]
fn test_unsold_liquidity_moves_from_locked_to_unlocked() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let options_available = accelerate_to_auctioning(ref vault);

    // Get liquidity locked before auction ends
    let (total_locked_before, total_unlocked_before) = vault
        .get_total_locked_and_unlocked_balance();

    let option_buyers = option_bidders_get(2);
    let bid_amounts = array![options_available / 3, options_available / 3];
    let bid_prices = array![current_round.get_reserve_price(), current_round.get_reserve_price()];

    let (clearing_price, total_options_sold) = accelerate_to_running_custom(
        ref vault, option_buyers.span(), bid_amounts.span(), bid_prices.span()
    );

    // Check unsold moves from locked to unlocked
    let unsold_liq = vault.get_unsold_liquidity(current_round.get_round_id());
    assert(unsold_liq > 0, 'unsold liq shd not be 0');
    let (total_locked_after, total_unlocked_after) = vault.get_total_locked_and_unlocked_balance();
    let total_premium = total_options_sold * clearing_price;

    assert(total_locked_after == total_locked_before - unsold_liq, 'locked balance after fail');
    assert(
        total_unlocked_after == total_unlocked_before + unsold_liq + total_premium,
        'unlocked balance after fail'
    );
}

// Test unsold liquidity adds to liquidity provider's unlocked balance
#[test]
#[available_gas(50000000)]
fn test_unsold_liquidity_is_unlocked_for_liquidity_providers() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let number_of_lps = 3;
    let mut liquidity_providers = liquidity_providers_get(number_of_lps).span();
    let deposit_amounts = create_array_linear(20 * decimals(), number_of_lps).span();
    let options_available = accelerate_to_auctioning_custom(
        ref vault, liquidity_providers, deposit_amounts
    );

    // Get liquidity providers locked and unlocked balances before auction end
    let mut locked_and_unlocked_balances_before: Span<(u256, u256)> = vault
        .get_lp_locked_and_unlocked_balances(liquidity_providers)
        .span();

    // Bid for 1/2 the options
    let option_bidders = array![option_bidder_buyer_1()].span();
    let bid_amounts = array![options_available / 2].span();
    let bid_prices = array![current_round.get_reserve_price()].span();
    accelerate_to_running_custom(ref vault, option_bidders, bid_amounts, bid_prices);

    // Check each LP's unlocked balance increments as expected
    let unsold_liq = vault.get_unsold_liquidity(current_round.get_round_id());
    let mut expected_unsold_liq_shares = get_portion_of_amount(deposit_amounts, unsold_liq).span();
    let mut locked_and_unlocked_balances_after: Span<(u256, u256)> = vault
        .get_lp_locked_and_unlocked_balances(liquidity_providers)
        .span();
    assert(unsold_liq > 0, 'unsold liq shd not be 0');
    loop {
        match liquidity_providers.pop_front() {
            Option::Some(_) => {
                let (locked_balance_before, unlocked_balance_before) =
                    locked_and_unlocked_balances_before
                    .pop_front()
                    .unwrap();
                let (locked_balance_after, unlocked_balance_after) =
                    locked_and_unlocked_balances_after
                    .pop_front()
                    .unwrap();
                let share_of_unsold_liq = expected_unsold_liq_shares.pop_front().unwrap();

                assert(
                    *locked_balance_after == *locked_balance_before - *share_of_unsold_liq,
                    'lp locked wrong'
                );
                assert(
                    *unlocked_balance_after == *unlocked_balance_before + *share_of_unsold_liq,
                    'lp unlocked wrong'
                );
            },
            Option::None => { break (); }
        }
    };
}

