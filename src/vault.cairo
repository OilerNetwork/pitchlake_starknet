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
    standard_deviation:u256,
    strike_price: u256,
    cap_level :u256, 
    collateral_level: u256,
    reserve_price: u256,
    total_options_available: u256,
    start_time:u64,
    expiry_time:u64
}

#[starknet::interface]
trait IVault<TContractState> {

    #[external]
    fn deposit_liquidity(ref self: TContractState, amount: u256 ) -> bool;

    #[external]
    fn withdraw_liquidity(ref self: TContractState, amount: u256 ) -> bool;

    #[external]
    fn claim_payout(ref self: TContractState, user: ContractAddress ) -> u256;

    // auction also moves capital from unallocated pool to allocated pool
    #[external]
    fn start_auction(ref self: TContractState, option_params : OptionParams);

    // returns true if bid if capital has been locked up in the auction. false if auction not running or bid below reserve price
    #[external]
    fn bid(ref self: TContractState, amount : u256, price :u256) -> bool;

    #[external]
    fn end_auction(ref self: TContractState) -> bool;

    #[view]
    fn get_auction_clearing_price(ref self: TContractState) -> u256;

    // TODO this should be part of a seperate interface
    #[external]
    fn generate_option_params(ref self: TContractState, start_time:u64, end_time:u64 ) -> OptionParams;

    #[external]
    fn settle(ref self: TContractState, current_price:u256) -> bool;


    #[view]
    fn get_cap_level(self: @TContractState) -> u256;

    #[view]
    fn vault_type(self: @TContractState) -> VaultType;

//////////////////////////////////////////////////////
//// total balances in different pools within the vault
//////////////////////////////////////////////////////
    #[view]
    fn payout_token_count(self: @TContractState) -> u256;

    #[view]
    fn get_unallocated_token_count(self: @TContractState) -> u256 ;

    // TODO may be rename it to collaterized pool
    #[view]
    fn get_allocated_token_count(self: @TContractState) -> u256 ;

    #[view]
    fn get_options_token_count(self: @TContractState) -> u256;

//////////////////////////////////////////////////////
//// user balances in different pools within the vault
//////////////////////////////////////////////////////

    #[view]
    fn payout_balance_of(ref self: TContractState, user: ContractAddress ) -> u256;

    #[view]
    fn option_balance_of(self: @TContractState, user:ContractAddress) -> u256 ;

    #[view]
    fn unallocated_balance_of(self: @TContractState) -> u256 ;

    #[view]
    fn allocated_balance_of(self: @TContractState, user:ContractAddress) -> u256 ;


//////////////////////////////////////////////////////
//// contract address of the pools being utilized within the vault
//////////////////////////////////////////////////////


    #[view]
    fn get_allocated_token_address(self: @TContractState) -> IERC20Dispatcher;

    #[view]
    fn get_unallocated_token_address(self: @TContractState) -> IERC20Dispatcher;

    #[view]
    fn get_options_token_address(self: @TContractState) -> IERC20Dispatcher;

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
    impl VaultImpl of super::IVault<ContractState> {

        fn deposit_liquidity(ref self: ContractState, amount: u256 ) -> bool{
            true
        }

        fn withdraw_liquidity(ref self: ContractState, amount: u256 ) -> bool{
            true
        }

        fn start_auction(ref self: ContractState, option_params:OptionParams) {
            
        }

        fn bid(ref self: ContractState, amount : u256, price :u256) -> bool{
            true
        }

        // returns the clearing price for the auction
        fn end_auction(ref self: ContractState) -> bool{
            // final clearing price
            true
        }

        fn get_auction_clearing_price(ref self: ContractState) -> u256{
            100
        }

        fn generate_option_params(ref self: ContractState, start_time:u64, end_time:u64) -> OptionParams{
            let tmp = OptionParams{
                    standard_deviation:10,
                    strike_price: 100,
                    cap_level :200,  // cap level,
                    collateral_level: 100,
                    reserve_price: 20,
                    total_options_available: 12000,
                    start_time:start_time,
                    expiry_time:end_time};
                    return tmp;
        }

        fn settle(ref self: ContractState, current_price:u256) -> bool{
          true  
        }

        fn claim_payout(ref self: ContractState, user: ContractAddress ) -> u256{
            33
        }

        #[view]
        fn payout_token_count(self: @ContractState) -> u256{
            22
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
        fn get_cap_level(self: @ContractState) -> u256 {
            // TODO fix later, random value
            100
        }

        #[view]
        fn vault_type(self: @ContractState) -> VaultType  {
            // TODO fix later, random value
            VaultType::AtTheMoney(1)
        }

//////////////////////////////////////////////////////
//// user balances in different pools within the vault
//////////////////////////////////////////////////////

        #[view]
        fn payout_balance_of(ref self: ContractState, user: ContractAddress ) -> u256{
            32
        }

        #[view]
        fn option_balance_of(self: @ContractState, user:ContractAddress) -> u256 {
            23
        }

        #[view]
        fn unallocated_balance_of(self: @ContractState) -> u256 {
            3
        }

        #[view]
        fn allocated_balance_of(self: @ContractState, user:ContractAddress) -> u256 {
            43
        }

//////////////////////////////////////////////////////
//// contract address of the pools being utilized within the vault
//////////////////////////////////////////////////////

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
