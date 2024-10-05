use core::poseidon::poseidon_hash_span;
use pitch_lake::vault::interface::L1DataRequest;

pub const VALUES_NOT_IN_RANGE: felt252 = 'Values not in range';

fn assert_equal_in_range<T, +PartialOrd<T>, +Add<T>, +Sub<T>, +Drop<T>, +Copy<T>>(
    a: T, b: T, range: T
) {
    assert(a >= b - range && a <= b + range, VALUES_NOT_IN_RANGE);
}

// @dev Returns the minimum of a and b
fn min<T, +PartialEq<T>, +PartialOrd<T>, +Drop<T>, +Copy<T>>(a: T, b: T) -> T {
    match a < b {
        true => a,
        false => b
    }
}

// @dev Returns the maximum of a and b
fn max<T, +PartialEq<T>, +PartialOrd<T>, +Drop<T>, +Copy<T>>(a: T, b: T) -> T {
    match a < b {
        true => b,
        false => a
    }
}

// @dev Returns base^exp
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

// @dev Serialize the job request and hash it to create the its ID
fn generate_request_id(request: L1DataRequest) -> felt252 {
    let mut serialized: Array<felt252> = Default::default();
    request.serialize(ref serialized);
    poseidon_hash_span(serialized.span())
}

