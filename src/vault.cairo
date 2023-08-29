use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};

#[derive(Copy, Drop, Serde, PartialEq)]
enum VaultType {
    InTheMoney: u128,
    AtTheMoney: u128,
    OutOfMoney: u128,
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
    use openzeppelin::token::erc20::ERC20;
    use openzeppelin::token::erc20::interface::IERC20;
    use starknet::ContractAddress;
    use pitch_lake_starknet::vault::VaultType;

    #[storage]
    struct Storage {}

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        initial_supply: u256,
        recipient: ContractAddress
    ) {
        let name = 'VAULT';
        let symbol = 'VLT';

        let mut unsafe_state = ERC20::unsafe_new_contract_state();
        ERC20::InternalImpl::initializer(ref unsafe_state, name, symbol);
        ERC20::InternalImpl::_mint(ref unsafe_state, recipient, initial_supply);
    }

    #[external(v0)]
    fn name(self: @ContractState) -> felt252 {
        let unsafe_state = ERC20::unsafe_new_contract_state();
        ERC20::ERC20Impl::name(@unsafe_state)
    }

    #[external(v0)]
    fn symbol(self: @ContractState) -> felt252 {
        let unsafe_state = ERC20::unsafe_new_contract_state();
        ERC20::ERC20Impl::symbol(@unsafe_state)
    }

    #[external(v0)]
    fn decimals(self: @ContractState) -> u8 {
        let unsafe_state = ERC20::unsafe_new_contract_state();
        ERC20::ERC20Impl::decimals(@unsafe_state)
    }

    #[external(v0)]
    fn total_supply(self: @ContractState) -> u256 {
        let unsafe_state = ERC20::unsafe_new_contract_state();
        ERC20::ERC20Impl::total_supply(@unsafe_state)
    }

    #[external(v0)]
    fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
        let unsafe_state = ERC20::unsafe_new_contract_state();
        ERC20::ERC20Impl::balance_of(@unsafe_state, account)
    }

    #[external(v0)]
    fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
        let unsafe_state = ERC20::unsafe_new_contract_state();
        ERC20::ERC20Impl::allowance(@unsafe_state, owner, spender)
    }

    #[external(v0)]
    fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
        let mut unsafe_state = ERC20::unsafe_new_contract_state();
        ERC20::ERC20Impl::transfer(ref unsafe_state, recipient, amount)
    }

    #[external(v0)]
    fn transfer_from(
        ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool {
        let mut unsafe_state = ERC20::unsafe_new_contract_state();
        ERC20::ERC20Impl::transfer_from(ref unsafe_state, sender, recipient, amount)
    }

    #[external(v0)]
    fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
        let mut unsafe_state = ERC20::unsafe_new_contract_state();
        ERC20::ERC20Impl::approve(ref unsafe_state, spender, amount)
    }

    impl VaultImpl of super::IDepositVault<ContractState> {

        // liquidity for the next cycle
        #[external]
        fn deposit(self: @ContractState, amount: u256 ) {

        }

        // withdraw liquidity from the next cycle
        #[external]
        fn withdraw(self: @ContractState, amount: u256 ) {

        }

        // TODO need better naming for lower case k, is it standard deviation?
        #[view]
        fn get_k(self: @ContractState) -> u128 {
            // TODO fix later, random value
            3
        }

        #[view]
        fn get_cap_level(self: @ContractState) -> u128 {
            // TODO fix later, random value
            100
        }

        #[view]
        fn get_duration(self: @ContractState) -> u128 {
            // TODO fix later, random value
            100
        }

        #[view]
        fn vault_type(self: @ContractState) -> VaultType  {
            // TODO fix later, random value
            VaultType::AtTheMoney(1)
        }

    }
}
