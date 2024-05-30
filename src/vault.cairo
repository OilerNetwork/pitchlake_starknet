use starknet::{ContractAddress};
use pitch_lake_starknet::option_round::{StartAuctionParams, OptionRoundState};
use pitch_lake_starknet::market_aggregator::{IMarketAggregator, IMarketAggregatorDispatcher};

// The type of vault
#[derive(starknet::Store, Copy, Drop, Serde, PartialEq)]
enum VaultType {
    InTheMoney,
    AtTheMoney,
    OutOfMoney,
}

// The interface for the vault contract
#[starknet::interface]
trait IVault<TContractState> {
    // Being used for testing event asserters work correctly. Need to look into
    // emitting events from our tests instead of via entry point
    fn rm_me2(ref self: TContractState);

    /// Reads ///

    /// Other

    // Get the vault's  manaager address
    // @dev Better access control ? (oz permits ?)
    fn vault_manager(self: @TContractState) -> ContractAddress;

    // Get the type of vault (ITM | ATM | OTM)
    fn vault_type(self: @TContractState) -> VaultType;

    // Get the market aggregator address
    fn get_market_aggregator(self: @TContractState) -> ContractAddress;

    /// Rounds

    // @return the current option round id
    fn current_option_round_id(self: @TContractState) -> u256;

    // @return the contract address of the option round
    fn get_option_round_address(self: @TContractState, option_round_id: u256) -> ContractAddress;

    /// Liquidity

    // For LPs //

    // Get the liquidity an lp has locked
    fn get_lp_locked_balance(self: @TContractState, liquidity_provider: ContractAddress) -> u256;

    // Get the liquidity an LP has unlocked
    fn get_lp_unlocked_balance(self: @TContractState, liquidity_provider: ContractAddress) -> u256;

    // Get the total liquidity an LP has in the protocol
    fn get_lp_total_balance(self: @TContractState, liquidity_provider: ContractAddress) -> u256;

    // For Vault //

    // Get the total liquidity locked
    fn get_total_locked(self: @TContractState) -> u256;

    // Get the total liquidity unlocked
    fn get_total_unlocked(self: @TContractState) -> u256;

    // Get the total liquidity in the protocol
    fn get_total_balance(self: @TContractState,) -> u256;

    /// Premiums

    // Get the total premium LP has earned in the current round
    // @note premiums for previous rounds
    fn get_premiums_earned(
        self: @TContractState, liquidity_provider: ContractAddress, round_id: u256
    ) -> u256;

    // Get the total premiums collected by an LP in a round
    fn get_premiums_collected(
        self: @TContractState, liquidity_provider: ContractAddress, round_id: u256
    ) -> u256;

    // @note add get_premiums_collected to return how much if any an LP collects from a round (used to prevent draining premiums)

    /// Writes ///

    /// State transition

    // Start the auction on the next round as long as the current round is Settled and the
    // round transition period has passed. Deploys the next next round and updates the current/next pointers.
    fn start_auction(ref self: TContractState) -> bool;

    // End the auction in the current round as long as the current round is Auctioning and the auction
    // bidding period has ended.
    // @return the clearing price of the auction
    fn end_auction(ref self: TContractState) -> u256;

    // Settle the current option round as long as the current round is Running and the option expiry time has passed.
    fn settle_option_round(ref self: TContractState) -> bool;

    /// LP functions

    // LP increments their position and sends the liquidity to the next round
    // @note do we need a return value here ?
    fn deposit_liquidity(ref self: TContractState, amount: u256) -> u256;

    // LP withdraws from their position while in the round transition period
    fn withdraw_liquidity(ref self: TContractState, amount: u256);

    /// LP token related

    // LP converts their collateral into LP tokens
    // @note all at once or can LP convert a partial amount ?
    //  - logically i'm pretty sure they could do a partial amount (collecting all rewards in either case)
    fn convert_position_to_lp_tokens(ref self: TContractState, amount: u256);

    // LP converts their (source_round) LP tokens into a position in the current round
    // @dev Premiums/unsold from the source round are not counted
    fn convert_lp_tokens_to_position(ref self: TContractState, source_round: u256, amount: u256);

    // LP token owner converts an amount of source round tokens to target round tokens
    // @dev Rx tokens do not include premiums/unsold from rx (above)
    // This is not a problem for token -> position, but is a problem for
    // token -> token because when rx tokens convert to ry, the ry tokens should
    // be able to collect ry premiums but will not be able to (above)
    // @dev Ry must be running or settled. This way we can know the premiums that the rY tokens earned in the round, and collect them
    // as a deposit into the next round. We need to collect these rY premiums because the LP tokens need to represent the value of a
    // deposit in the round net any premiums from the round.
    // @dev If we do not collect the premiums for rY upon conversion, they would be lost.
    // @return the amount of target round tokens received
    // @dev move entry point to LPToken ?
    fn convert_lp_tokens_to_newer_lp_tokens(
        ref self: TContractState, source_round: u256, target_round: u256, amount: u256
    ) -> u256;
}

#[starknet::contract]
mod Vault {
    use pitch_lake_starknet::vault::IVault;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::token::erc20::interface::IERC20;
    use starknet::{
        ContractAddress, ClassHash, deploy_syscall, get_caller_address, contract_address_const,
        get_contract_address
    };
    use pitch_lake_starknet::vault::VaultType;
    use openzeppelin::utils::serde::SerializedAppend;
    use pitch_lake_starknet::option_round::{
        OptionRound, OptionRoundConstructorParams, StartAuctionParams, OptionRoundState,
        IOptionRoundDispatcher
    };
    use pitch_lake_starknet::market_aggregator::{IMarketAggregatorDispatcher};

    // testing
    use pitch_lake_starknet::tests::utils::structs::{mock_option_params};

    // Events
    #[event]
    #[derive(PartialEq, Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Withdrawal: Withdrawal,
        OptionRoundDeployed: OptionRoundDeployed,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct Deposit {
        #[key]
        account: ContractAddress,
        position_balance_before: u256,
        position_balance_after: u256,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct Withdrawal {
        #[key]
        account: ContractAddress,
        position_balance_before: u256,
        position_balance_after: u256,
    }


    #[derive(Drop, starknet::Event, PartialEq)]
    struct OptionRoundDeployed {
        // might not need
        round_id: u256,
        address: ContractAddress,
    // option_round_params: OptionRoundParams
    // possibly more members to this event
    }

    #[storage]
    struct Storage {
        vault_manager: ContractAddress,
        vault_type: VaultType,
        //current_option_round_params: OptionRoundParams,
        current_option_round_id: u256,
        market_aggregator: ContractAddress,
        round_addresses: LegacyMap<u256, ContractAddress>,
        premiums_collected: LegacyMap<(u256, ContractAddress), bool>,
    // liquidity_positions: LegacyMap<((ContractAddress, u256), u256)>,
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
        self.vault_type.write(vault_type);
        self.market_aggregator.write(market_aggregator);
        // @dev Deploy the 0th round as current (Settled) and deploy the 1st round (Open)
        let round_zero_constructor_args: OptionRoundConstructorParams =
            OptionRoundConstructorParams {
            vault_address: starknet::get_contract_address(), round_id: 0
        };
        let round_one_constructor_args: OptionRoundConstructorParams =
            OptionRoundConstructorParams {
            vault_address: starknet::get_contract_address(), round_id: 1
        };
        // Deploy 0th round
        let mut calldata = array![market_aggregator.into()];
        calldata.append_serde(round_zero_constructor_args);
        let (z_address, _) = deploy_syscall(
            option_round_class_hash, 'some salt', calldata.span(), false
        )
            .unwrap();
        // Deploy 1st round
        let mut calldata = array![market_aggregator.into()];
        calldata.append_serde(round_one_constructor_args);
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
        fn rm_me2(ref self: ContractState) {
            self
                .emit(
                    Event::OptionRoundDeployed(
                        OptionRoundDeployed {
                            round_id: 1, address: starknet::get_contract_address(),
                        }
                    )
                );
            self
                .emit(
                    Event::Deposit(
                        Deposit {
                            account: starknet::get_contract_address(),
                            position_balance_before: 100,
                            position_balance_after: 100
                        }
                    )
                );
            self
                .emit(
                    Event::Withdrawal(
                        Withdrawal {
                            account: starknet::get_contract_address(),
                            position_balance_before: 100,
                            position_balance_after: 100
                        }
                    )
                );
        }

        /// Reads ///

        /// Other

        fn vault_manager(self: @ContractState) -> ContractAddress {
            self.vault_manager.read()
        }

        fn vault_type(self: @ContractState) -> VaultType {
            self.vault_type.read()
        }

        fn get_market_aggregator(self: @ContractState) -> ContractAddress {
            self.market_aggregator.read()
        }

        /// Rounds

        fn current_option_round_id(self: @ContractState) -> u256 {
            // (for testing; need a deployed instance of round to avoid CONTRACT_NOT_DEPLOYED errors)
            0
        }

        fn get_option_round_address(
            self: @ContractState, option_round_id: u256
        ) -> ContractAddress {
            self.round_addresses.read(option_round_id)
        }

        /// Liquidity

        // For LPs //

        fn get_lp_locked_balance(
            self: @ContractState, liquidity_provider: ContractAddress
        ) -> u256 {
            100
        }

        fn get_lp_unlocked_balance(
            self: @ContractState, liquidity_provider: ContractAddress
        ) -> u256 {
            100
        }

        fn get_lp_total_balance(self: @ContractState, liquidity_provider: ContractAddress) -> u256 {
            100
        }

        // For Vault //

        fn get_total_locked(self: @ContractState) -> u256 {
            100
        }

        fn get_total_unlocked(self: @ContractState) -> u256 {
            100
        }

        fn get_total_balance(self: @ContractState,) -> u256 {
            100
        }

        /// Premiums

        fn get_premiums_earned(
            self: @ContractState, liquidity_provider: ContractAddress, round_id: u256
        ) -> u256 {
            100
        }

        fn get_premiums_collected(
            self: @ContractState, liquidity_provider: ContractAddress, round_id: u256
        ) -> u256 {
            100
        }

        /// Writes ///

        /// State transition

        fn settle_option_round(ref self: ContractState) -> bool {
            true
        }

        fn start_auction(ref self: ContractState) -> bool {
            true
        }

        fn end_auction(ref self: ContractState) -> u256 {
            100
        }

        /// OB functions
        fn deposit_liquidity(ref self: ContractState, amount: u256) -> u256 {
            1
        }

        fn withdraw_liquidity(ref self: ContractState, amount: u256) {}

        /// LP token related

        fn convert_position_to_lp_tokens(ref self: ContractState, amount: u256) {}

        fn convert_lp_tokens_to_position(
            ref self: ContractState, source_round: u256, amount: u256
        ) {}

        fn convert_lp_tokens_to_newer_lp_tokens(
            ref self: ContractState, source_round: u256, target_round: u256, amount: u256
        ) -> u256 {
            100
        }
    }
}
