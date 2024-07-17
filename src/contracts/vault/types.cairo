use starknet::ContractAddress;
use starknet::Event;
use pitch_lake_starknet::contracts::option_round::contract::OptionRound;

#[derive(starknet::Store, Copy, Drop, Serde, PartialEq)]
enum VaultType {
    InTheMoney,
    AtTheMoney,
    OutOfMoney,
}

mod Errors {
    const InsufficientBalance: felt252 = 'Insufficient unlocked balance';
}
