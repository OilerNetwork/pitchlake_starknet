use pitch_lake::vault::interface::VaultType;
use pitch_lake::library::utils::min;
use pitch_lake::types::Consts::BPS;

// Calculate the maximum payout for a single option
fn max_payout_per_option(strike_price: u256, cap_level: u128) -> u256 {
    (strike_price * cap_level.into()) / BPS
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
fn calculate_cap_level(alpha: u128, volatility: u128) -> u128 {
    volatility
}

// Calculate a round's strike price
// @note strike_level is out of bps
// e.g.strike_level of -12.34% is 10_000 - 1234 = 8766 (bps)
// e.g.strike_level of +56.78% is 10_000 + 5678 = 15,678 (bps)
fn calculate_strike_price(strike_level: u128, twap: u256) -> u256 {
    (twap * strike_level.into()) / BPS.into()
}

fn calculate_strike_price_old(vault_type: VaultType, twap: u256, volatility: u128) -> u256 {
    let adjustment = (twap * volatility.into()) / BPS;
    match vault_type {
        VaultType::AtTheMoney(_) => twap,
        VaultType::OutOfMoney(_) => twap + adjustment,
        VaultType::InTheMoney(_) => {
            if adjustment >= twap {
                twap / 2
            } else {
                twap - adjustment
            }
        },
    }
}
