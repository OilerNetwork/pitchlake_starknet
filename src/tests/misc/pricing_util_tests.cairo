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
    // Test with max_returns = 5431 (54.31%)
    let vol: u128 = 5431;
    let min_cap: u128 = 0;

    // Test k = -7500 (-75%) with different alpha values
    let k = -7500;
    assert_eq!(pricing_utils::calculate_cap_level(1000, k, vol, min_cap), 806169); // alpha = 10%
    assert_eq!(pricing_utils::calculate_cap_level(2500, k, vol, min_cap), 322467); // alpha = 25%
    assert_eq!(pricing_utils::calculate_cap_level(5000, k, vol, min_cap), 161233); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(7500, k, vol, min_cap), 107489); // alpha = 75%
    assert_eq!(pricing_utils::calculate_cap_level(10000, k, vol, min_cap), 80616); // alpha = 100%

    // Test k = -5000 (-50%) with different alpha values
    let k = -5000;
    assert_eq!(pricing_utils::calculate_cap_level(1000, k, vol, min_cap), 353084); // alpha = 10%
    assert_eq!(pricing_utils::calculate_cap_level(2500, k, vol, min_cap), 141233); // alpha = 25%
    assert_eq!(pricing_utils::calculate_cap_level(5000, k, vol, min_cap), 70616); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(7500, k, vol, min_cap), 47077); // alpha = 75%
    assert_eq!(pricing_utils::calculate_cap_level(10000, k, vol, min_cap), 35308); // alpha = 100%

    // Test k = -2500 (-25%) with different alpha values
    let k = -2500;
    assert_eq!(pricing_utils::calculate_cap_level(1000, k, vol, min_cap), 202056); // alpha = 10%
    assert_eq!(pricing_utils::calculate_cap_level(2500, k, vol, min_cap), 80822); // alpha = 25%
    assert_eq!(pricing_utils::calculate_cap_level(5000, k, vol, min_cap), 40411); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(7500, k, vol, min_cap), 26940); // alpha = 75%
    assert_eq!(pricing_utils::calculate_cap_level(10000, k, vol, min_cap), 20205); // alpha = 100%

    // Test k = 0 (0%) with different alpha values
    let k = 0;
    assert_eq!(pricing_utils::calculate_cap_level(1000, k, vol, min_cap), 126542); // alpha = 10%
    assert_eq!(pricing_utils::calculate_cap_level(2500, k, vol, min_cap), 50616); // alpha = 25%
    assert_eq!(pricing_utils::calculate_cap_level(5000, k, vol, min_cap), 25308); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(7500, k, vol, min_cap), 16872); // alpha = 75%
    assert_eq!(pricing_utils::calculate_cap_level(10000, k, vol, min_cap), 12654); // alpha = 100%

    // Test k = 2500 (25%) with different alpha values
    let k = 2500;
    assert_eq!(pricing_utils::calculate_cap_level(1000, k, vol, min_cap), 81233); // alpha = 10%
    assert_eq!(pricing_utils::calculate_cap_level(2500, k, vol, min_cap), 32493); // alpha = 25%
    assert_eq!(pricing_utils::calculate_cap_level(5000, k, vol, min_cap), 16246); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(7500, k, vol, min_cap), 10831); // alpha = 75%
    assert_eq!(pricing_utils::calculate_cap_level(10000, k, vol, min_cap), 8123); // alpha = 100%

    // Test k = 5000 (50%) with different alpha values
    let k = 5000;
    assert_eq!(pricing_utils::calculate_cap_level(1000, k, vol, min_cap), 51028); // alpha = 10%
    assert_eq!(pricing_utils::calculate_cap_level(2500, k, vol, min_cap), 20411); // alpha = 25%
    assert_eq!(pricing_utils::calculate_cap_level(5000, k, vol, min_cap), 10205); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(7500, k, vol, min_cap), 6803); // alpha = 75%
    assert_eq!(pricing_utils::calculate_cap_level(10000, k, vol, min_cap), 5102); // alpha = 100%

    // Test k = 7500 (75%) with different alpha values
    let k = 7500;
    assert_eq!(pricing_utils::calculate_cap_level(1000, k, vol, min_cap), 29452); // alpha = 10%
    assert_eq!(pricing_utils::calculate_cap_level(2500, k, vol, min_cap), 11781); // alpha = 25%
    assert_eq!(pricing_utils::calculate_cap_level(5000, k, vol, min_cap), 5890); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(7500, k, vol, min_cap), 3927); // alpha = 75%
    assert_eq!(pricing_utils::calculate_cap_level(10000, k, vol, min_cap), 2945); // alpha = 100%

    // Test k = 10_000 (100%) with different alpha values
    let k = 10_000;
    assert_eq!(pricing_utils::calculate_cap_level(1000, k, vol, min_cap), 13271); // alpha = 10%
    assert_eq!(pricing_utils::calculate_cap_level(2500, k, vol, min_cap), 5308); // alpha = 25%
    assert_eq!(pricing_utils::calculate_cap_level(5000, k, vol, min_cap), 2654); // alpha = 50%
    assert_eq!(pricing_utils::calculate_cap_level(7500, k, vol, min_cap), 1769); // alpha = 75%
    assert_eq!(pricing_utils::calculate_cap_level(10000, k, vol, min_cap), 1327); // alpha = 100%
}

#[test]
fn test_cap_level_edge_cases() {
    let min_cap = 0;
    // Test when alpha is 0
    let cap_level = pricing_utils::calculate_cap_level(0, 0, 20000, min_cap);
    assert(cap_level == min_cap, 'alpha 0 should return min');

    // Test when 2.33 x vol <= k
    let cap_level = pricing_utils::calculate_cap_level(1000, 5000, 2000, min_cap);
    assert(cap_level == min_cap, 'max_returns <= k shd return min');

    // Test when k + 1 <= 0 (k = -10000 means -100%)
    let cap_level = pricing_utils::calculate_cap_level(2500, -10001, 20000, min_cap);
    assert(cap_level == min_cap, 'k+1 <= 0 should return min');

    // Test normal cases
    let cap_level = pricing_utils::calculate_cap_level(2500, 0, 20000, min_cap); // ATM
    assert(cap_level > min_cap, 'ATM cap level should be > 0');

    let cap_level_itm = pricing_utils::calculate_cap_level(
        2500, -1000, 20000, min_cap
    ); // ITM (-10%)
    assert(cap_level_itm > min_cap, 'ITM cap level should be > 0');

    let cap_level_otm = pricing_utils::calculate_cap_level(
        2500, 1000, 20000, min_cap
    ); // OTM (+10%)
    assert(cap_level_otm > min_cap, 'OTM cap level should be > 0');
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
