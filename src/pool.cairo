use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};

#[derive(Copy, Drop, Serde, PartialEq)]
enum PoolType {
    Collaterized: u128,
    Unallocated: u128,
}

#[starknet::interface]
trait IPool<TContractState> {}

#[starknet::contract]
mod pool {
    use core::traits::Into;
    use starknet::ContractAddress;
    use openzeppelin::token::erc20::ERC20Component;
    use pitch_lake_starknet::vault::VaultType;
    use pitch_lake_starknet::pool::PoolType;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    #[storage]
    struct Storage {
        pool_type: u128,
        #[substorage(v0)]
        erc20: ERC20Component::Storage
    }

    // Exposes snake_case & CamelCase entry points
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    // Allows the contract access to internal functions
    impl InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event
    }

    #[constructor]
    fn constructor(ref self: ContractState, initial_supply: u256, recipient: ContractAddress) {
        self.erc20.initializer("VAULT", "VLT");
        self.erc20._mint(recipient, initial_supply);
        // todo: update to the proper enum
        self.pool_type.write(1);
    }

    #[abi(embed_v0)]
    impl PoolImpl of super::IPool<ContractState> {}
}
