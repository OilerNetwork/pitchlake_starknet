use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait,};
use starknet::{ContractAddress};

/// Array helpers ///

// Create array of length `len`, each element is `amount` (For bids use the function twice for price and amount)
fn create_array_linear<T, +Drop<T>, +Copy<T>>(amount: T, len: u32) -> Array<T> {
    let mut arr = array![];
    let mut index = 0;
    while (index < len) {
        arr.append(amount);
        index += 1;
    };
    arr
}

// Create array of length `len`, each element is `amount + index * step` (For bids use the function twice for price and amount)
fn create_array_gradient(amount: u256, step: u256, len: u32) -> Array<u256> {
    let mut arr: Array<u256> = array![];
    let mut index: u32 = 0;
    while (index < len) {
        arr.append(amount + index.into() * step);
        index += 1;
    };
    arr
}

// Create array of length `len`, each element is `amount - index * step` (For bids use the function twice for price and amount)
fn create_array_gradient_reverse(amount: u256, step: u256, len: u32) -> Array<u256> {
    let mut arr: Array<u256> = array![];
    let mut index: u32 = 0;
    while (index < len) {
        arr.append(amount - index.into() * step);
        index += 1;
    };
    arr
}

// Sum all of the u256s in a given span
fn sum_u256_array(mut arr: Span<u256>) -> u256 {
    let mut sum = 0;
    loop {
        match arr.pop_front() {
            Option::Some(el) => { sum += *el; },
            Option::None => { break; }
        }
    };
    sum
}

// Sum the total amount paid for multiple bids.
fn get_total_bids_amount(mut bid_prices: Span<u256>, mut bid_amounts: Span<u256>) -> u256 {
    assert_two_arrays_equal_length(bid_prices, bid_amounts);
    let mut sum = 0;
    loop {
        match bid_prices.pop_front() {
            Option::Some(bid_price) => {
                let bid_amount = bid_amounts.pop_front().unwrap();
                sum += *bid_amount * *bid_price;
            },
            Option::None => { break (); }
        }
    };
    sum
}

// Assert two arrays of any type are equal
fn assert_two_arrays_equal_length<T, V>(arr1: Span<T>, arr2: Span<V>) {
    assert(arr1.len() == arr2.len(), 'Arrays not equal length');
}

// Multiply each element in an array by a scalar
fn scale_array<T, +Drop<T>, +Copy<T>, +Mul<T>>(mut arr: Span<T>, scalar: T) -> Array<T> {
    let mut scaled: Array<T> = array![];
    loop {
        match arr.pop_front() {
            Option::Some(el) => { scaled.append(*el * scalar); },
            Option::None => { break (); }
        }
    };
    scaled
}

// Multiply each element in an array by the corresponding element in another array
fn multiply_arrays<T, +Drop<T>, +Copy<T>, +Mul<T>>(
    mut arr1: Span<T>, mut arr2: Span<T>
) -> Array<T> {
    assert_two_arrays_equal_length(arr1, arr2);
    let mut multiplied: Array<T> = array![];
    loop {
        match arr1.pop_front() {
            Option::Some(el1) => {
                let el2 = arr2.pop_front().unwrap();
                multiplied.append(*el1 * *el2);
            },
            Option::None => { break (); }
        }
    };
    multiplied
}
// Make an array from a span
fn span_to_array<T, +Drop<T>, +Copy<T>>(mut span: Span<T>) -> Array<T> {
    let mut arr = array![];
    loop {
        match span.pop_front() {
            Option::Some(el) => { arr.append(*el); },
            Option::None => { break (); }
        }
    };
    arr
}

fn pow(mut value:u256, mut power:u8)->u256{
    let mut res:u256 = 1;
    while power>0{
        res*=value;
        power-=1;
    };
    res
}
fn to_wei(mut values:Span<u256>,mut decimals:u8)->Span<u256>{
    let mut arr_res=array![];

    loop {
        match values.pop_front(){
            Option::Some(value)=>{
                let updated_value = *value*pow(10,decimals);
                arr_res.append(updated_value);
            },
            Option::None=>{break;}
        }
    };
    arr_res.span()
}


/// ERC20 Helpers ///

// Get erc20 balances for an address
fn get_erc20_balance(contract_address: ContractAddress, account_address: ContractAddress) -> u256 {
    let contract = ERC20ABIDispatcher { contract_address };
    contract.balance_of(account_address)
}

// Get erc20 balances for multiple addresses
fn get_erc20_balances(
    contract_address: ContractAddress, mut account_addresses: Span<ContractAddress>
) -> Array<u256> {
    let mut balances = array![];
    loop {
        match account_addresses.pop_front() {
            Option::Some(addr) => { balances.append(get_erc20_balance(contract_address, *addr)); },
            Option::None => { break (); }
        }
    };
    balances
}

// Return each elements portion of the 'amount' corresponding to the total of the array
// @dev Scaling with bps for precision
// @dev Used to determine how many premiums and payouts belong to an account
fn get_portion_of_amount(mut arr: Span<u256>, amount: u256) -> Array<u256> {
    let precision_factor = 10000;
    let mut total = sum_u256_array(arr);
    let mut portions = array![];
    loop {
        match arr.pop_front() {
            Option::Some(el) => {
                let portion = ((precision_factor * *el * amount) / total) / precision_factor;
                portions.append(portion);
            },
            Option::None => { break (); }
        }
    };
    portions
}

