use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};
use openzeppelin::token::erc20::interface::IERC20Dispatcher;
use openzeppelin::utils::serde::SerializedAppend;

use pitch_lake_starknet::option_round::{IOptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundParams};


#[derive(Copy, Drop, Serde, PartialEq)]
enum VaultType {
    InTheMoney,
    AtTheMoney,
    OutOfMoney,
}



#[event]
#[derive(Drop, starknet::Event)]
enum Event {
    Deposit: Transfer,
    Withdrawal: Transfer,
    OptionRoundCreated: OptionRoundCreated,
}

#[derive(Drop, starknet::Event)]
struct Transfer {
    from: ContractAddress,
    to: ContractAddress,
    value: u256
}

#[derive(Drop, starknet::Event)]
struct OptionRoundCreated {
    prev_round: ContractAddress,
    new_round: ContractAddress,
    collaterized: u256
}


#[starknet::interface]
trait IVault<TContractState> {

    // add liquidity to the unallocated/uncollaterized pool
    #[external]
    fn deposit_liquidity(ref self: TContractState, amount: u256 ) -> bool;

    // withdraw liquidity from the unallocated/uncollaterized pool
    #[external]
    fn withdraw_liquidity(ref self: TContractState, amount: u256 ) -> bool;

    #[view]
    fn generate_option_round_params(ref self: TContractState, start_time_:u64, expiry_time_:u64)-> OptionRoundParams;

    // generate the option parameters and also deploy the option contract and move the liquidity over to the new option contract, also start the auction on the new option contract,
    #[external]
    fn start_new_option_round(ref self: TContractState, params:OptionRoundParams ) -> IOptionRoundDispatcher;

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
    fn total_unallocated_liquidity(self: @TContractState) -> u256 ;

    #[view] 
    fn unallocated_liquidity_balance_of(self: @TContractState, liquidity_provider: ContractAddress) -> u256 ;

}

#[starknet::contract]
mod Vault  {
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use core::traits::Into;
    use pitch_lake_starknet::vault::IVault;
    use openzeppelin::token::erc20::ERC20;
    use openzeppelin::token::erc20::interface::IERC20;
    use starknet::{ContractAddress, deploy_syscall, contract_address_const, get_contract_address};
    use pitch_lake_starknet::vault::VaultType;
    use pitch_lake_starknet::pool::IPoolDispatcher;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use openzeppelin::utils::serde::SerializedAppend;
    use pitch_lake_starknet::option_round::{IOptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundParams};


    #[storage]
    struct Storage {
        current_option_round_params: OptionRoundParams,
        current_option_round_dispatcher: IOptionRoundDispatcher,
        option_round_class_hash: felt252
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        option_round_class_hash_: felt252,
        vault_type: VaultType
    ) {
        self.option_round_class_hash.write( option_round_class_hash_);
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

        fn generate_option_round_params(ref self: ContractState, start_time_:u64, expiry_time_:u64)-> OptionRoundParams{
            // let total_unallocated_liquidity:u256 = 1000000000000000000000; // should be -> self.total_unallocated_liquidity() ;
            // // assert(total_unallocated_liquidity > 0, 'liquidity cannnot be zero');
            // let option_reserve_price_:u256 = 6;
            // let average_basefee :u256 = 20;
            // let standard_deviation : u256 = 30;
            // let cap_level :u256 = average_basefee + (3 * standard_deviation); //per notes from tomasz, we set cap level at 3 standard deviation

            // let in_the_money_strike_price: u256 = average_basefee - standard_deviation;
            // let at_the_money_strike_price: u256 = average_basefee ;
            // let out_the_money_strike_price: u256 = average_basefee + standard_deviation;

            // let collateral_level = cap_level - in_the_money_strike_price; // per notes from tomasz
            // let total_options_available = total_unallocated_liquidity/ collateral_level;

            // let option_reserve_price = option_reserve_price_;// just an assumption

            let tmp :OptionRoundParams= OptionRoundParams{
                strike_price: 1000,
                standard_deviation: 50,
                cap_level :100,  
                collateral_level: 100,
                reserve_price: 10,
                total_options_available:1000,
                start_time:start_time_,
                expiry_time:expiry_time_};
            return tmp;
        }

        fn start_new_option_round(ref self: ContractState, params:OptionRoundParams ) -> IOptionRoundDispatcher{

            let mut calldata = array![];
            calldata.append_serde(get_contract_address());
            calldata.append_serde(get_contract_address()); // TODO upadte it to the erco 20 collaterized pool
            calldata.append_serde(params);

            let (address, _) = deploy_syscall(
                self.option_round_class_hash.read().try_into().unwrap(), 0, calldata.span(), true
                )
            .expect('DEPLOY_AD_FAILED');
            let round_dispatcher : IOptionRoundDispatcher = IOptionRoundDispatcher{contract_address: address};

            return round_dispatcher;
        }

        fn vault_type(self: @ContractState) -> VaultType  {
            // TODO fix later, random value
            VaultType::AtTheMoney
        }

        fn current_option_round(ref self: ContractState ) -> (OptionRoundParams, IOptionRoundDispatcher){
            // TODO fix later, random value
            return (self.generate_option_round_params(0, 0), IOptionRoundDispatcher{contract_address: contract_address_const::<0>()});
        }

        fn previous_option_round(ref self: ContractState ) -> (OptionRoundParams, IOptionRoundDispatcher){
            // TODO fix later, random value
            return (self.generate_option_round_params(0, 0), IOptionRoundDispatcher{contract_address: contract_address_const::<0>()});
        }

        fn total_unallocated_liquidity(self: @ContractState) -> u256 {
            // TODO fix later, random value
            100
        }
        
        fn unallocated_liquidity_balance_of(self: @ContractState, liquidity_provider: ContractAddress) -> u256 {
            // TODO fix later, random value
            100
        }
    }
}
