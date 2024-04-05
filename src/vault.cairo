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
// Is this the case or wil OBs interact with the option rounds ? 

#[starknet::interface]
trait IVault<TContractState> { // erc721
    /// new below ///

    /// Reads ///

    // matt 
    // @return The LP's deposited balance at the start of the round_id (actual deposit value)
    fn lp_deposit_balance(self: @TContractState, lp: ContractAddress, round_id: u256) -> u256;
    // @return THe LP's position value at the start of the round_id
    fn lp_position_balance(self: @TContractState, lp: ContractAddress, round_id: u256) -> u256;
    // matt

    // @return the type of the vault (ITM | ATM | OTM)
    fn vault_type(self: @TContractState) -> VaultType;

    // @return the current option round id 
    fn current_option_round_id(self: @TContractState) -> u256;

    // @return the next option round id
    fn next_option_round_id(self: @TContractState) -> u256;

    // @return the contract address of the option round
    fn get_option_round_address(self: @TContractState, option_round_id: u256) -> ContractAddress;

    // Don't need arbitrary lookups, just current 
    // @return an LP's liquidity at the start of the option round
    fn get_lps_starting_liquidity_in_option_round(self: @TContractState, round_id: u256) -> u256;

    // @return an LP's liquidity at the end of the option round (the remaining liquidity)
    fn get_lps_final_liquidity_in_option_round(self: @TContractState, round_id: u256) -> u256;

    // @return the premiums LP has earned in the option round
    fn get_lps_premiums_earned_in_option_round(self: @TContractState, round_id: u256) -> u256;

    /// Writes ///

    // LP modifies their current position or creates a new one if they don't have one yet
    // @return the lp_id of the liquidity position (erc721 token id)
    fn deposit_liquidity(ref self: TContractState, amount: u256) -> u256;

    // LP flags their entire position to be withdrawn at the end of the current running round
    // @return if the claim was submitted successfully
    fn submit_claim(ref self: TContractState) -> bool;

    // LP withdraws their liquidity from the the current open option round 
    // @return if the withdrawal was successful
    fn withdraw_liquidity(ref self: TContractState, lp_id: u256, amount: u256) -> bool;

    // Deploy the next option round contract as long as the current is state::Settled, and start 
    // the auction on the new current option round (-> state::Auctioning)
    // @note This function should only be callable by the pitchlake server, or the public with incentive.
    // @dev The current/next_option_round_id both increment by 1.
    // @dev The new next option round is deployed with state::Open.
    // @note Once we start the auction we know how much liquidity we have, this is where 
    // we fetch/consume/pass the values from fossil (strike, cl, etc.) to create our OptionRoundParams.
    fn start_next_option_round(ref self: TContractState) -> bool;


    /// old below

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
    // fn withdraw_liquidity(ref self: TContractState, lp_id: u256, amount: u256) -> bool;

    // read 
    // @return current option round params and the option round id
    fn current_option_round(self: @TContractState) -> (u256, OptionRoundParams);

    // @return next option round params and the option round id
    fn next_option_round(self: @TContractState) -> (u256, OptionRoundParams);

    fn get_market_aggregator(self: @TContractState) -> IMarketAggregatorDispatcher;

    // @return the contract address of the option round
    fn option_round_addresses(self: @TContractState, option_round_id: u256) -> ContractAddress;

    // unallocated balance of balance of a liquidity position
    fn unallocated_liquidity_balance_of(self: @TContractState, lp_id: u256) -> u256;

    // total liquidity unallocated/uncollaterized
    fn total_unallocated_liquidity(self: @TContractState) -> u256;

    // decimals in the vault token ?
    fn decimals(self: @TContractState) -> u8;


    // #[view]
    // fn generate_option_round_params(ref self: TContractState, option_expiry_time_:u64)-> OptionRoundParams;

    // @notice Deploy a new option round, this also collaterizes amount from the previous option round into current option round. This also starts the auction for the options in the current round.
    // @dev there should be checks to make sure that the current option round has settled and is not collaterized anymore and certain time has elapsed.
    // @return option round params, and the next option round id and contract address
    fn start_new_option_round(ref self: TContractState) -> (u256, OptionRoundParams);
}

#[starknet::contract]
mod Vault {
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use core::traits::Into;
    use pitch_lake_starknet::vault::IVault;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::token::erc20::interface::IERC20;
    use starknet::{ContractAddress, deploy_syscall, contract_address_const, get_contract_address};
    use pitch_lake_starknet::vault::VaultType;
    use pitch_lake_starknet::pool::IPoolDispatcher;
    use openzeppelin::utils::serde::SerializedAppend;
    use pitch_lake_starknet::option_round::{
        OptionRound, OptionRoundParams, OptionRoundState, IOptionRoundDispatcher,
        IOptionRoundDispatcherTrait
    };
    use pitch_lake_starknet::market_aggregator::{
        IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait
    };


    #[storage]
    struct Storage {
        current_option_round_params: OptionRoundParams,
        current_option_round_id: u256,
        market_aggregator: IMarketAggregatorDispatcher,
        /// matt: 

        round_addresses: LegacyMap<u256, ContractAddress>,
    // liquidity_positions: Array<(u256, u256)>,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        vault_type: VaultType,
        market_aggregator: IMarketAggregatorDispatcher
    ) {
        self.market_aggregator.write(market_aggregator);
        // could deploy a 0th round, and automatically set it to Settled, 

        // @dev Deploy a 0th round as current, and set it to Settled, then deploy the 1st round as next round
        let zeroth_option_round_params: OptionRoundParams = OptionRoundParams {
            current_average_basefee: 0,
            strike_price: 0,
            standard_deviation: 0,
            cap_level: 0,
            collateral_level: 0,
            reserve_price: 0,
            total_options_available: 0,
            // start_time:start_time_,
            option_expiry_time: 0,
            auction_end_time: 0,
            minimum_bid_amount: 0,
            minimum_collateral_required: 0
        };
        let test_option_round_params: OptionRoundParams = OptionRoundParams {
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
    // Deploy 0th round
    //let mut calldata: Array<felt252> = array!['owner'];
    //calldata.append_serde(starknet::get_contract_address());
    //calldata.append_serde(zeroth_option_round_params);
    //calldata.append_serde(market_aggregator);
    //let class_hash: starknet::ClassHash = OptionRound::TEST_CLASS_HASH;
    //let (option_round_0_address, _) = deploy_syscall(
    //class_hash, 'some salt', calldata.span(), false
    //)
    //.unwrap();

    // Deploy 1st round
    //calldata = array!['owner'];
    //calldata.append_serde(starknet::get_contract_address());
    //calldata.append_serde(test_option_round_params);
    //calldata.append_serde(market_aggregator);
    //let (option_round_1_address, _) = deploy_syscall(
    //OptionRound::TEST_CLASS_HASH.try_into().unwrap(), 'some salt', calldata.span(), false
    //)
    //.unwrap();

    //self.round_addresses.write(0, option_round_0_address);
    //self.round_addresses.write(1, option_round_1_address);
    // need to set 0th round to Settled 
    }


    #[abi(embed_v0)]
    impl VaultImpl of super::IVault<ContractState> {
        /// Reads ///
        fn vault_type(self: @ContractState) -> VaultType {
            VaultType::AtTheMoney
        }

        fn current_option_round_id(self: @ContractState) -> u256 {
            // (for testing; need a deployed instance of round to avoid CONTRACT_NOT_DEPLOYED errors)
            0
        }

        fn next_option_round_id(self: @ContractState) -> u256 {
            1
        }

        fn get_option_round_address(
            self: @ContractState, option_round_id: u256
        ) -> ContractAddress {
            self.option_round_addresses(option_round_id)
        }

        fn get_lps_starting_liquidity_in_option_round(
            self: @ContractState, round_id: u256
        ) -> u256 {
            100
        }

        fn get_lps_final_liquidity_in_option_round(self: @ContractState, round_id: u256) -> u256 {
            100
        }

        fn get_lps_premiums_earned_in_option_round(self: @ContractState, round_id: u256) -> u256 {
            100
        }
        // matt 
        fn lp_deposit_balance(self: @ContractState, lp: ContractAddress, round_id: u256) -> u256 {
            100
        }

        fn lp_position_balance(self: @ContractState, lp: ContractAddress, round_id: u256) -> u256 {
            100
        }

        /// Writes ///
        fn deposit_liquidity(ref self: ContractState, amount: u256) -> u256 {
            1
        }

        fn submit_claim(ref self: ContractState) -> bool {
            true
        }

        fn withdraw_liquidity(ref self: ContractState, lp_id: u256, amount: u256) -> bool {
            true
        }

        fn start_next_option_round(ref self: ContractState) -> bool {
            true
        }

        /// old ///

        fn open_liquidity_position(ref self: ContractState, amount: u256) -> u256 {
            10
        }

        fn deposit_liquidity_to(ref self: ContractState, lp_id: u256, amount: u256) -> bool {
            true
        }

        // fn withdraw_liquidity(ref self: ContractState, lp_id: u256, amount: u256) -> bool {
        //     true
        // }

        fn start_new_option_round(ref self: ContractState) -> (u256, OptionRoundParams) {
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

            // // mock deploy to abvoid a ton of ENTRYPOINT_NOT_FOUND errors
            // //todo real vals
            // let mut call_data: Array<felt252> = array!['owner', 'collat. pool addr'];
            // // 
            // call_data.append_serde(params);
            // // should just use address and build dispatcher when needed ? 
            // call_data.append('mk agg dispatcher');

            // let (round_address, _) = deploy_syscall(
            //     OptionRound::TEST_CLASS_HASH.try_into().unwrap(), 'salt', call_data.span(), false
            // )
            //     .unwrap();

            // // mock set in storage 
            // self.round_addresses.write(1, round_address);

            return (1, params);
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
            // get_contract_address()
            self.round_addresses.read(option_round_id)
        }

        // fn vault_type(self: @ContractState) -> VaultType {
        //     // TODO fix later, random value
        //     VaultType::AtTheMoney
        // }

        fn get_market_aggregator(self: @ContractState) -> IMarketAggregatorDispatcher {
            return self.market_aggregator.read();
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
