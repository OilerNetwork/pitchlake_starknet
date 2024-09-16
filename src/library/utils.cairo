use pitch_lake_starknet::types::{VaultType, Consts::BPS};

fn min<T, +PartialEq<T>, +PartialOrd<T>, +Drop<T>, +Copy<T>>(a: T, b: T) -> T {
    match a < b {
        true => a,
        false => b
    }
}

// Get the maximum of two values
fn max<T, +PartialEq<T>, +PartialOrd<T>, +Drop<T>, +Copy<T>>(a: T, b: T) -> T {
    match a < b {
        true => b,
        false => a
    }
}

// Raise x to the y power
fn pow(base: u256, exp: u8) -> u256 {
    if exp == 0 {
        1
    } else if exp == 1 {
        base
    } else if exp % 2 == 0 {
        pow(base * base, exp / 2)
    } else {
        base * pow(base * base, exp / 2)
    }
}

// Calculate a round's strike price
// @param vault_type: The type of the vault
// @param avg_basefee: The TWAP of the basefee for the last 2 weeks
// @param volatility: The volatility of the basefee for the last 2 weeks
// @return The strike price of the upcoming round
fn calculate_strike_price(vault_type: VaultType, avg_basefee: u256, volatility: u128) -> u256 {
    let adjustment = (avg_basefee * volatility.into()) / BPS;
    match vault_type {
        VaultType::AtTheMoney(_) => avg_basefee,
        VaultType::OutOfMoney(_) => avg_basefee + adjustment,
        VaultType::InTheMoney(_) => {
            // @note 0 ensures payout for round, need to decide if we should use ATM price,
            // or scale the adjustment to keep ITM nature but not a 0 strike
            if adjustment >= avg_basefee {
                avg_basefee
            } else {
                avg_basefee - adjustment
            }
        },
    }
}

