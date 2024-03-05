use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};
use openzeppelin::token::erc20::interface::IERC20Dispatcher;
use openzeppelin::utils::serde::SerializedAppend;

use pitch_lake_starknet::option_round::{OptionRoundParams, OptionRoundState};
use pitch_lake_starknet::market_aggregator::{
    IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait
};

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
    option_round_params: OptionRoundParams
}

//IVault, Vault will be the main contract that the liquidity_providers and option_buyers will interact with.

#[starknet::interface]
trait IVault<TContractState> { // erc721
    // @notice add liquidity to the next option round. This will create a new liquidity position
    // @param amount: amount of liquidity to add
    // @return liquidity position id
    fn open_liquidity_position(ref self: TContractState, amount: u256) -> u256;

    // @notice add liquidity to the next option round. This will update the liquidity position for lp_id
    // @param lp_id: liquidity position id
    // @param amount: amount of liquidity to add
    // @return bool: true if the liquidity was added successfully 
    fn deposit_liquidity_to(ref self: TContractState, lp_id: u256, amount: u256) -> bool;

    // @notice withdraw liquidity from the position
    // @dev this can only be withdrawn from amound deposited for the next option round or if the current option round has settled and is not collaterized anymore
    // @param lp_id: liquidity position id
    // @param amount: amount of liquidity to withdraw in wei
    // @return bool: true if the liquidity was withdrawn successfully
    fn withdraw_liquidity(ref self: TContractState, lp_id: u256, amount: u256) -> bool;

    // #[view]
    // fn generate_option_round_params(ref self: TContractState, option_expiry_time_:u64)-> OptionRoundParams;

    // new 

    // @notice Deploy a new option round, this also collaterizes amount from the previous option round into current option round. This also starts the auction for the options in the current round.
    // @dev there should be checks to make sure that the current option round has settled and is not collaterized anymore and certain time has elapsed.
    // @return option round params, and the next option round id and contract address
    fn start_new_option_round_new(ref self: TContractState) -> (u256, OptionRoundParams);

    // @notice start a new option round, this also collaterizes amount from the previous option round and current option round. This also starts the auction for the options
    // @dev there should be checks to make sure that the previous option round has settled and is not collaterized anymore and certain time has elapsed.
    // @return option round id and option round params, and now also the address of the deployed option round contract
    fn start_new_option_round(
        ref self: TContractState
    ) -> (u256, OptionRoundParams, ContractAddress);

    /// remove these until...

    // @notice place a bid in the auction.
    // @param amount: max amount in weth/wei token to be used for bidding in the auction
    // @param price: max price in weth/wei token per option. if the auction ends with a price higher than this then the auction_place_bid is not accepted and can be refunded via refund_unused_bid_deposit
    // @returns true if auction_place_bid if deposit has been locked up in the auction. false if auction not running or auction_place_bid below reserve price
    fn auction_place_bid(ref self: TContractState, amount: u256, price: u256) -> bool;

    // @notice successfully ended an auction, false if there was no auction in process
    // @return : the auction clearing price
    fn settle_auction(ref self: TContractState) -> u256;

    // @notice if the option is past the expiry date then using the market_aggregator we can settle the option round
    // @return : true if the option round was settled successfully
    fn settle_option_round(ref self: TContractState) -> bool;

    // @param option_round_id: option round id
    // @return OptionRoundState: the current state of the option round // missing option round id ? 
    fn get_option_round_state(self: @TContractState) -> OptionRoundState;

    // @notice gets the option round params for the option round
    // @param option_round_id: option round id
    fn get_option_round_params(self: @TContractState, option_round_id: u256) -> OptionRoundParams;

    // @notice gets the auction clearing price for the option round, if the auction has ended
    fn get_auction_clearing_price(self: @TContractState, option_round_id: u256) -> u256;

    // moves/transfers the unused premium deposit back to the bidder, return value is the amount of the transfer
    // this is per option buyer. every option buyer will have to individually call refund_unused_bid_deposit to transfer any unused deposits
    fn refund_unused_bid_deposit(
        ref self: TContractState, option_round_id: u256, recipient: ContractAddress
    ) -> u256;

    // @notice transfers any payout due to the option buyer, return value is the amount of the transfer
    // @dev this is per option buyer. claim_option_payout will have to be called for every option buyer.
    fn claim_option_payout(
        ref self: TContractState, option_round_id: u256, for_option_buyer: ContractAddress
    ) -> u256;


    /// here. should only be in the option_round contract 

    fn vault_type(self: @TContractState) -> VaultType;

    // @return current option round params and the option round id
    fn current_option_round(self: @TContractState) -> (u256, OptionRoundParams);

    // @return next option round params and the option round id
    fn next_option_round(self: @TContractState) -> (u256, OptionRoundParams);

    // new: 
    // @return an option round id's contract address
    fn option_round_addresses(self: @TContractState, option_round_id: u256) -> ContractAddress;

    fn get_market_aggregator(self: @TContractState) -> IMarketAggregatorDispatcher;

    /// remove these until...

    // total amount deposited as part of bidding by an option buyer, if the auction has not ended this represents the total amount locked up for auction and cannot be claimed back,
    // if the auction has ended this the amount which was not converted into an option and can be claimed back.
    fn unused_bid_deposit_balance_of(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // payout due to an option buyer
    fn payout_balance_of(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // no of options bought by a user
    fn option_balance_of(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // premium balance of liquidity position
    fn premium_balance_of(self: @TContractState, lp_id: u256) -> u256;

    // locked collateral balance of a liquidity position
    fn collateral_balance_of(self: @TContractState, lp_id: u256) -> u256;

    // unallocated balance of balance of a liquidity position
    fn unallocated_liquidity_balance_of(self: @TContractState, lp_id: u256) -> u256;

    // total collateral locked up in the vault
    fn total_collateral(self: @TContractState) -> u256;

    // total liquidity unallocated/uncollaterized
    fn total_unallocated_liquidity(self: @TContractState) -> u256;

    // total options sold
    fn total_options_sold(self: @TContractState) -> u256;

    /// here ? should be only in option_round

    fn decimals(self: @TContractState) -> u8;
}

#[starknet::contract]
mod Vault {
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
    use pitch_lake_starknet::option_round::{OptionRoundParams, OptionRoundState};
    use pitch_lake_starknet::market_aggregator::{
        IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait
    };


    #[storage]
    struct Storage {
        current_option_round_params: OptionRoundParams,
        current_option_round_id: u256,
        market_aggregator: IMarketAggregatorDispatcher,
    /// matt: 

    // liquidity_positions: Array<(u256, u256)>,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        vault_type: VaultType,
        market_aggregator: IMarketAggregatorDispatcher
    ) {
        self.market_aggregator.write(market_aggregator);
    }

    #[external(v0)]
    impl VaultImpl of super::IVault<ContractState> {
        fn open_liquidity_position(ref self: ContractState, amount: u256) -> u256 {
            10
        }

        fn deposit_liquidity_to(ref self: ContractState, lp_id: u256, amount: u256) -> bool {
            true
        }

        fn withdraw_liquidity(ref self: ContractState, lp_id: u256, amount: u256) -> bool {
            true
        }

        // new 
        fn start_new_option_round_new(ref self: ContractState) -> (u256, OptionRoundParams) {
            let params = OptionRoundParams {
                current_average_basefee: 100,
                strike_price: 1000,
                standard_deviation: 50,
                cap_level: 100,
                collateral_level: 100,
                reserve_price: 10,
                total_options_available: 1000,
                // start_time:start_time_,
                option_expiry_time: 1000,
                auction_end_time: 1000,
                minimum_bid_amount: 100,
                minimum_collateral_required: 100
            };
            // assert current round is settled, and next one is initialized
            // start next round's auction
            // deploy new next round contract 
            // update current/next round ids (current += 1, next += 1)
            return (0, params);
        }

        fn start_new_option_round(
            ref self: ContractState
        ) -> (u256, OptionRoundParams, ContractAddress) {
            let params = OptionRoundParams {
                current_average_basefee: 100,
                strike_price: 1000,
                standard_deviation: 50,
                cap_level: 100,
                collateral_level: 100,
                reserve_price: 10,
                total_options_available: 1000,
                // start_time:start_time_,
                option_expiry_time: 1000,
                auction_end_time: 1000,
                minimum_bid_amount: 100,
                minimum_collateral_required: 100
            };
            // deploy new option round
            let option_round_address: ContractAddress = contract_address_const::<'TODO'>();

            return (0, params, option_round_address);
        }

        fn auction_place_bid(ref self: ContractState, amount: u256, price: u256) -> bool {
            true
        }

        fn settle_auction(ref self: ContractState) -> u256 {
            100
        }

        fn settle_option_round(ref self: ContractState) -> bool {
            true
        }

        fn get_option_round_state(self: @ContractState) -> OptionRoundState {
            OptionRoundState::Initialized
        }

        fn get_option_round_params(
            self: @ContractState, option_round_id: u256
        ) -> OptionRoundParams {
            let params = OptionRoundParams {
                current_average_basefee: 100,
                strike_price: 1000,
                standard_deviation: 50,
                cap_level: 100,
                collateral_level: 100,
                reserve_price: 10,
                total_options_available: 1000,
                // start_time:start_time_,
                option_expiry_time: 1000,
                auction_end_time: 1000,
                minimum_bid_amount: 100,
                minimum_collateral_required: 100
            };

            return params;
        }

        fn get_auction_clearing_price(self: @ContractState, option_round_id: u256) -> u256 {
            100
        }

        fn current_option_round(self: @ContractState) -> (u256, OptionRoundParams) {
            let params = OptionRoundParams {
                current_average_basefee: 100,
                strike_price: 1000,
                standard_deviation: 50,
                cap_level: 100,
                collateral_level: 100,
                reserve_price: 10,
                total_options_available: 1000,
                // start_time:start_time_,
                option_expiry_time: 1000,
                auction_end_time: 1000,
                minimum_bid_amount: 100,
                minimum_collateral_required: 100
            };
            return (0, params);
        }

        fn next_option_round(self: @ContractState) -> (u256, OptionRoundParams) {
            let params = OptionRoundParams {
                current_average_basefee: 100,
                strike_price: 1000,
                standard_deviation: 50,
                cap_level: 100,
                collateral_level: 100,
                reserve_price: 10,
                total_options_available: 1000,
                // start_time:start_time_,
                option_expiry_time: 1000,
                auction_end_time: 1000,
                minimum_bid_amount: 100,
                minimum_collateral_required: 100
            };
            return (0, params);
        }


        // new
        fn option_round_addresses(self: @ContractState, option_round_id: u256) -> ContractAddress {
            get_contract_address()
        }


        fn vault_type(self: @ContractState) -> VaultType {
            // TODO fix later, random value
            VaultType::AtTheMoney
        }

        fn get_market_aggregator(self: @ContractState) -> IMarketAggregatorDispatcher {
            return self.market_aggregator.read();
        }

        fn refund_unused_bid_deposit(
            ref self: ContractState, option_round_id: u256, recipient: ContractAddress
        ) -> u256 {
            100
        }

        fn claim_option_payout(
            ref self: ContractState, option_round_id: u256, for_option_buyer: ContractAddress
        ) -> u256 {
            100
        }

        fn unused_bid_deposit_balance_of(
            self: @ContractState, option_buyer: ContractAddress
        ) -> u256 {
            100
        }

        fn payout_balance_of(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }

        fn option_balance_of(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }

        fn premium_balance_of(self: @ContractState, lp_id: u256) -> u256 {
            100
        }

        fn collateral_balance_of(self: @ContractState, lp_id: u256) -> u256 {
            100
        }

        fn total_collateral(self: @ContractState) -> u256 {
            100
        }

        fn total_options_sold(self: @ContractState) -> u256 {
            100
        }

        fn decimals(self: @ContractState) -> u8 {
            18
        }

        fn total_unallocated_liquidity(self: @ContractState) -> u256 {
            100
        }

        fn unallocated_liquidity_balance_of(self: @ContractState, lp_id: u256) -> u256 {
            100
        }
    }
}
