use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};
use openzeppelin::token::erc20::interface::IERC20Dispatcher;

#[derive(Copy, Drop, Serde, PartialEq)]
enum VaultType {
    InTheMoney: u128,
    AtTheMoney: u128,
    OutOfMoney: u128,
}

#[derive(Copy, Drop, Serde)]
struct OptionParams {
    k:u128,
    strike_price: u128,
    volatility: u128,
    cap_level :u128,  // cap level,
    collateral_level: u128,
    reserve_price: u128,
    total_options_available: u128,
    start_time:u256,
    expiry:u256
}

#[starknet::interface]
trait IDepositVault<TContractState> {

    #[external]
    fn deposit_liquidity(ref self: TContractState, amount: u256 ) -> bool;

    #[external]
    fn withdraw_liquidity(ref self: TContractState, amount: u256 ) -> bool;

    #[external]
    fn start_auction(ref self: TContractState) -> bool;

    #[external]
    fn bid(ref self: TContractState, amount : u256, price :u256) -> bool;

    // returns the clearing price for the auction
    #[external]
    fn end_auction(ref self: TContractState) -> u128;

    #[external]
    fn generate_option_params(ref self: TContractState) -> OptionParams;

    #[external]
    fn settle(ref self: TContractState) -> bool;

    #[view]
    fn get_allocated_token_address(self: @TContractState) -> IERC20Dispatcher;

    #[view]
    fn get_unallocated_token_address(self: @TContractState) -> IERC20Dispatcher;

    #[view]
    fn get_options_token_address(self: @TContractState) -> IERC20Dispatcher;

    // TODO need better naming for lower case k, is it standard deviation?
    #[view]
    fn get_k(self: @TContractState) -> u128;

    #[view]
    fn get_cap_level(self: @TContractState) -> u128;

    #[view]
    fn vault_type(self: @TContractState) -> VaultType;

    #[view]
    fn get_unallocated_token_count(self: @TContractState) -> u256 ;

    #[view]
    fn get_allocated_token_count(self: @TContractState) -> u256 ;

    #[view]
    fn get_options_token_count(self: @TContractState) -> u256;

}

#[starknet::contract]
mod Vault  {
    use openzeppelin::token::erc20::ERC20;
    use openzeppelin::token::erc20::interface::IERC20;
    use starknet::ContractAddress;
    use pitch_lake_starknet::vault::VaultType;
    use pitch_lake_starknet::pool::IPoolDispatcher;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use super::OptionParams;

    #[storage]
    struct Storage {
        allocated_pool:IERC20Dispatcher,
        unallocated_pool: IERC20Dispatcher,
        options_pool: IERC20Dispatcher
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        allocated_pool_: ContractAddress,
        unallocated_pool_: ContractAddress
    ) {
        // self.allocated_pool.write(allocated_pool_);
        // self.unallocated_pool.write(unallocated_pool_);
        // deploy and instantiate the allocated and unallocated pool
    }

    #[external(v0)]
    impl VaultImpl of super::IDepositVault<ContractState> {

        fn deposit_liquidity(ref self: ContractState, amount: u256 ) -> bool{
            true
        }

        fn withdraw_liquidity(ref self: ContractState, amount: u256 ) -> bool{
            true
        }

        fn start_auction(ref self: ContractState) -> bool{
            true
        }

        fn bid(ref self: ContractState, amount : u256, price :u256) -> bool{
            true
        }

        // returns the clearing price for the auction
        fn end_auction(ref self: ContractState) -> u128{
            // final clearing price
            3263
        }

        fn generate_option_params(ref self: ContractState) -> OptionParams{
            let tmp = OptionParams{
                    k:10,
                    strike_price: 100,
                    volatility: 3,
                    cap_level :200,  // cap level,
                    collateral_level: 100,
                    reserve_price: 20,
                    total_options_available: 12000,
                    start_time:223423432,
                    expiry:34332432432432};
                    return tmp;
        }

        fn settle(ref self: ContractState) -> bool{
          true  
        }

        // TODO need better naming for lower case k, is it standard deviation?
        #[view]
        fn get_k(self: @ContractState) -> u128 {
            // TODO fix later, random value
            3
        }

        #[view]
        fn get_unallocated_token_count(self: @ContractState) -> u256 {
            // TODO fix later, random value
            10000
        }

        #[view]
        fn get_allocated_token_count(self: @ContractState) -> u256 {
            // TODO fix later, random value
            10
        }

        #[view]
        fn get_options_token_count(self: @ContractState) -> u256 {
            // TODO fix later, random value
            10
        }

        #[view]
        fn get_cap_level(self: @ContractState) -> u128 {
            // TODO fix later, random value
            100
        }

        #[view]
        fn vault_type(self: @ContractState) -> VaultType  {
            // TODO fix later, random value
            VaultType::AtTheMoney(1)
        }

        #[view]
        fn get_allocated_token_address(self: @ContractState) -> IERC20Dispatcher{
            self.allocated_pool.read()
        }

        #[view]
        fn get_unallocated_token_address(self: @ContractState) -> IERC20Dispatcher{
           self.unallocated_pool.read() 
        }

        #[view]
        fn get_options_token_address(self: @ContractState) -> IERC20Dispatcher{
            self.options_pool.read()
        }

    }
}
