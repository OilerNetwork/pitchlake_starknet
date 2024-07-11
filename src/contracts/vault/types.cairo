use starknet::ContractAddress;
use starknet::Event;
use pitch_lake_starknet::contracts::option_round::contract::OptionRound;

#[derive(starknet::Store, Copy, Drop, Serde, PartialEq)]
enum VaultType {
    InTheMoney,
    AtTheMoney,
    OutOfMoney,
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
