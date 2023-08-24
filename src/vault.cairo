use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};
use pitch_lake_starknet::eth::Eth;

#[derive(Copy, Drop, Serde, PartialEq)]
enum VaultType {
    InTheMoney: (),
    AtTheMoney: (),
    OutOfMoney: (),
}


#[starknet::interface]
trait IDepositVault<TContractState> {

    #[external]
    fn deposit(self: @TContractState, amount: u256 ) ;
    #[external]
    fn withdraw(self: @TContractState, amount: u256 ) ;

    // TODO need better naming for lower case k, is it standard deviation?
    #[view]
    fn get_k(self: @TContractState) -> u128;

    #[view]
    fn get_cap_level(self: @TContractState) -> u128;

    #[view]
    fn get_duration(self: @TContractState) -> u128;

    #[view]
    fn vault_type(self: @TContractState) -> VaultType;

}

#[starknet::contract]
mod Vault  {
    use starknet::{ContractAddress, StorePacking};
    use starknet::contract_address::ContractAddressZeroable;
    use pitch_lake_starknet::eth::Eth;

    // TODO update the WETH contract address below
    // const WETH_CONTRACT_ADDRESS: ContractAddress = 1111111;


    #[constructor]
    fn constructor(ref self: ContractState, 
        name: felt252, symbol: felt252, initial_supply: u256, recipient: ContractAddress
    ) {
        // Eth::initializer(name, symbol);
        // Eth::_mint(recipient, initial_supply);
    }

    #[view]
    fn name() -> felt252 {
        'PITCH_LAKE_VAULT'
    }

    #[view]
    fn symbol() -> felt252 {
        'PLV'
    }

    #[view]
    fn decimals(ref self: ContractState) -> u8 {
        Eth::decimals()
    }

    #[view]
    fn totalSupply() -> u256 {
        Eth::totalSupply()
    }

    #[view]
    fn balanceOf(account: ContractAddress) -> u256 {
        Eth::balanceOf(account)
    }

    #[view]
    fn allowance(owner: ContractAddress, spender: ContractAddress) -> u256 {
        ERC20::allowance(owner, spender)
    }

    #[external]
    fn transfer(recipient: ContractAddress, amount: u256) -> bool {
        Eth::transfer(recipient, amount)
    }

    #[external]
    fn transferFrom(sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool {
        Eth::transferFrom(sender, recipient, amount)
    }

    #[external]
    fn approve(spender: ContractAddress, amount: u256) -> bool {
        Eth::approve(spender, amount)
    }


    #[storage]
    struct Storage {
        // balance: u256, 
    }

    impl VaultImpl of super::IDepositVault<ContractState> {
    #[external]
    fn deposit(self: @TContractState, amount: u256 ) {

    }
    #[external]
    fn withdraw(self: @TContractState, amount: u256 ) ;

    // TODO need better naming for lower case k, is it standard deviation?
    #[view]
    fn get_k(self: @TContractState) -> u128;

    #[view]
    fn get_cap_level(self: @TContractState) -> u128;

    #[view]
    fn get_duration(self: @TContractState) -> u128;

    #[view]
    fn vault_type(self: @TContractState) -> VaultType;

    }
}
