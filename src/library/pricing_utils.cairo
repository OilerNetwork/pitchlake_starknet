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

// Calculate cap level using volatility, alpha, k, and minimum cap level
// @param volatility: volatility of returns in BPs (e.g., 3333 for 33.33%)
// @param k: strike level in BPS (e.g., -2500 for -25%)
// @param alpha: target percentage of max returns in BPS (e.g., 5000 for 50%)
// @param minimum_cap_level: minimum cap level in BPS (e.g., 1000 for 10%)
//
// cl = max[min_cl, (λ - k) / (α * (1 + k))]
// - min_cl: 0% <= min_cl < ∞%
// - λ = 2.33 x volatility: 0% <= λ < ∞%
// - k: -100.00% < k < ∞%
// - a: 0.00% < a <= 100%
fn calculate_cap_level(alpha: u128, k: i128, volatility: u128, minimum_cap_level: u128) -> u128 {
    // @dev Max values for i128 and u128 (+100_000_000%)
    let max_i128: i128 = 1_000_000 * BPS_i128;
    let max_u128: u128 = 1_000_000 * BPS_u128;

    // @dev Cast alpha to i128
    // - a: 0.00% < a <= 100%
    let alpha: i128 = min(BPS_i128, alpha.try_into().unwrap_or(BPS_i128));

    // @dev Cast minimum_cap_level to i128
    // - cl: 0% <= cl < ∞%
    let minimum_cap_level_i128 = minimum_cap_level.try_into().unwrap_or(max_i128);

    // @dev Cast volatility to i128
    // - volatility: 0% <= volatility < ∞%
    let vol_i128: i128 = volatility.try_into().unwrap_or(max_i128);

    // @dev Calculate the cap level as BPs
    let scalar = BPS_i128 * BPS_i128;
    // @dev λ = 2.33 x volatility
    let numerator = ((233 * vol_i128) - (100 * k));
    let denominator = 100 * (alpha * (k + BPS_i128));

    // @dev Avoid division by zero
    if denominator == 0 {
        return minimum_cap_level;
    }

    // @dev Return max(minimum_cap_level, cap_level)
    let cap_level = (scalar * numerator) / denominator;

    if cap_level < minimum_cap_level_i128 {
        return minimum_cap_level;
    } else {
        return cap_level.try_into().unwrap_or(max_u128);
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
