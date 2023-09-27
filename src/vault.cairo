use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};
use openzeppelin::token::erc20::interface::IERC20Dispatcher;
use openzeppelin::utils::serde::SerializedAppend;

use pitch_lake_starknet::option_round::{IOptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundParams};
use pitch_lake_starknet::market_aggregator::{IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait};

#[derive(Copy, Drop, Serde, PartialEq)]
enum VaultType {
    InTheMoney,
    AtTheMoney,
    OutOfMoney,
}

#[event]
#[derive(Drop, starknet::Event)]
enum Event {
    Deposit: VaultTransfer,
    Withdrawal: VaultTransfer,
    OptionRoundCreated: OptionRoundCreated,
}

#[derive(Drop, starknet::Event)]
struct VaultTransfer {
    from: ContractAddress,
    to: ContractAddress,
    amount: u256
}

#[derive(Drop, starknet::Event)]
struct OptionRoundCreated {
    prev_round: ContractAddress,
    new_round: ContractAddress,
    collaterized_amount: u256,
    option_round_params:OptionRoundParams
}


#[starknet::interface]
trait IVault<TContractState> {

    // add liquidity to the unallocated/uncollaterized pool in eth(wei). sender and registered_for should be the same for most cases, 
    // but option_round can deposit liquidity back after an option round has completed on behalf of the orginal liquidity provider
    #[external]
    fn deposit_liquidity(ref self: TContractState, amount: u256, sender:ContractAddress, registered_for:ContractAddress) -> bool;

    // withdraw liquidity from the unallocated/uncollaterized pool to the recicpient.
    #[external]
    fn withdraw_liquidity_to(ref self: TContractState, amount: u256, recipient:ContractAddress ) -> bool;

    #[view]
    fn generate_option_round_params(ref self: TContractState, option_expiry_time_:u64)-> OptionRoundParams;

    // generate the option parameters and also deploy the option contract and move the liquidity over to the new option contract, also start the auction on the new option contract. 
    // after a new round is started, both total_unallocated_liquidity and unallocated_liquidity_balance_of will return zero, unless a new liquidity is deposited via deposit_liquidity function.
    // after the call previos_option_round will return the previous round and current_option_round will return the new round
    #[external]
    fn start_new_option_round(ref self: TContractState, params:OptionRoundParams ) -> IOptionRoundDispatcher;

    #[view]
    fn vault_type(self: @TContractState) -> VaultType;

    // returns the latest option round
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

    #[view]
    fn get_market_aggregator(self: @TContractState) -> IMarketAggregatorDispatcher;

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
    use pitch_lake_starknet::market_aggregator::{IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait};


    #[storage]
    struct Storage {
        current_option_round_params: OptionRoundParams,
        current_option_round_dispatcher: IOptionRoundDispatcher,
        option_round_class_hash: felt252,
        market_aggregator: IMarketAggregatorDispatcher
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        option_round_class_hash_: felt252,
        vault_type: VaultType,
        market_aggregator: IMarketAggregatorDispatcher
    ) {
        self.option_round_class_hash.write( option_round_class_hash_);
        self.market_aggregator.write(market_aggregator);
    }

    #[external(v0)]
    impl VaultImpl of super::IVault<ContractState> {

        #[view]
        fn decimals(ref self: ContractState)->u8{
            18
        }

        fn deposit_liquidity(ref self: ContractState, amount: u256, sender:ContractAddress, registered_for:ContractAddress ) -> bool{
            true
        }

        fn withdraw_liquidity_to(ref self: ContractState, amount: u256, recipient:ContractAddress  ) -> bool{
            true
        }

        fn generate_option_round_params(ref self: ContractState, option_expiry_time_:u64)-> OptionRoundParams{
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
                    current_average_basefee: 100,
                    strike_price: 1000,
                    standard_deviation: 50,
                    cap_level :100,  
                    collateral_level: 100,
                    reserve_price: 10,
                    total_options_available:1000,
                    // start_time:start_time_,
                    option_expiry_time:option_expiry_time_,
                    auction_end_time: 1000,
                    minimum_bid_amount: 100,
                    minimum_collateral_required:100
                };
            return tmp;
        }

        fn start_new_option_round(ref self: ContractState, params:OptionRoundParams ) -> IOptionRoundDispatcher{

            let mut calldata = array![];
            calldata.append_serde(get_contract_address());
            calldata.append_serde(get_contract_address()); // TODO upadte it to the erco 20 collaterized pool
            calldata.append_serde(params);
            calldata.append_serde(self.market_aggregator.read());

            let (address, _) = deploy_syscall(
                self.option_round_class_hash.read().try_into().unwrap(), 0, calldata.span(), true
                )
            .expect('DEPLOY_NEW_OPTION_ROUND_FAILED');
            let round_dispatcher : IOptionRoundDispatcher = IOptionRoundDispatcher{contract_address: address};

            return round_dispatcher;
        }

        fn vault_type(self: @ContractState) -> VaultType  {
            // TODO fix later, random value
            VaultType::AtTheMoney
        }

        fn current_option_round(ref self: ContractState ) -> (OptionRoundParams, IOptionRoundDispatcher){
            // TODO fix later, random value
            return (self.generate_option_round_params( 0), IOptionRoundDispatcher{contract_address: contract_address_const::<0>()});
        }

        fn previous_option_round(ref self: ContractState ) -> (OptionRoundParams, IOptionRoundDispatcher){
            // TODO fix later, random value
            return (self.generate_option_round_params( 0), IOptionRoundDispatcher{contract_address: contract_address_const::<0>()});
        }

        fn total_unallocated_liquidity(self: @ContractState) -> u256 {
            // TODO fix later, random value
            100
        }
        
        fn unallocated_liquidity_balance_of(self: @ContractState, liquidity_provider: ContractAddress) -> u256 {
            // TODO fix later, random value
            100
        }

        fn get_market_aggregator(self: @ContractState) -> IMarketAggregatorDispatcher {
            return self.market_aggregator.read();
        }
    }
}
