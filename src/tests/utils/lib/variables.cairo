use starknet::ContractAddress;

pub fn decimals() -> u256 {
    //10  ** 18
    1000000000000000000
}

pub fn minute_duration() -> u64 {
    60
}

pub fn hour_duration() -> u64 {
    60 * minute_duration()
}

pub fn day_duration() -> u64 {
    24 * hour_duration()
}

pub fn week_duration() -> u64 {
    7 * day_duration()
}

pub fn month_duration() -> u64 {
    30 * day_duration()
}

pub fn zero_address() -> ContractAddress {
    0.try_into().unwrap()
}

pub fn bps() -> u256 {
    10000
}
