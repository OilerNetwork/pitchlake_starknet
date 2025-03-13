use core::num::traits::Zero;
use pitch_lake::vault::interface::VaultType;
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

// Calculate cap level using max returns
// - `max_returns * 1.2`
// - result is a percentage (BPS) that is >= 0
fn calculate_cap_level(max_returns: u128) -> u128 {
    if max_returns > 0 {
        (120 * max_returns) / 100
    } else {
        1
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
