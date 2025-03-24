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

// Calculate cap level using max returns, alpha, and k
// `cl = (max_returns - k) / (alpha * (1 + k))`
// @param max_returns: maximum returns in BPS (e.g., 20349 for 203.49%)
// @param k: strike level in BPS (e.g., 0 for ATM, -2500 for -25%)
// @param alpha: target percentage of max returns in BPS (e.g., 2500 for 25%)
fn calculate_cap_level(max_returns: u128, k: i128, alpha: u128) -> u128 {
    let max_returns_minus_k: i128 = (max_returns.try_into().unwrap()) - k;
    let k_plus_one = BPS_i128 + k;

    // Avoid division by zero, clamp to 1
    if (alpha == 0 || k_plus_one <= 0) {
        return 1;
    }

    // If (max_returns - k) is negative => clamp to 1
    if max_returns_minus_k <= 0 {
        return 1;
    }

    let alpha_i128: i128 = alpha.try_into().unwrap();
    let cl = (max_returns_minus_k * BPS_i128 * BPS_i128) / (alpha_i128 * k_plus_one);

    return cl.try_into().unwrap();
}


// Calculate a round's strike price `K = (1 + k)TWAP`
// @param twap: the current TWAP of the basefee
// @param k: the strike level
// @note The minimum strike_level of -9999 translates to a strike price -99.99% the current twap
// (-10_000 would mean a strike price == 0)
fn calculate_strike_price(k: i128, twap: u256) -> u256 {
    let k_plus_one_i128: i128 = k + BPS_i128;

    if k_plus_one_i128 <= 0 {
        // @dev k+1 should never be 0 or less => clamp to 0.
        return 0;
    }

    // @dev Cast k+1 from i128 to felt252 to u256 (k is positive here)
    let k_plus_one_u256: u256 = Into::<i128, felt252>::into(k_plus_one_i128).into();

    (k_plus_one_u256 * twap) / BPS_u256
}
