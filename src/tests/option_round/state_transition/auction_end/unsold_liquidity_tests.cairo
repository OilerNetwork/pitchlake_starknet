use pitch_lake::{
    tests::{
        utils::{
            helpers::{
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_running_custom,
                    timeskip_and_end_auction, accelerate_to_auctioning_custom,
                    accelerate_to_settled,
                },
                setup::{setup_facade, setup_test_auctioning_bidders},
                general_helpers::{
                    create_array_linear, create_array_gradient, create_array_gradient_reverse,
                    get_portion_of_amount, get_erc20_balance, get_erc20_balances,
                },
            },
            lib::{
                test_accounts::{
                    liquidity_provider_1, liquidity_provider_2, liquidity_provider_3,
                    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
                    option_bidder_buyer_4, option_bidders_get, liquidity_providers_get,
                },
                variables::{decimals},
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
        },
    }
};
use pitch_lake::library::pricing_utils::max_payout_per_option;
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

// Test sold liquidity is 0 before auction end
#[test]
#[available_gas(50000000)]
fn test_sold_liquidity_0_before_auction_end() {
    let (mut vault, _) = setup_facade();
    let total_options_available = accelerate_to_auctioning(ref vault);

    // Place bids but not end auction
    let mut current_round = vault.get_current_round();
    let bid_amount = total_options_available;
    let bid_price = current_round.get_reserve_price();
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());

    // Check that sold liquidity is 0 before auction end
    let sold_liq = vault.get_sold_liquidity(current_round.get_round_id());
    assert(sold_liq == 0, 'should be 0 pre auction end');
}

// Test sold liq backs all options selling partial
#[test]
#[available_gas(50000000)]
fn test_sold_liquidity_backs_all_sold_options() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let options_available = accelerate_to_auctioning(ref vault);

    let bid_amount = 97 * options_available / 100;
    let bid_price = current_round.get_reserve_price();
    let (_, options_sold) = accelerate_to_running_custom(
        ref vault,
        array![option_bidder_buyer_1()].span(),
        array![bid_amount].span(),
        array![bid_price].span()
    );

    let req_collateral = options_sold
        * max_payout_per_option(current_round.get_strike_price(), current_round.get_cap_level());

    assert(req_collateral == current_round.sold_liquidity(), 'sold liq wrong');
    assert(
        current_round.sold_liquidity()
            + current_round.unsold_liquidity() == current_round.starting_liquidity(),
        'unsold liq wrong'
    );
}

// Test sold liq backs all options selling all
#[test]
#[available_gas(50000000)]
fn test_sold_liquidity_backs_all_sold_options_all() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);

    let bid_amount = current_round.get_total_options_available();
    let bid_price = current_round.get_reserve_price();
    let (_, options_sold) = accelerate_to_running_custom(
        ref vault,
        array![option_bidder_buyer_1()].span(),
        array![bid_amount].span(),
        array![bid_price].span()
    );

    let req_collateral = options_sold
        * max_payout_per_option(current_round.get_strike_price(), current_round.get_cap_level());

    assert(req_collateral == current_round.sold_liquidity(), 'sold liq wrong');
    assert(
        current_round.sold_liquidity()
            + current_round.unsold_liquidity() == current_round.starting_liquidity(),
        'unsold liq wrong'
    );
}


// Test un/sold liquidity is correct
#[test]
#[available_gas(50000000)]
fn test_unsold_liquidity_1() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let options_available = accelerate_to_auctioning(ref vault);

    let bidders = option_bidders_get(2);
    let bid_amount = options_available / 4;
    let bid_amounts = array![bid_amount, bid_amount];
    let bid_prices = create_array_linear((current_round.get_reserve_price()), bid_amounts.len());
    let (_, sold_options) = accelerate_to_running_custom(
        ref vault, bidders.span(), bid_amounts.span(), bid_prices.span()
    );

    let expected_sold_liq = max_payout_per_option(
        current_round.get_strike_price(), current_round.get_cap_level()
    )
        * sold_options;
    let expected_unsold_liq = current_round.starting_liquidity() - expected_sold_liq;
    let sold_liq = vault.get_sold_liquidity(current_round.get_round_id());
    let unsold_liq = vault.get_unsold_liquidity(current_round.get_round_id());

    assert(sold_liq == expected_sold_liq, 'sold liq wrong');
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
#[available_gas(80000000)]
fn test_unsold_liquidity_is_unlocked_for_liquidity_providers() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let number_of_lps = 3;
    let mut liquidity_providers = liquidity_providers_get(number_of_lps).span();
    let deposit_amount = 20 * decimals();
    let deposit_amounts = create_array_linear(deposit_amount, number_of_lps).span();
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
    let sold_liq = vault.get_sold_liquidity(current_round.get_round_id());

    let mut expected_sold_liq_shares = get_portion_of_amount(deposit_amounts, sold_liq).span();
    let mut expected_unsold_liq_shares = get_portion_of_amount(deposit_amounts, unsold_liq).span();
    let total_premium = current_round.total_premiums();
    let mut expected_premiums_shares = get_portion_of_amount(deposit_amounts, total_premium).span();

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
                let share_of_sold_liq = expected_sold_liq_shares.pop_front().unwrap();
                let share_of_unsold_liq = deposit_amount - *share_of_sold_liq;
                let share_of_premiums = expected_premiums_shares.pop_front().unwrap();
                let expected_lp_locked_after = *locked_balance_before - share_of_unsold_liq;

                let share_of_unsold_liq = expected_unsold_liq_shares.pop_front().unwrap();
                let expected_lp_unlocked_after = *unlocked_balance_before
                    + *share_of_unsold_liq
                    + *share_of_premiums;

                assert(*locked_balance_after == expected_lp_locked_after, 'lp locked wrong');

                assert(*unlocked_balance_after == expected_lp_unlocked_after, 'lp unlocked wrong');
            },
            Option::None => { break (); }
        }
    };
}

// Test unsold liquidity adds to liquidity provider's unlocked when round settles
#[test]
#[available_gas(50000000)]
fn test_unsold_liquidity_is_unlocked_for_liquidity_providers_end_of_round() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let deposit_amount = 20 * decimals();
    let liquidity_provider = liquidity_provider_1();
    let options_available = accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );

    // Get liquidity providers locked and unlocked balances before auction end
    let (locked_balance_before, unlocked_balance_before): (u256, u256) = vault
        .get_lp_locked_and_unlocked_balance(liquidity_provider);

    // Bid for 1/2 the options, end auction and round (no payout)
    let option_bidders = array![option_bidder_buyer_1()].span();
    let bid_amount = options_available / 2;
    let bid_amounts = array![bid_amount].span();
    let bid_prices = array![current_round.get_reserve_price()].span();
    accelerate_to_running_custom(ref vault, option_bidders, bid_amounts, bid_prices);
    accelerate_to_settled(ref vault, current_round.get_strike_price() - 1);

    // Unsold liquidity and premiums
    let total_premium = current_round.total_premiums();

    // Get liquidity providers locked and unlocked balances after round settles
    let (locked_balance_after, unlocked_balance_after): (u256, u256) = vault
        .get_lp_locked_and_unlocked_balance(liquidity_provider);

    assert(locked_balance_before == deposit_amount, 'locked before wrong');
    assert(unlocked_balance_before == 0, 'unlocked before wrong');
    assert(locked_balance_after == 0, 'locked after wrong');
    assert(unlocked_balance_after == deposit_amount + total_premium, 'unlocked after wrong');
}

