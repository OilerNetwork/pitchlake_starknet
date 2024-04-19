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
trait IVault<TContractState> { 
    /// Reads ///

    // Get the vault's  manaager address 
    // @dev Better access control ? (oz permits ?)
    fn vault_manager(self: @TContractState) -> ContractAddress;

    // Get the type of vault (ITM | ATM | OTM)
    fn vault_type(self: @TContractState) -> VaultType;

    // @return the current option round id 
    fn current_option_round_id(self: @TContractState) -> u256;

    // @return the contract address of the option round
    fn get_option_round_address(self: @TContractState, option_round_id: u256) -> ContractAddress;

    // Get the liquidity an LP has locked as collateral in the current round
    fn get_collateral_balance_for(
        self: @TContractState, liquidity_provider: ContractAddress
    ) -> u256;

    // Get the liqudity an LP has unallocated (unlocked), they can withdraw from this amount
    // @dev If the current round is Running, LP's share of its unallocated liquidity is uncluded (unless already withdrawn)
    // @dev Includes deposits into the next round if there are any
    fn get_unallocated_balance_for(
        self: @TContractState, liquidity_provider: ContractAddress
    ) -> u256;

    // Get the total premium LP has earned in the current round
    fn get_premiums_for(self: @TContractState, liquidity_provider: ContractAddress) -> u256;

    /// Writes ///

    // LP increments their position and sends the liquidity to the next round
    // @return the lp_id of the liquidity position (erc721 token id)
    fn deposit_liquidity(ref self: TContractState, amount: u256) -> u256;

    // LP withdraws from their position while in the round transition period
    fn withdraw_liquidity(ref self: TContractState, amount: u256);

    // Settle the current option round as long as the current round is Running and the option expiry time has passed.
    fn settle_option_round(ref self: TContractState) -> bool;

    // Start the auction on the next round as long as the current round is Settled and the
    // round transition period has passed. Deploys the next next round and updates the current/next pointers.
    fn start_auction(ref self: TContractState) -> bool;

    // End the auction in the current round as long as the current round is Auctioning and the auction
    // bidding period has ended.
    fn end_auction(ref self: TContractState) -> u256;

    // @note needed ? 
    fn get_market_aggregator(self: @TContractState) -> IMarketAggregatorDispatcher;
}

#[starknet::contract]
mod Vault {
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use core::traits::Into;
    use pitch_lake_starknet::vault::IVault;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::token::erc20::interface::IERC20;
    use starknet::{
        ContractAddress, ClassHash, deploy_syscall, get_caller_address, contract_address_const,
        get_contract_address
    };
    use pitch_lake_starknet::vault::VaultType;
    use pitch_lake_starknet::pool::IPoolDispatcher;
    use openzeppelin::utils::serde::SerializedAppend;
    use pitch_lake_starknet::option_round::{
        OptionRound, OptionRoundConstructorParams, OptionRoundParams, OptionRoundState,
        IOptionRoundDispatcher, IOptionRoundDispatcherTrait
    };
    use pitch_lake_starknet::market_aggregator::{
        IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait
    };
    use debug::{PrintTrait};


    #[storage]
    struct Storage {
        vault_manager: ContractAddress,
        current_option_round_params: OptionRoundParams,
        current_option_round_id: u256,
        market_aggregator: ContractAddress,
        round_addresses: LegacyMap<u256, ContractAddress>,
    // liquidity_positions: Array<(u256, u256)>,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        vault_manager: ContractAddress,
        vault_type: VaultType,
        market_aggregator: ContractAddress,
        //market_aggregator: IMarketAggregatorDispatcher,
        option_round_class_hash: ClassHash,
    ) {
        self.vault_manager.write(vault_manager);
        self.market_aggregator.write(market_aggregator);
        // @dev Deploy the 0th round as current (Settled) and deploy the 1st round (Open)
        let z_constructor_args: OptionRoundConstructorParams = OptionRoundConstructorParams {
            vault_address: starknet::get_contract_address(), round_id: 0
        };
        let f_constructor_args: OptionRoundConstructorParams = OptionRoundConstructorParams {
            vault_address: starknet::get_contract_address(), round_id: 1
        };
        // Deploy 0th round
        let mut calldata = array![market_aggregator.into()];
        calldata.append_serde(z_constructor_args);
        let (z_address, _) = deploy_syscall(
            option_round_class_hash, 'some salt', calldata.span(), false
        )
            .unwrap();
        // Deploy 1st round
        let mut calldata = array![market_aggregator.into()];
        calldata.append_serde(f_constructor_args);
        let (f_address, _) = deploy_syscall(
            option_round_class_hash, 'some salt', calldata.span(), false
        )
            .unwrap();
        // Set round addressess
        self.round_addresses.write(0, z_address);
        self.round_addresses.write(1, f_address);
    }


    #[abi(embed_v0)]
    impl VaultImpl of super::IVault<ContractState> {
        /// Reads ///
        fn vault_manager(self: @ContractState) -> ContractAddress {
            self.vault_manager.read()
        }

        fn vault_type(self: @ContractState) -> VaultType {
            VaultType::AtTheMoney
        }

        fn current_option_round_id(self: @ContractState) -> u256 {
            // (for testing; need a deployed instance of round to avoid CONTRACT_NOT_DEPLOYED errors)
            0
        }

        fn get_option_round_address(
            self: @ContractState, option_round_id: u256
        ) -> ContractAddress {
            self.round_addresses.read(option_round_id)
        }

        fn get_collateral_balance_for(
            self: @ContractState, liquidity_provider: ContractAddress
        ) -> u256 {
            100
        }

        fn get_unallocated_balance_for(
            self: @ContractState, liquidity_provider: ContractAddress
        ) -> u256 {
            100
        }

        fn get_premiums_for(self: @ContractState, liquidity_provider: ContractAddress) -> u256 {
            100
        }

        /// Writes ///
        fn deposit_liquidity(ref self: ContractState, amount: u256) -> u256 {
            1
        }

        fn withdraw_liquidity(ref self: ContractState, amount: u256) {}

        fn settle_option_round(ref self: ContractState) -> bool {
            true
        }

        fn start_auction(ref self: ContractState) -> bool {
            true
        }

        fn end_auction(ref self: ContractState) -> u256 {

            100
        }

        fn get_market_aggregator(self: @ContractState) -> IMarketAggregatorDispatcher {
            IMarketAggregatorDispatcher { contract_address: self.market_aggregator.read() }
        }
    }
}
