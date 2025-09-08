use pitch_lake::library::pricing_utils;

#[test]
fn test_max_payout_per_option() {
    // Test normal cases
    let strike_100 = 100_u256;
    let cap_10000 = 10000_u128; // 100%
    assert_eq!(pricing_utils::max_payout_per_option(strike_100, cap_10000), 100);

    // Test with larger numbers
    let strike_1e18 = 1_000_000_000_000_000_000_u256;
    let cap_5000 = 5000_u128; // 50%
    assert_eq!(
        pricing_utils::max_payout_per_option(strike_1e18, cap_5000), 500_000_000_000_000_000_u256
    );

    // Test with small cap
    let cap_1 = 1_u128; // 0.01%
    assert_eq!(pricing_utils::max_payout_per_option(strike_1e18, cap_1), 100_000_000_000_000);

    // Test with zero cap
    let cap_0 = 0_u128;
    assert_eq!(pricing_utils::max_payout_per_option(strike_100, cap_0), 0);
}

#[test]
fn test_calculate_payout_per_option() {
    let strike_100 = 100_u256;
    let cap_15000 = 15000_u128; // 150%

    // Test when settlement price is below strike (should be 0)
    assert_eq!(pricing_utils::calculate_payout_per_option(strike_100, cap_15000, 90), 0);
    assert_eq!(pricing_utils::calculate_payout_per_option(strike_100, cap_15000, 100), 0);

    // Test when settlement price is above strike but below cap
    assert_eq!(pricing_utils::calculate_payout_per_option(strike_100, cap_15000, 120), 20);
    assert_eq!(pricing_utils::calculate_payout_per_option(strike_100, cap_15000, 200), 100);

    // Test when settlement price is above cap
    assert_eq!(pricing_utils::calculate_payout_per_option(strike_100, cap_15000, 300), 150);
    assert_eq!(pricing_utils::calculate_payout_per_option(strike_100, cap_15000, 1000), 150);

    // Test with zero cap
    assert_eq!(pricing_utils::calculate_payout_per_option(strike_100, 0, 200), 0);
}

#[test]
fn test_calculate_total_options_available() {
    let starting_liquidity = 1000_u256;
    let strike_100 = 100_u256;

    // Test normal case
    let cap_10000 = 10000_u128; // 100%
    assert_eq!(
        pricing_utils::calculate_total_options_available(starting_liquidity, strike_100, cap_10000),
        10
    );

    // Test with zero cap (should return 0)
    assert_eq!(
        pricing_utils::calculate_total_options_available(starting_liquidity, strike_100, 0), 0
    );

    // Test with large liquidity and small cap
    let large_liquidity = 1_000_000_000_000_000_000_u256;
    let small_cap = 100_u128; // 1%
    assert_eq!(
        pricing_utils::calculate_total_options_available(large_liquidity, strike_100, small_cap),
        1_000_000_000_000_000_000_u256
    );

    // Test with large liquidity and very small cap
    let large_liquidity = 1_000_000_000_000_000_000_u256;
    let small_cap = 100_u128; // 1%
    assert_eq!(
        pricing_utils::calculate_total_options_available(large_liquidity, strike_100, small_cap),
        1_000_000_000_000_000_000_u256
    );

    // Test with zero liquidity
    assert_eq!(pricing_utils::calculate_total_options_available(0, strike_100, cap_10000), 0);
}

#[test]
fn test_calculate_strike_price_edge_cases() {
    let twap = 10_000_u256;

    // Test minimum viable k (-9999)
    let min_k = -9999_i128;
    assert_eq!(pricing_utils::calculate_strike_price(min_k, twap), 1);

    // Test maximum reasonable k (100000 = 1000%)
    let max_k = 100_000_i128;
    assert_eq!(pricing_utils::calculate_strike_price(max_k, twap), 110_000);

    // Test with very large TWAP
    let large_twap = 1_000_000_000_000_000_000_u256;
    let normal_k = 1_000_i128; // 10%
    assert_eq!(
        pricing_utils::calculate_strike_price(normal_k, large_twap), 1_100_000_000_000_000_000
    );

    // Test with small TWAP
    let small_twap = 1_u256;
    assert_eq!(pricing_utils::calculate_strike_price(0_i128, small_twap), 1);
}

#[test]
#[should_panic]
fn test_calculate_strike_price_invalid_k() {
    let twap = 100_u256;
    let k: i128 = -10000;
    assert_eq!(pricing_utils::calculate_strike_price(k, twap), 0);
    assert_eq!(pricing_utils::calculate_strike_price(k - 1, twap), 0);
}
