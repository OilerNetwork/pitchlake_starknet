use starknet::{ContractAddress};
use pitch_lake_starknet::option_round::{OptionRoundParams, OptionRoundState};
use pitch_lake_starknet::market_aggregator::{IMarketAggregator, IMarketAggregatorDispatcher};

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
    // @note do we need a return value here ? 
    fn deposit_liquidity(ref self: TContractState, amount: u256) -> u256;

    // LP withdraws from their position while in the round transition period
    fn withdraw_liquidity(ref self: TContractState, amount: u256);

    // LP converts their collateral into LP tokens
    // @note all at once or can LP convert a partial amount ? 
    //  - logically i'm pretty sure they could do a partial amount (collecting all rewards in either case)
    fn convert_position_to_lp_tokens(ref self: TContractState, amount: u256);

    // LP converts their (source_round) LP tokens into a position in the current round
    // @dev Premiums/unsold from the source round are not counted
    fn convert_lp_tokens_to_position(ref self: TContractState, source_round: u256, amount: u256);

    // rx_tokens -> ry_tokens ? 
    // @dev Rx tokens do not include premiums/unsold from rx (above) 
    // This is not a problem for token -> position, but is a problem for
    // token -> token because when rx tokens convert to ry, the ry tokens should
    // be able to collect ry premiums but will not be able to (above)
    // @dev One solution is to take the amount of premiums/unallocated from ry that will get ignored, and
    // add it to the ry token amount, this way when when the vault arbitrarily looks at the ry tokens,
    // it can ignore the premiums/unsold from ry as it should, but the LP will still get their value.
    // @dev if y is open, premiums are not known yet, so we could not add them in (so they will be properly ignored in the future)
    //  - if y is open, y-1 must be settled, if < settled then we do not know the conversion rate for payout in y-1 -> y
    // @dev if y is auctioning, premiums are not known yet, so we could do the same, not include them in the conversion
    // @dev if y is running, act as mentioned previously (include them in the amount so they when ignored in the future they are still counted)
    // @dev if y is settled, perform the same as running
    // The point of converting token -> token is to stay liquid but also have access to the most liquidity/buyers
    // If you have r3 tokens, and the current round is 50, there are probably fewer buyers for the r3 tokens than
    // r49 or r50 tokens
    // @return the amount of target round tokens received
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
    fn end_auction(ref self: TContractState) -> u256;

    // @note needed ? 
    fn get_market_aggregator(self: @TContractState) -> ContractAddress;
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


    #[storage]
    struct Storage {
        vault_manager: ContractAddress,
        current_option_round_params: OptionRoundParams,
        current_option_round_id: u256,
        market_aggregator: ContractAddress,
        round_addresses: LegacyMap<u256, ContractAddress>,
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
    }
}
