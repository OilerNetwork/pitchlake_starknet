use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};
use openzeppelin::token::erc20::interface::ERC20ABIDispatcher;
use openzeppelin::utils::serde::SerializedAppend;

use pitch_lake_starknet::contracts::option_round::types::{OptionRoundState};
use pitch_lake_starknet::contracts::market_aggregator::{
    IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait
};

// @note Events for tokeninzing/positionizing in this contract or vault?
#[event]
#[derive(Drop, starknet::Event)]
enum Event {}

#[starknet::interface]
trait ILPToken<TContractState> {
    /// Reads ///

    // The address of th vault contract associated with this contract
    fn vault_address(self: @TContractState) -> ContractAddress;

    // The address of the option round associated with this lp token
    fn option_round_address(self: @TContractState) -> ContractAddress;
/// Writes ///

// Burn round tokens and convert them into a position in the vault
//fn convert_to_position(ref self: TContractState, amount: u256);
}
#[starknet::contract]
mod LpToken {
    use starknet::{ContractAddress};
    use openzeppelin::token::erc20::ERC20Component;
    use pitch_lake_starknet::contracts::{lp_token::{ILPToken}};

    // ERC20 Component
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    // Exposes snake_case & CamelCase entry points
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    // Allows the contract access to internal functions
    impl InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        vault_address: ContractAddress,
        option_round_address: ContractAddress,
        #[substorage(v0)]
        erc20: ERC20Component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event
    }
    #[constructor]
    fn constructor(ref self: ContractState, name: ByteArray, symbol: ByteArray) {
        self.erc20.initializer(name, symbol);
    }

    #[abi(embed_v0)]
    impl LPTokenImpl of ILPToken<ContractState> {
        /// Reads ///

        fn vault_address(self: @ContractState) -> ContractAddress {
            self.vault_address.read()
        }

        fn option_round_address(self: @ContractState) -> ContractAddress {
            self.option_round_address.read()
        }
    /// Writes ///

    //fn convert_to_position(ref self: ContractState, amount: u256) {}
    }
}
