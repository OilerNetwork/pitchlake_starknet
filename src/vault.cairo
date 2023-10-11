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

//IVault, Vault will be the main contract that the liquidity_providers and option_buyers will interact with.

#[starknet::interface]
trait IVault<TContractState> {// erc721

    // @notice add liquidity to the next option round. This will create a new liquidity position
    // @param amount: amount of liquidity to add
    // @return liquidity position id
    #[external]
    fn deposit_liquidity(ref self: TContractState, amount: u256 ) -> u256;


    // @notice add liquidity to the next option round. This will update the liquidity position
    // @param lp_id: liquidity position id
    // @param amount: amount of liquidity to add
    // @return bool: true if the liquidity was added successfully 
    #[external]
    fn add_liquidity_to(ref self: TContractState, lp_id:u256,  amount: u256 ) -> bool;


    // @notice withdraw liquidity from the position
    // @dev this can only be withdrawn from amound deposited for the next option round or if the current option round has settled and is not collaterized anymore
    // @param lp_id: liquidity position id
    // @return bool: true if teh liquidity was withdrawn successfully
    #[external]
    fn withdraw_liquidity(ref self: TContractState, lp_id: u256, amount:u256 ) -> bool;

    #[view]
    fn generate_option_round_params(ref self: TContractState, option_expiry_time_:u64)-> OptionRoundParams;

    // @notice start a new option round, this also collaterizes amount from the previous option round and current option round. This also starts the auction for the options
    // @dev there should be checks to make sure that the previous option round has settled and is not collaterized anymore and certain time has elapsed.
    // @param params: option round params
    // @return option round id
    #[external]
    fn start_new_option_round(ref self: TContractState, params:OptionRoundParams ) -> u256;

    // @notice place a bid in the auction.
    // @param opton_round_id: option round id
    // @param amount: max amount in auction_place_bid token to be used for bidding in the auction
    // @param price: max price in auction_place_bid token(eth) per option. if the auction ends with a price higher than this then the auction_place_bid is not accepted
    // @returns true if auction_place_bid if deposit has been locked up in the auction. false if auction not running or auction_place_bid below reserve price
    #[external]
    fn auction_place_bid(ref self: TContractState, option_round_id: u256, amount : u256, price :u256) -> bool;

    // @notice successfully ended an auction, false if there was no auction in process
    // @param option_round_id: option round id
    // @return u256: the auction clearing price
    #[external]
    fn settle_auction(ref self: TContractState, option_round_id: u256) -> u256;

    // @notice if the option is past the expiry date then using the market_aggregator we can settle the option round
    // @param option_round_id: option round id
    // @return bool: true if the option round was settled successfully
    #[external]
    fn settle_option_round(ref self: TContractState, option_round_id: u256) -> bool;

    // @param option_round_id: option round id
    // @return OptionRoundState: the current state of the option round
    #[view]
    fn get_option_round_state(ref self: TContractState, option_round_id: u256) -> OptionRoundState;

    // @notice gets the most auction price for the option, if the auction has ended
    // @param option_round_id: option round id
    #[view]
    fn get_option_round_params(ref self: TContractState, option_round_id: u256) -> OptionRoundParams;

    // gets the most auction price for the option, if the auction has ended
    #[view]
    fn get_auction_clearing_price(ref self: TContractState, option_round_id: u256) -> u256;

    // moves/transfers the unused premium deposit back to the bidder, return value is the amount of the transfer
    // this is per option buyer. every option buyer will have to individually call claim_unused_bid_deposit to transfer any used deposits
    #[external]
    fn claim_unused_bid_deposit(ref self: TContractState, option_round_id: u256,  recipient:ContractAddress ) -> u256;

    // transfers any payout due to the option buyer, return value is the amount of the transfer
    // this is per option buyer. every option buyer will have to individually call claim_payout.
    #[external]
    fn claim_option_payout(ref self: TContractState, option_round_id: u256, for_option_buyer:ContractAddress ) -> u256;

    #[view]
    fn vault_type(self: @TContractState) -> VaultType;

    // @return current option round params and the option round id
    #[view]
    fn current_option_round(ref self: TContractState ) -> (OptionRoundParams, u256);

    // @return previous option round params and the option round id
    #[view]
    fn previous_option_round(ref self: TContractState ) -> (OptionRoundParams, u256);

    #[view]
    fn decimals(ref self: TContractState)->u8;

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
