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
    fn deposit_liquidity(ref self: TContractState, amount: u256 ) -> bool;

    #[external]
    fn withdraw_liquidity(ref self: TContractState, amount: u256 ) -> bool;

    // who is calling the generate params method? should it be called manually? does it check  internally that appropraite time has elapsed before generating new params.
    #[external]
    fn generate_params_start_auction(ref self: TContractState) -> bool;

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
    use pitch_lake_starknet::pool::IPoolDispatcher;

    #[storage]
    struct Storage {
        allocated_pool:ContractAddress,
        un_allocated_pool: ContractAddress
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        allocated_pool_: ContractAddress,
        un_allocated_pool_: ContractAddress
    ) {
        self.allocated_pool.write(allocated_pool_);
        self.un_allocated_pool.write(un_allocated_pool_);
        // deploy and instantiate the allocated and unallocated pool
    }

    #[external(v0)]
    impl VaultImpl of super::IDepositVault<ContractState> {

        // liquidity for the next cycle
        fn deposit_liquidity(ref self: ContractState, amount: u256 ) -> bool{
            true
        }

        fn generate_params_start_auction(ref self: ContractState) -> bool{
            true
        }

        // withdraw liquidity from the next cycle
        fn withdraw_liquidity(ref self: ContractState, amount: u256)-> bool  {
            true
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
