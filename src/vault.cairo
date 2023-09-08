use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};
use openzeppelin::token::erc20::interface::IERC20Dispatcher;
use pitch_lake_starknet::option_round::{IOptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundParams};


#[derive(Copy, Drop, Serde, PartialEq)]
enum VaultType {
    InTheMoney: u128,
    AtTheMoney: u128,
    OutOfMoney: u128,
}


#[starknet::interface]
trait IVault<TContractState> {

    // add liquidity to the unallocated/uncollaterized pool
    #[external]
    fn deposit_liquidity(ref self: TContractState, amount: u256 ) -> bool;

    // withdraw liquidity from the unallocated/uncollaterized pool
    #[external]
    fn withdraw_liquidity(ref self: TContractState, amount: u256 ) -> bool;

    // generate the option parameters and also deploy the option contract and move the liquidity over to the new option contract, also start the auction on the new option contract,
    #[external]
    fn start_new_option_round(ref self: TContractState, start_time:u64, end_time:u64 ) -> (OptionRoundParams, IOptionRoundDispatcher);

    #[view]
    fn vault_type(self: @TContractState) -> VaultType;

    // returns the current running option round.
    #[view]
    fn current_option_round(ref self: TContractState ) -> (OptionRoundParams, IOptionRoundDispatcher);

    #[view]
    fn previous_option_round(ref self: TContractState ) -> (OptionRoundParams, IOptionRoundDispatcher);

    #[view]
    fn decimals(ref self: TContractState)->u8;

    #[view]
    fn total_liquidity_unallocated(self: @TContractState) -> u256 ;

    #[view]
    fn unallocated_liquidity_balance_of(self: @TContractState, liquidity_provider: ContractAddress) -> u256 ;

}

#[starknet::contract]
mod Vault  {
    use openzeppelin::token::erc20::ERC20;
    use openzeppelin::token::erc20::interface::IERC20;
    use starknet::{ContractAddress, deploy_syscall, contract_address_const};
    use pitch_lake_starknet::vault::VaultType;
    use pitch_lake_starknet::pool::IPoolDispatcher;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use pitch_lake_starknet::option_round::{IOptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundParams};


    #[storage]
    struct Storage {
        current_option_round_params: OptionRoundParams,
        current_option_round: IOptionRoundDispatcher
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
    ) {
    }

    fn initialize_option_params(start_time_:u64, expiry_time_:u64)-> OptionRoundParams{
        let total_liquidity_unallocated:u256 = 10000 ;
        let option_reserve_price_:u256 = 6;
        let average_basefee :u256 = 20;
        let standard_deviation : u256 = 30;
        let cap_level :u256 = average_basefee + (3 * standard_deviation); //per notes from tomasz, we set cap level at 3 standard deviation

        let in_the_money_strike_price: u256 = average_basefee + standard_deviation;
        let at_the_money_strike_price: u256 = average_basefee ;
        let out_the_money_strike_price: u256 = average_basefee - standard_deviation;

        let collateral_level = cap_level - in_the_money_strike_price; // per notes from tomasz
        let total_options_available = total_liquidity_unallocated/ collateral_level;

        let option_reserve_price = option_reserve_price_;// just an assumption

        let tmp = OptionRoundParams{
            strike_price: in_the_money_strike_price,
            standard_deviation: standard_deviation,
            cap_level :cap_level,  
            collateral_level: collateral_level,
            reserve_price: option_reserve_price,
            total_options_available: total_options_available,
            start_time:start_time_,
            expiry_time:expiry_time_};
            return tmp;
    }


    #[external(v0)]
    impl VaultImpl of super::IVault<ContractState> {

        #[view]
        fn decimals(ref self: ContractState)->u8{
            18
        }

        fn deposit_liquidity(ref self: ContractState, amount: u256 ) -> bool{
            true
        }

        fn withdraw_liquidity(ref self: ContractState, amount: u256 ) -> bool{
            true
        }

        fn start_new_option_round(ref self: ContractState, start_time:u64, end_time:u64 ) -> (OptionRoundParams, IOptionRoundDispatcher){
            let params = initialize_option_params(start_time, end_time);
            let mut calldata = array![];
            // test class hash TODO fix later
            let TEST_CLASS_HASH : felt252 = 0x000000000;

            let (address, _) = deploy_syscall(
                TEST_CLASS_HASH .try_into().unwrap(), 0, calldata.span(), true
                )
            .expect('DEPLOY_AD_FAILED');
            return (params, IOptionRoundDispatcher{contract_address: address});
        }

        fn vault_type(self: @ContractState) -> VaultType  {
            // TODO fix later, random value
            VaultType::AtTheMoney(1)
        }

        fn current_option_round(ref self: ContractState ) -> (OptionRoundParams, IOptionRoundDispatcher){
            // TODO fix later, random value
            return (initialize_option_params(0, 0), IOptionRoundDispatcher{contract_address: contract_address_const::<0>()});
        }

        fn previous_option_round(ref self: ContractState ) -> (OptionRoundParams, IOptionRoundDispatcher){
            // TODO fix later, random value
            return (initialize_option_params(0, 0), IOptionRoundDispatcher{contract_address: contract_address_const::<0>()});
        }

        fn total_liquidity_unallocated(self: @ContractState) -> u256 {
            // TODO fix later, random value
            100
        }
        
        fn unallocated_liquidity_balance_of(self: @ContractState, liquidity_provider: ContractAddress) -> u256 {
            // TODO fix later, random value
            100
        }
    }
}
