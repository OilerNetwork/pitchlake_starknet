use starknet::ContractAddress;
use starknet::Event;
use pitch_lake_starknet::contracts::option_round::contract::OptionRound;

#[derive(starknet::Store, Copy, Drop, Serde, PartialEq)]
enum VaultType {
    InTheMoney,
    AtTheMoney,
    OutOfMoney,
}


#[derive(Drop, starknet::Event, PartialEq)]
struct Deposit {
    #[key]
    account: ContractAddress,
    position_balance_before: u256,
    position_balance_after: u256,
}

#[derive(Drop, starknet::Event, PartialEq)]
struct Withdrawal {
    #[key]
    account: ContractAddress,
    position_balance_before: u256,
    position_balance_after: u256,
}


#[derive(Drop, starknet::Event, PartialEq)]
struct OptionRoundDeployed {
    // might not need
    round_id: u256,
    address: ContractAddress,
// option_round_params: OptionRoundParams
// possibly more members to this event
}

#[derive(Copy, Drop, Serde)]
enum VaultError {
    // Error from OptionRound contract
    OptionRoundError: OptionRound::OptionRoundError,
    // Withdrawal exceeds unlocked position
    InsufficientBalance,
}


//Traits
impl VaultErrorIntoFelt252Trait of Into<VaultError, felt252> {
    fn into(self: VaultError) -> felt252 {
        match self {
            VaultError::OptionRoundError(e) => { e.into() },
            VaultError::InsufficientBalance => { 'Vault: Insufficient balance' }
        }
    }
}
