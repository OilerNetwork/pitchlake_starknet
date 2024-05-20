use starknet::{ContractAddress};
use pitch_lake_starknet::option_round::{OptionRoundParams, OptionRoundState};
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
    fn rm_me2(ref self: TContractState);
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
    // @note do we need a return value here ?
    fn deposit_liquidity(ref self: TContractState, amount: u256) -> u256;

    // LP withdraws from their position while in the round transition period
    fn withdraw_liquidity(ref self: TContractState, amount: u256);

    // @note Discuss if there should be 1 withdraw function or two (1 for collecting
    // premium/unsold from current and 1 for withdrawing unallocated from next round)
    // LP collects from their unallocated balance
    fn collect_unallocated(ref self: TContractState, amount: u256);

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

    // Settle the current option round as long as the current round is Running and the option expiry time has passed.
    fn settle_option_round(ref self: TContractState) -> bool;

    // Start the auction on the next round as long as the current round is Settled and the
    // round transition period has passed. Deploys the next next round and updates the current/next pointers.
    fn start_auction(ref self: TContractState) -> bool;

    // End the auction in the current round as long as the current round is Auctioning and the auction
    // bidding period has ended.
    // @return the clearing price of the auction
    fn end_auction(ref self: TContractState) -> u256;

    // Get the market aggregator address
    fn get_market_aggregator(self: @TContractState) -> ContractAddress;

    fn is_premium_collected(self: @TContractState, lp: ContractAddress, round_id: u256) -> bool;
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
        OptionRound, OptionRoundConstructorParams, OptionRoundParams, OptionRoundState,
        IOptionRoundDispatcher
    };
    use pitch_lake_starknet::market_aggregator::{IMarketAggregatorDispatcher};

    // testing
    use pitch_lake_starknet::tests::utils::{mock_option_params};

    // Events
    #[event]
    #[derive(PartialEq, Drop, starknet::Event)]
    enum Event {
        Deposit: VaultTransfer,
        Withdrawal: VaultTransfer,
        OptionRoundCreated: OptionRoundCreated,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct VaultTransfer {
        #[key]
        user: ContractAddress,
        total_balance_before: u256,
        // Collateral + unallocated
        total_balance_now: u256,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct OptionRoundCreated {
        prev_round: ContractAddress,
        new_round: ContractAddress,
        collaterized_amount: u256,
        option_round_params: OptionRoundParams
    }

    #[storage]
    struct Storage {
        vault_manager: ContractAddress,
        vault_type: VaultType,
        current_option_round_params: OptionRoundParams,
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
                    Event::OptionRoundCreated(
                        OptionRoundCreated {
                            prev_round: starknet::get_contract_address(),
                            new_round: starknet::get_contract_address(),
                            collaterized_amount: 100,
                            option_round_params: mock_option_params(),
                        }
                    )
                );
            self
                .emit(
                    Event::Deposit(
                        VaultTransfer {
                            user: starknet::get_contract_address(),
                            total_balance_before: 100,
                            total_balance_now: 100
                        }
                    )
                );
            self
                .emit(
                    Event::Withdrawal(
                        VaultTransfer {
                            user: starknet::get_contract_address(),
                            total_balance_before: 100,
                            total_balance_now: 100
                        }
                    )
                );
        }
        /// Reads ///
        fn vault_manager(self: @ContractState) -> ContractAddress {
            self.vault_manager.read()
        }

        fn vault_type(self: @ContractState) -> VaultType {
            self.vault_type.read()
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

        fn is_premium_collected(self: @ContractState, lp: ContractAddress, round_id: u256) -> bool {
            self.premiums_collected.read((round_id, lp))
        }

        /// Writes ///
        fn deposit_liquidity(ref self: ContractState, amount: u256) -> u256 {
            1
        }

        fn withdraw_liquidity(ref self: ContractState, amount: u256) {}

        fn convert_position_to_lp_tokens(ref self: ContractState, amount: u256) {}

        fn convert_lp_tokens_to_position(
            ref self: ContractState, source_round: u256, amount: u256
        ) {}

        fn convert_lp_tokens_to_newer_lp_tokens(
            ref self: ContractState, source_round: u256, target_round: u256, amount: u256
        ) -> u256 {
            100
        }

        fn settle_option_round(ref self: ContractState) -> bool {
            true
        }

        fn start_auction(ref self: ContractState) -> bool {
            true
        }

        fn end_auction(ref self: ContractState) -> u256 {
            100
        }

        fn get_market_aggregator(self: @ContractState) -> ContractAddress {
            self.market_aggregator.read()
        }
        fn collect_unallocated(ref self: ContractState, amount: u256) {}
    }
}
