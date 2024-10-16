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

// @note TODO
fn calculate_cap_level(a: u128, k: i128, vol: u128) -> u128 {
    let lambda: i128 = 233 * vol.try_into().unwrap() / 100; // 2.33 * vol
    if k >= lambda {
        1
    } else {
        let a: u128 = a.try_into().unwrap();
        let k: u128 = k.try_into().unwrap();
        let lambda: u128 = lambda.try_into().unwrap();

        // cl = λ − k / (α × (1.0000 + k))
        let numerator: u128 = (lambda - k);
        let denominator: u128 = (a * (k + BPS_u128)) / BPS_u128;

        (BPS_u128 * numerator / denominator)
    }
}

// Calculate a round's strike price
// @note strike_level is in BPS > -10,000
// e.g. a strike_level of -12.34% is -1234 BPS; therefore, k + 1 is -1234 + 10_000 = 8766
fn calculate_strike_price(k: i128, twap: u256) -> u256 {
    assert(k >= -BPS_i128, 'Strike level must be >= -10,000');

    // @dev Cast k from i128 to u256
    let k_plus_1_felt252: felt252 = (k + BPS_i128).into();
    let k_plus_1_u256: u256 = k_plus_1_felt252.into();

    (twap * k_plus_1_u256) / BPS_u256
}
