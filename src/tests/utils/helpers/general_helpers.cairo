use openzeppelin_token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use starknet::ContractAddress;

/// Array helpers ///

pub fn to_gwei(value: u256) -> u256 {
    value * 1_000_000_000
}

// Create array of length `len`, each element is `amount` (For bids use the function twice for price
// and amount)
pub fn create_array_linear<T, +Drop<T>, +Copy<T>>(amount: T, len: u32) -> Array<T> {
    let mut arr = array![];
    let mut index = 0;
    while (index < len) {
        arr.append(amount);
        index += 1;
    }
    arr
}

// Create array of length `len`, each element is `amount + index * step` (For bids use the function
// twice for price and amount)
pub fn create_array_gradient(amount: u256, step: u256, len: u32) -> Array<u256> {
    let mut arr: Array<u256> = array![];
    let mut index: u32 = 0;
    while (index < len) {
        arr.append(amount + index.into() * step);
        index += 1;
    }
    arr
}

// Create array of length `len`, each element is `amount - index * step` (For bids use the function
// twice for price and amount)
pub fn create_array_gradient_reverse(amount: u256, step: u256, len: u32) -> Array<u256> {
    let mut arr: Array<u256> = array![];
    let mut index: u32 = 0;
    while (index < len) {
        arr.append(amount - index.into() * step);
        index += 1;
    }
    arr
}

// Sum all of the u256s in a given span
pub fn sum_u256_array(mut arr: Span<u256>) -> u256 {
    let mut sum = 0;
    for el in arr {
        sum += *el;
    }
    //  loop {
    //      match arr.pop_front() {
    //          Option::Some(el) => { sum += *el; },
    //          Option::None => { break; },
    //      }
    //  }
    sum
}

// Sum the total amount paid for multiple bids.
pub fn get_total_bids_amount(mut bid_prices: Span<u256>, mut bid_amounts: Span<u256>) -> u256 {
    assert_two_arrays_equal_length(bid_prices, bid_amounts);
    let mut sum = 0;
    for i in 0..bid_prices.len() {
        sum += *bid_prices[i] * *bid_amounts[i];
    }
    //    loop {
    //        match bid_prices.pop_front() {
    //            Option::Some(bid_price) => {
    //                let bid_amount = bid_amounts.pop_front().unwrap();
    //                sum += *bid_amount * *bid_price;
    //            },
    //            Option::None => { break (); },
    //        }
    //    }
    sum
}

// Assert two arrays of any type are equal
pub fn assert_two_arrays_equal_length<T, V>(arr1: Span<T>, arr2: Span<V>) {
    assert(arr1.len() == arr2.len(), 'Arrays not equal length');
}

// Multiply each element in an array by a scalar
pub fn scale_array<T, +Drop<T>, +Copy<T>, +Mul<T>>(mut arr: Span<T>, scalar: T) -> Array<T> {
    let mut scaled: Array<T> = array![];
    for el in arr {
        scaled.append(*el * scalar);
    }
    //loop {
    //    match arr.pop_front() {
    //        Option::Some(el) => { scaled.append(*el * scalar); },
    //        Option::None => { break (); },
    //    }
    //}
    scaled
}

// Multiply each element in an array by the corresponding element in another array
pub fn multiply_arrays<T, +Drop<T>, +Copy<T>, +Mul<T>>(
    mut arr1: Span<T>, mut arr2: Span<T>,
) -> Array<T> {
    assert_two_arrays_equal_length(arr1, arr2);
    let mut multiplied: Array<T> = array![];
    for i in 0..arr1.len() {
        multiplied.append(*arr1[i] * *arr2[i]);
    }
    // loop {
    //     match arr1.pop_front() {
    //         Option::Some(el1) => {
    //             let el2 = arr2.pop_front().unwrap();
    //             multiplied.append(*el1 * *el2);
    //         },
    //         Option::None => { break (); },
    //     }
    // }
    multiplied
}
// Make an array from a span
pub fn span_to_array<T, +Drop<T>, +Copy<T>>(mut span: Span<T>) -> Array<T> {
    let mut arr = array![];
    for el in span {
        arr.append(*el);
    }
    //loop {
    //    match span.pop_front() {
    //        Option::Some(el) => { arr.append(*el); },
    //        Option::None => { break (); },
    //    }
    //}
    arr
}

pub fn pow(base: u256, exp: u256) -> u256 {
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

pub fn to_wei(value: u256, decimals: u8) -> u256 {
    value * (pow(10, decimals.into()))
}

pub fn to_wei_multi(mut values: Span<u256>, mut decimals: u8) -> Span<u256> {
    let mut arr_res = array![];

    for value in values {
        arr_res.append(to_wei(*value, decimals.into()));
    }

    //    loop {
    //        match values.pop_front() {
    //            Option::Some(value) => { arr_res.append(to_wei(*value, decimals.into())); },
    //            Option::None => { break; },
    //        }
    //}

    arr_res.span()
}


/// ERC20 Helpers ///

// Get erc20 balances for an address
pub fn get_erc20_balance(
    contract_address: ContractAddress, account_address: ContractAddress,
) -> u256 {
    let contract = ERC20ABIDispatcher { contract_address };
    contract.balance_of(account_address)
}

// Get erc20 balances for multiple addresses
pub fn get_erc20_balances(
    contract_address: ContractAddress, mut account_addresses: Span<ContractAddress>,
) -> Array<u256> {
    let mut balances = array![];
    for addr in account_addresses {
        balances.append(get_erc20_balance(contract_address, *addr));
    }
    //    loop {
    //        match account_addresses.pop_front() {
    //            Option::Some(addr) => { balances.append(get_erc20_balance(contract_address,
    //            *addr)); }, Option::None => { break (); },
    //        }
    //    }
    balances
}

// Return each elements portion of the 'amount' corresponding to the total of the array
// @dev Scaling with bps for precision
// @dev Used to determine how many premiums and payouts belong to an account
pub fn get_portion_of_amount(mut arr: Span<u256>, amount: u256) -> Array<u256> {
    let total = sum_u256_array(arr);
    let mut portions = array![];
    for value in arr {
        let portion = (*value * amount) / total;
        portions.append(portion);
    }
    //loop {
    //    match arr.pop_front() {
    //        Option::Some(value) => {
    //            let portion = (*value * amount) / total;
    //            portions.append(portion);
    //        },
    //        Option::None => { break (); },
    //    }
    //}
    portions
}

pub fn assert_u256s_equal_in_range(value1: u256, value2: u256, range: u256) {
    let lower_bound = if range > value2 {
        0
    } else {
        value2 - range
    };
    assert(value1 >= lower_bound, 'Value below range');
    assert(value1 <= value2 + range, 'Value above range');
}

