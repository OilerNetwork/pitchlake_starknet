use starknet::{ContractAddress, contract_address_const};

fn decimals() -> u256 {
    //10  ** 18
    1000000000000000000
}

fn minute_duration() -> u64 {
    60
}

fn hour_duration() -> u64 {
    60 * minute_duration()
}

fn day_duration() -> u64 {
    24 * hour_duration()
}

fn week_duration() -> u64 {
    7 * day_duration()
}

fn month_duration() -> u64 {
    30 * day_duration()
}

fn zero_address() -> ContractAddress {
    contract_address_const::<0>()
}

fn bps() -> u256 {
    10000
}
