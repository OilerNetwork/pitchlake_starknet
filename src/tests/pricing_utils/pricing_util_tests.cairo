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
fn test_cap_level_against_python_outputs() {
    // Test with max_returns = 20349 (203.49%)
    let max_returns: u128 = 20349;

    // Test k = -7500 (-75%) with different alpha values
    assert_eq!(
        pricing_utils::calculate_cap_level(max_returns, -7500, 1000), 1_113_960
    ); // alpha = 10%
    assert_eq!(
        pricing_utils::calculate_cap_level(max_returns, -7500, 2500), 445_584
    ); // alpha = 25%
    assert_eq!(
        pricing_utils::calculate_cap_level(max_returns, -7500, 5000), 222_792
    ); // alpha = 50%
    assert_eq!(
        pricing_utils::calculate_cap_level(max_returns, -7500, 7500), 148_528
    ); // alpha = 75%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, -7500, 10000), 111_396);

    // Test k = -5000 (-50%) with different alpha values
    assert_eq!(
        pricing_utils::calculate_cap_level(max_returns, -5000, 1000), 506_980
    ); // alpha = 10%
    assert_eq!(
        pricing_utils::calculate_cap_level(max_returns, -5000, 2500), 202_792
    ); // alpha = 25%
    assert_eq!(
        pricing_utils::calculate_cap_level(max_returns, -5000, 5000), 101_396
    ); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, -5000, 7500), 67_597); // alpha = 75%
    assert_eq!(
        pricing_utils::calculate_cap_level(max_returns, -5000, 10000), 50_698
    ); // alpha = 100%

    // Test k = -2500 (-25%) with different alpha values
    assert_eq!(
        pricing_utils::calculate_cap_level(max_returns, -2500, 1000), 304_653
    ); // alpha = 10%
    assert_eq!(
        pricing_utils::calculate_cap_level(max_returns, -2500, 2500), 121_861
    ); // alpha = 25%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, -2500, 5000), 60_930); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, -2500, 7500), 40_620); // alpha = 75%
    assert_eq!(
        pricing_utils::calculate_cap_level(max_returns, -2500, 10000), 30_465
    ); // alpha = 100%

    // Test k = 0 (ATM) with different alpha values
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 0, 1000), 203_490); // alpha = 10%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 0, 2500), 81_396); // alpha = 25%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 0, 5000), 40_698); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 0, 7500), 27_132); // alpha = 75%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 0, 10000), 20_349); // alpha = 100%

    // Test k = 2500 (25%) with different alpha values
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 2500, 1000), 142_792); // alpha = 10%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 2500, 2500), 57_116); // alpha = 25%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 2500, 5000), 28_558); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 2500, 7500), 19_038); // alpha = 75%
    assert_eq!(
        pricing_utils::calculate_cap_level(max_returns, 2500, 10000), 14_279
    ); // alpha = 100%

    // Test k = 5000 (50%) with different alpha values
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 5000, 1000), 102_326); // alpha = 10%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 5000, 2500), 40_930); // alpha = 25%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 5000, 5000), 20_465); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 5000, 7500), 13_643); // alpha = 75%
    assert_eq!(
        pricing_utils::calculate_cap_level(max_returns, 5000, 10000), 10_232
    ); // alpha = 100%

    // Test k = 7500 (75%) with different alpha values
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 7500, 1000), 73_422); // alpha = 10%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 7500, 2500), 29_369); // alpha = 25%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 7500, 5000), 14_684); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 7500, 7500), 9789); // alpha = 75%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 7500, 10000), 7342); // alpha = 100%

    // Test k = 10000 (100%) with different alpha values
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 10000, 1000), 51_745); // alpha = 10%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 10000, 2500), 20_698); // alpha = 25%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 10000, 5000), 10_349); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 10000, 7500), 6899); // alpha = 75%
    assert_eq!(pricing_utils::calculate_cap_level(max_returns, 10000, 10000), 5174); // alpha = 100%
}

#[test]
fn test_cap_level_edge_cases() {
    // Test when alpha is 0
    let cap_level = pricing_utils::calculate_cap_level(20000, 0, 0);
    assert(cap_level == 1, 'alpha 0 should return 0');

    // Test when max_returns <= k
    let cap_level = pricing_utils::calculate_cap_level(1000, 2000, 2500);
    assert(cap_level == 1, 'max_returns <= k should be 0');

    // Test when k + 1 <= 0 (k = -10000 means -100%)
    let cap_level = pricing_utils::calculate_cap_level(20000, -10001, 2500);
    assert(cap_level == 1, 'k+1 <= 0 should return 0');

    // Test normal cases
    let cap_level = pricing_utils::calculate_cap_level(20000, 0, 2500); // ATM
    assert(cap_level > 1, 'ATM cap level should be > 0');

    let cap_level_itm = pricing_utils::calculate_cap_level(20000, -1000, 2500); // ITM (-10%)
    assert(cap_level_itm > 1, 'ITM cap level should be > 0');

    let cap_level_otm = pricing_utils::calculate_cap_level(20000, 1000, 2500); // OTM (+10%)
    assert(cap_level_otm > 1, 'OTM cap level should be > 0');
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
fn test_calculate_strike_price_invalid_k() {
    let twap = 100_u256;
    let k: i128 = -10000;
    assert_eq!(pricing_utils::calculate_strike_price(k, twap), 0);
    assert_eq!(pricing_utils::calculate_strike_price(k - 1, twap), 0);
}
