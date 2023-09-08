use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};

#[derive(Copy, Drop, Serde, PartialEq)]
enum PoolType {
    Collaterized: u128,
    Unallocated: u128,
}

#[starknet::interface]
trait IPool<TContractState> {

}

#[starknet::contract]
mod pool  {
    use core::traits::Into;
use openzeppelin::token::erc20::ERC20;
    use openzeppelin::token::erc20::interface::IERC20;
    use starknet::ContractAddress;
    use pitch_lake_starknet::vault::VaultType;
    use pitch_lake_starknet::pool::PoolType;

    #[storage]
    struct Storage {
        pool_type: u128
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        initial_supply: u256,
        pool_type_:PoolType,
        recipient: ContractAddress
    ) {
        let name = 'VAULT';
        let symbol = 'VLT';

        let mut unsafe_state = ERC20::unsafe_new_contract_state();
        ERC20::InternalImpl::initializer(ref unsafe_state, name, symbol);
        ERC20::InternalImpl::_mint(ref unsafe_state, recipient, initial_supply);

        //TODO update with teh proper enum.
        self.pool_type.write(1);
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

     #[external(v0)]
     impl PoolImpl of super::IPool<ContractState> {


    }
}
