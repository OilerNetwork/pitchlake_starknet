use pitch_lake::vault::interface::VaultType;
use pitch_lake::library::utils::min;
use pitch_lake::types::Consts::BPS;

// @note TODO
fn calculate_cap_level(alpha: u128, volatility: u128) -> u128 {
    volatility
}

// @dev Calculate the maximum payout for a single option
fn max_payout_per_option(strike_price: u256, cap_level: u128) -> u256 {
    (strike_price * cap_level.into()) / BPS
}

// @dev Calculate the actual payout for a single option
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
// Calculate a round's strike price
// @param vault_type: The type of the vault
// @param twap: The TWAP of the basefee for the last 2 weeks
// @param volatility: The volatility of the basefee for the last 2 weeks
// @return The strike price of the upcoming round
fn calculate_strike_price(vault_type: VaultType, twap: u256, volatility: u128) -> u256 {
    let adjustment = (twap * volatility.into()) / BPS;
    match vault_type {
        VaultType::AtTheMoney(_) => twap,
        VaultType::OutOfMoney(_) => twap + adjustment,
        VaultType::InTheMoney(_) => {
            // @note 0 ensures payout for round, need to decide if we should use ATM price,
            // or scale the adjustment to keep ITM nature but not a 0 strike
            if adjustment >= twap {
                twap / 2
            } else {
                twap - adjustment
            }
        },
    }
}

