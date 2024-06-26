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