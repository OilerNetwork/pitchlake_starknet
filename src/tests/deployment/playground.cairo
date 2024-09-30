use pitch_lake::library::pricing_utils::{
    max_payout_per_option, calculate_payout_per_option, calculate_total_options_available,
    calculate_cap_level, calculate_strike_price
};


#[test]
#[available_gas(50000000)]
fn playground_test_1() {
    let cap_level = calculate_cap_level(1, 1000);
    println!("\ncap level: {}\n", cap_level)
}
