use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcherTrait,
};
use starknet::{ContractAddress};
/// Array helpers ///

// Create array of length `len`, each element is `amount` (For bids use the function twice for price and amount)
fn create_array_linear(amount: u256, len: u32) -> Array<u256> {
    let mut arr: Array<u256> = array![];
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

// Sum all of the u256s in a given span
fn sum_u256_array(mut arr: Span<u256>) -> u256 {
    let mut sum = 0;
    match arr.pop_front() {
        Option::Some(el) => { sum += *el; },
        Option::None => {}
    }
    sum
}

// Assert two arrays of any type are equal
fn assert_two_arrays_equal_length<T, V>(arr1: Span<T>, arr2: Span<V>) {
    assert(arr1.len() == arr2.len(), 'Arrays not equal length');
}

// Sum an array of spreads and return the total spread
fn sum_spreads(mut spreads: Span<(u256, u256)>) -> (u256, u256) {
    let mut total_locked: u256 = 0;
    let mut total_unlocked: u256 = 0;
    loop {
        match spreads.pop_front() {
            Option::Some((
                locked, unlocked
            )) => {
                total_locked += *locked;
                total_unlocked += *unlocked;
            },
            Option::None => { break (); }
        }
    };
    (total_locked, total_unlocked)
}

// Split spreads into locked and unlocked arrays
fn split_spreads(mut spreads: Span<(u256, u256)>) -> (Array<u256>, Array<u256>) {
    let mut locked: Array<u256> = array![];
    let mut unlocked: Array<u256> = array![];
    loop {
        match spreads.pop_front() {
            Option::Some((
                locked_amount, unlocked_amount
            )) => {
                locked.append(*locked_amount);
                unlocked.append(*unlocked_amount);
            },
            Option::None => { break (); }
        }
    };
    (locked, unlocked)
}

// Get erc20 balances for an address
fn get_erc20_balance(contract_address: ContractAddress, account_address: ContractAddress) -> u256 {
    let contract = IERC20Dispatcher { contract_address };
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
