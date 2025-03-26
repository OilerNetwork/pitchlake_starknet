use core::num::traits::Zero;
use pitch_lake::library::utils::min;
use pitch_lake::library::constants::{BPS_i128, BPS_felt252, BPS_u256, BPS_u128};

// Calculate the maximum payout for a single option
fn max_payout_per_option(strike_price: u256, cap_level: u128) -> u256 {
    (strike_price * cap_level.into()) / BPS_u256
}

// Calculate the actual payout for a single option
fn calculate_payout_per_option(
    strike_price: u256, cap_level: u128, settlement_price: u256
) -> u256 {
    if (settlement_price <= strike_price) {
        0
    } else {
        let uncapped = settlement_price - strike_price;
        let capped = max_payout_per_option(strike_price, cap_level);

        min(capped, uncapped)
    }
}

// Calculate the total number of options available to sell in an auction
fn calculate_total_options_available(
    starting_liquidity: u256, strike_price: u256, cap_level: u128
) -> u256 {
    let capped = max_payout_per_option(strike_price, cap_level);
    match capped == 0 {
        // @dev If the max payout per option is 0, then there are 0 options to sell
        true => 0,
        // @dev Else the number of options available is the starting liquidity divided by
        // the capped amount
        false => starting_liquidity / capped
    }
}

// @note TODO
// cl = λ − k / (α × (k + 1))
fn calculate_cap_level(a: u128, k: i128, vol: u128) -> u128 {
    // @dev λ = 2.3300 * vol
    let lambda: i128 = 23300 * vol.try_into().expect('Vol u128 -> i128 failed') / BPS_i128;

    // @dev Cap level must be positive
    if k >= lambda {
        1
    } else {
        // @dev `λ - k` >= 0 here, cast from i128 to u128 through felt252
        let lambda_minus_k: u128 = Into::<i128, felt252>::into(lambda - k).try_into().unwrap();

        // @dev Ensure k+1 is positive then cast from i128 to u128 through felt252
        let k_plus_1 = k + BPS_i128;
        assert(k_plus_1 > 0, 'Strike price must be > 0');

        let k_plus_1 = Into::<i128, felt252>::into(k_plus_1)
            .try_into()
            .expect('k_plus_1 felt252 -> u128 failed');

        // @dev cl = λ − k / (α × (k + 1))
        let numerator: u128 = lambda_minus_k;
        let denominator: u128 = a * k_plus_1;

        // @dev (λ - k) is BPS - BPS, (a * (k + 1)) is BPS * BPS, so multip
        (BPS_u128 * BPS_u128 * numerator / denominator)
    }
}

// Calculate a round's strike price `K = (1 + k)BF`
// @param twap: the current TWAP of the basefee
// @param k: the strike level
// @note The minimum strike_level of -9999 translates to a strike price -99.99% the current twap
// (-10_000 would mean a strike price == 0)
fn calculate_strike_price(k: i128, twap: u256) -> u256 {
    let k_plus_1: i128 = k + BPS_i128;
    assert(k_plus_1 > 0, 'Strike price must be > 0');

    // @dev Cast k+1 from i128 to u256 (k is positive here)
    let k_plus_1: u256 = Into::<i128, felt252>::into(k_plus_1).into();

    (k_plus_1 * twap) / BPS_u256
}
