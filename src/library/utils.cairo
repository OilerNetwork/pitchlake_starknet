use pitch_lake_starknet::types::{Consts::{BPS, PRECISION}};

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

// Compute x / y with added precision
fn divide_with_precision<T, +Into<u256, T>, +Mul<T>, +Div<T>, +Drop<T>, +Copy<T>>(x: T, y: T) -> T {
    let p = PRECISION.into();
    (x * p) / (y * p)
}

