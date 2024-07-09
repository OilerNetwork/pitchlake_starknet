use starknet::{ContractAddress};
use pitch_lake_starknet::contracts::{
    option_round::{StartAuctionParams, OptionRoundState},
    market_aggregator::{IMarketAggregator, IMarketAggregatorDispatcher},
    vault::Vault::{VaultType, VaultError},
};

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

    // Get the ETH address
    fn eth_address(self: @TContractState) -> ContractAddress;

    // Get the round transition period
    fn get_round_transition_period(self: @TContractState) -> u64;

    // @note Add getters for auction run time & option run time
    // - need to also add to facade, then use in tests for the (not yet created) setters (A1.1)

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
    fn get_total_locked_balance(self: @TContractState) -> u256;

    // Get the total liquidity unlocked
    fn get_total_unlocked_balance(self: @TContractState) -> u256;

    // Get the total liquidity in the protocol
    fn get_total_balance(self: @TContractState,) -> u256;

    /// Premiums

    // Get the total premium LP has earned in the current round
    // @note premiums for previous rounds
    // @note, not sure this function is easily implementable, if a user accuates their position, the
    // storage mappings would not be able to correclty value the position in the round_id, to know the
    // amount of premiums earned in the round_id. We would need to modify the checkpoints to be a mapping
    // instead of a single value (i.e. checkpoint 1 == x, checkpoint 2 == y, along with keeping track of
    // the checkpoint nonces)
    fn get_premiums_earned(
        self: @TContractState, liquidity_provider: ContractAddress, round_id: u256
    ) -> u256;

    // Get the total premiums collected by an LP in a round
    fn get_premiums_collected(
        self: @TContractState, liquidity_provider: ContractAddress, round_id: u256
    ) -> u256;

    // Get the amount of unsold liquidity for a round
    fn get_unsold_liquidity(self: @TContractState, round_id: u256) -> u256;

    /// Writes ///

    /// State transition

    // Start the auction on the next round as long as the current round is Settled and the
    // round transition period has passed. Deploys the next next round and updates the current/next pointers.
    // @return the total options available in the auction
    fn start_auction(ref self: TContractState) -> Result<u256, VaultError>;

    // End the auction in the current round as long as the current round is Auctioning and the auction
    // bidding period has ended.
    // @return the clearing price of the auction
    // @return the total options sold in the auction (@note keep or drop ?)
    fn end_auction(ref self: TContractState) -> Result<(u256, u256), VaultError>;

    // Settle the current option round as long as the current round is Running and the option expiry time has passed.
    // @return The total payout of the option round
    fn settle_option_round(ref self: TContractState) -> Result<u256, VaultError>;

    /// LP functions

    // Liquditiy provider deposits to the vault for the upcoming round
    // @return The liquidity provider's updated unlocked position
    fn deposit_liquidity(
        ref self: TContractState, amount: u256, liquidity_provider: ContractAddress
    ) -> Result<u256, VaultError>;

    // Liquidity provider withdraws from the vailt
    // @return The liquidity provider's updated unlocked position
    fn withdraw_liquidity(
        ref self: TContractState, amount: u256
    ) -> Result<u256, Vault::VaultError>;

    /// LP token related

    // Phase C ?

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
    ) -> Result<u256, VaultError>;
}

#[starknet::contract]
mod Vault {
    use starknet::{
        ContractAddress, ClassHash, deploy_syscall, get_caller_address, contract_address_const,
        get_contract_address, get_block_timestamp
    };
    use openzeppelin::{
        token::erc20::{
            ERC20Component, interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait,}
        },
        utils::serde::SerializedAppend
    };
    use pitch_lake_starknet::contracts::{
        vault::{IVault},
        option_round::{
            OptionRound,
            OptionRound::{
                OptionRoundErrorIntoFelt252, OptionRoundConstructorParams, StartAuctionParams,
                SettleOptionRoundParams, OptionRoundState
            },
            IOptionRoundDispatcher, IOptionRoundDispatcherTrait,
        },
        market_aggregator::{IMarketAggregatorDispatcher}
    };

    // The type of vault
    #[derive(starknet::Store, Copy, Drop, Serde, PartialEq)]
    enum VaultType {
        InTheMoney,
        AtTheMoney,
        OutOfMoney,
    }

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
        // The address for the ETH contract
        eth_address: ContractAddress,
        option_round_class_hash: ClassHash,
        // The amount liquidity providers deposit into each round: (liquidity_provider, round_id) -> deposit_amount
        positions: LegacyMap<(ContractAddress, u256), u256>,
        // Withdraw checkpoints: (liquidity_provider) -> round_id
        withdraw_checkpoints: LegacyMap<ContractAddress, u256>,
        // Total unlocked liquidity
        total_unlocked_balance: u256,
        // Total locked liquidity
        total_locked_balance: u256,
        // The amount of premiums a liquidity provider collects from each round: (liquidity_provider, round_id) -> collected_amount
        premiums_collected: LegacyMap<(ContractAddress, u256), u256>,
        // The amount of liquidity not sold during each round's auction (if any): (round_id) -> unsold_liquidity
        unsold_liquidity: LegacyMap<u256, u256>,
        // The id of the current option round
        current_option_round_id: u256,
        ///////
        ///////
        vault_manager: ContractAddress,
        vault_type: VaultType,
        market_aggregator: ContractAddress,
        round_addresses: LegacyMap<u256, ContractAddress>,
        round_transition_period: u64,
        auction_run_time: u64,
        option_run_time: u64,
    }

    // @note Need to add eth address as a param here
    //  - Will need to update setup functions to accomodate
    #[constructor]
    fn constructor(
        ref self: ContractState,
        eth_address: ContractAddress,
        vault_manager: ContractAddress,
        vault_type: VaultType,
        market_aggregator: ContractAddress,
        option_round_class_hash: ClassHash,
    ) {
        self.eth_address.write(eth_address);
        self.vault_manager.write(vault_manager);
        self.vault_type.write(vault_type);
        self.market_aggregator.write(market_aggregator);
        self.option_round_class_hash.write(option_round_class_hash);

        // Setting placeholder values for storage vars because if left as 0
        // tests fail that should not
        // @note Should pass these in the constructor
        // - Need to update the setup functions to accomodate (and a couple tests)
        self.round_transition_period.write(123);
        self.auction_run_time.write(123);
        self.option_run_time.write(123);

        // @dev Deploy the 1st option round
        self.deploy_next_round();
    }

    #[derive(Copy, Drop, Serde)]
    enum VaultError {
        // Error from OptionRound contract
        OptionRoundError: OptionRound::OptionRoundError,
        // Withdrawal exceeds unlocked position
        InsufficientBalance,
    }

    impl VaultErrorIntoFelt252Trait of Into<VaultError, felt252> {
        fn into(self: VaultError) -> felt252 {
            match self {
                VaultError::OptionRoundError(e) => { e.into() },
                VaultError::InsufficientBalance => { 'Vault: Insufficient balance' }
            }
        }
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

        fn eth_address(self: @ContractState) -> ContractAddress {
            self.eth_address.read()
        }

        fn get_round_transition_period(self: @ContractState) -> u64 {
            self.round_transition_period.read()
        }

        /// Rounds

        fn current_option_round_id(self: @ContractState) -> u256 {
            self.current_option_round_id.read()
        }

        fn get_option_round_address(
            self: @ContractState, option_round_id: u256
        ) -> ContractAddress {
            self.round_addresses.read(option_round_id)
        }

        fn get_unsold_liquidity(self: @ContractState, round_id: u256) -> u256 {
            self.unsold_liquidity.read(round_id)
        }

        /// Liquidity

        // For liquidity providers

        // Get the value of a liquidity provider's position that is locked
        fn get_lp_locked_balance(
            self: @ContractState, liquidity_provider: ContractAddress
        ) -> u256 {
            // Get a dispatcher for the current round
            let current_round_id = self.current_option_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            // @dev If the current round is Open, no liquidity is locked
            if (current_round.get_state() == OptionRoundState::Open) {
                0
            } // @dev If the current round is Auctioning or Running, the liquidity provider's
            // locked balance is their remaining balance from the previous round and their deposit
            // for the current round
            else {
                // The liquidity provider's deposit for the current round
                let current_round_deposit = self
                    .positions
                    .read((liquidity_provider, current_round_id));
                // The liquidity provider's position value at the end of the previous round
                let previous_round_id = current_round_id - 1;
                let previous_round_remaining_balance = self
                    .calculate_value_of_position_from_checkpoint_to_round(
                        liquidity_provider, previous_round_id
                    );
                previous_round_remaining_balance + current_round_deposit
            }
        }

        // Get the value of a liquidity provider's position that is unlocked
        fn get_lp_unlocked_balance(
            self: @ContractState, liquidity_provider: ContractAddress
        ) -> u256 {
            // @param remaining_liquidity: The value of the position at the end of the previous round
            // @param collectable_balance: The value of the premiums/unsold liquidity in the current round that
            // the liquidity provider has not yet collected
            // @param upcoming_round_deposit: The value of the liquidity provider's deposit for the upcoming round
            let (remaining_liquidity, collectable_balance, upcoming_round_deposit) = self
                .get_lp_unlocked_balance_internal(liquidity_provider);
            remaining_liquidity + collectable_balance + upcoming_round_deposit
        }

        fn get_lp_total_balance(self: @ContractState, liquidity_provider: ContractAddress) -> u256 {
            self.get_lp_locked_balance(liquidity_provider)
                + self.get_lp_unlocked_balance(liquidity_provider)
        }

        // For Vault //

        fn get_total_locked_balance(self: @ContractState) -> u256 {
            self.total_locked_balance.read()
        }

        fn get_total_unlocked_balance(self: @ContractState) -> u256 {
            self.total_unlocked_balance.read()
        }

        fn get_total_balance(self: @ContractState,) -> u256 {
            self.get_total_locked_balance() + self.get_total_unlocked_balance()
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
            self.premiums_collected.read((liquidity_provider, round_id))
        }

        /// Writes ///

        /// State transition

        fn start_auction(ref self: ContractState) -> Result<u256, VaultError> {
            // Get a dispatcher for the current option round
            let current_round_id = self.current_option_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);

            // The liquidity being locked at the start of the round
            let starting_liquidity = self.get_total_unlocked_balance();

            // Calculate the total options available to sell in the auction
            let total_options_available = self
                .calculate_total_options_available(starting_liquidity);

            // @note replace with individual getters, add strike price
            let reserve_price = self.fetch_reserve_price();
            let cap_level = self.fetch_cap_level();
            let strike_price = self.fetch_strike_price();
            // Try to start the auction on the current round
            let res = current_round
                .start_auction(
                    StartAuctionParams {
                        total_options_available,
                        starting_liquidity,
                        reserve_price,
                        cap_level,
                        strike_price
                    }
                );
            match res {
                Result::Ok(total_options_available) => {
                    // Update total_locked_liquidity
                    self.total_locked_balance.write(starting_liquidity);

                    // Update total_unlocked_liquidity
                    self.total_unlocked_balance.write(0);

                    // Return the total options available
                    Result::Ok(total_options_available)
                },
                Result::Err(err) => { Result::Err(VaultError::OptionRoundError(err)) }
            }
        }

        fn end_auction(ref self: ContractState) -> Result<(u256, u256), VaultError> {
            // Get a dispatcher for the current round
            let current_round_id = self.current_option_round_id();
            let current_round = self.get_round_dispatcher(current_round_id);

            // Try to end the auction on the option round
            let res = current_round.end_auction();
            match res {
                Result::Ok((
                    clearing_price, total_options_sold
                )) => {
                    // Amount of liquidity currently locked and unlocked
                    let mut locked_liquidity = self.get_total_locked_balance();
                    let mut unlocked_liquidity = self.get_total_unlocked_balance();

                    // Premiums earned from the auction are unlocked for liquidity providers to withdraw
                    unlocked_liquidity += current_round.total_premiums();

                    // Handle any unsold liquidity
                    let total_options_available = current_round.get_total_options_available();
                    if (total_options_sold < total_options_available) {
                        // Number of options that did not sell
                        let unsold_options = total_options_available - total_options_sold;

                        // Portion of the locked liquidity these unsold options represent
                        // @note Consider adding precision factor
                        let unsold_liquidity = (locked_liquidity * unsold_options)
                            / total_options_available;

                        // Decrement locked liquidity by the unsold liquidity and
                        // update the storage variable
                        locked_liquidity -= unsold_liquidity;
                        self.total_locked_balance.write(locked_liquidity);

                        // Increment unlocked liquidity by the unsold liquidity
                        unlocked_liquidity += unsold_liquidity;

                        // Store how the unsold liquidity for this round for future balance calculations
                        self.unsold_liquidity.write(current_round_id, unsold_liquidity);
                    }

                    // Update the total_unlocked_balance storage variable
                    self.total_unlocked_balance.write(unlocked_liquidity);

                    // Return the clearing_price & total_options_sold
                    return Result::Ok((clearing_price, total_options_sold));
                },
                Result::Err(e) => { Result::Err(VaultError::OptionRoundError(e)) }
            }
        }

        fn settle_option_round(ref self: ContractState) -> Result<u256, VaultError> {
            // Get a dispatcher for the current option round
            let current_round_id = self.current_option_round_id();
            let current_round_dispatcher = self.get_round_dispatcher(current_round_id);

            // Fetch the price to settle the option round
            let settlement_price = self.fetch_settlement_price();

            // Try to settle the option round
            let res = current_round_dispatcher
                .settle_option_round(SettleOptionRoundParams { settlement_price });
            match res {
                Result::Ok(total_payout) => {
                    // @dev Checking if payout > 0 to save gas if there is no payout
                    let mut remaining_liquidity = self.get_total_locked_balance();
                    if (total_payout > 0) {
                        // Transfer total payout from the vault to the settled option round
                        let eth_dispatcher = self.get_eth_dispatcher();
                        eth_dispatcher
                            .transfer(current_round_dispatcher.contract_address, total_payout);
                        // The remaining liquidity for a round is how much was locked minus the total payout
                        remaining_liquidity -= total_payout;
                    }

                    // The locked liquidity becomes 0 and the remaining liquidity becomes unlocked
                    self.total_locked_balance.write(0);
                    let total_unlocked_balance_before = self.get_total_unlocked_balance();
                    self
                        .total_unlocked_balance
                        .write(remaining_liquidity + total_unlocked_balance_before);

                    // Deploy next option round contract, update current round id & round address mapping
                    self.deploy_next_round();

                    // Return the total payout of the option round
                    Result::Ok(total_payout)
                },
                Result::Err(err) => { Result::Err(VaultError::OptionRoundError(err)) },
            }
        }

        /// Liquidity provider functions

        // Caller deposits liquidity on behalf of the liquidity provider for the upcoming round
        fn deposit_liquidity(
            ref self: ContractState, amount: u256, liquidity_provider: ContractAddress
        ) -> Result<u256, VaultError> {
            // The liquidity provider's total unlocked balance before and after the deposit
            let lp_unlocked_balance_before = self.get_lp_unlocked_balance(liquidity_provider);
            let lp_unlocked_balance_after = lp_unlocked_balance_before + amount;

            // Get a dispatcher for the current round
            let current_round_id = self.current_option_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);

            // Update the total unlocked balance of the vault
            let total_unlocked_balance_before = self.get_total_unlocked_balance();
            self.total_unlocked_balance.write(total_unlocked_balance_before + amount);

            // Update the liquidity provider's deposit value in the mapping for the upcoming round
            let upcoming_round_id = self.get_upcoming_round_id(@current_round);
            let upcoming_round_deposit = self
                .positions
                .read((liquidity_provider, upcoming_round_id));
            self
                .positions
                .write((liquidity_provider, upcoming_round_id), upcoming_round_deposit + amount);

            // Transfer the deposit to this contract (from caller to vault)
            let eth = self.get_eth_dispatcher();
            eth.transfer_from(get_caller_address(), get_contract_address(), amount);

            // Emit deposit event
            self
                .emit(
                    Event::Deposit(
                        Deposit {
                            account: liquidity_provider,
                            position_balance_before: lp_unlocked_balance_before,
                            position_balance_after: lp_unlocked_balance_after
                        }
                    )
                );

            // Return the liquidity provider's updated unlocked balance
            Result::Ok(lp_unlocked_balance_after)
        }

        // Caller withdraws liquidity from their unlocked balance
        fn withdraw_liquidity(ref self: ContractState, amount: u256) -> Result<u256, VaultError> {
            // Get the liquidity provider's unlocked balance broken up into its components
            let liquidity_provider = get_caller_address();
            let (remaining_liquidity, collectable_balance, upcoming_round_deposit) = self
                .get_lp_unlocked_balance_internal(liquidity_provider);
            let lp_unlocked_balance = remaining_liquidity
                + collectable_balance
                + upcoming_round_deposit;

            // Assert the amount being withdrawn is <= the liquidity provider's unlocked balance
            if (amount > lp_unlocked_balance) {
                return Result::Err(VaultError::InsufficientBalance);
            }

            // If the amount being withdrawn is <= the upcoming round deposit, we only need to update the
            // liquidity provider's position in storage for the upcoming round
            let current_round_id = self.current_option_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            let upcoming_round_id = self.get_upcoming_round_id(@current_round);
            let upcoming_round_deposit_after_withdraw = if (amount <= upcoming_round_deposit) {
                upcoming_round_deposit - amount
            } else {
                0
            };
            self
                .positions
                .write(
                    (liquidity_provider, upcoming_round_id), upcoming_round_deposit_after_withdraw
                );

            // If the amount being withdrawn is > the upcoming round deposit, this means it is coming from
            // another component of the liquidity provider's unlocked balance, depending on the state
            // of the current round
            if (amount > upcoming_round_deposit) {
                // @dev If the current round is Auctioning, then the unlocked balance is only the upcoming round deposit,
                // and was therefore handled in the previous conditional
                let current_round_id = self.current_option_round_id.read();
                let current_round = self.get_round_dispatcher(current_round_id);
                // @dev If the current round is Running, then the remaining withdraw amount (amount difference) is coming
                // from the collectable balance
                let amount_difference = amount - upcoming_round_deposit;
                if (current_round.get_state() == OptionRoundState::Running) {
                    let premiums_already_collected = self
                        .premiums_collected
                        .read((liquidity_provider, current_round_id));
                    self
                        .premiums_collected
                        .write(
                            (liquidity_provider, current_round_id),
                            premiums_already_collected + amount_difference
                        );
                } // @dev If the current round is Open, then the remaining withdraw amount is coming from the
                // remaining liquidity of the previous round; therefore, we need to accuate the liquidity provider's
                // position in storage (update the checkpoint and deposit amount)
                else {
                    let updated_remaining_liquidity = remaining_liquidity - amount_difference;
                    self
                        .positions
                        .write((liquidity_provider, current_round_id), updated_remaining_liquidity);
                    self.withdraw_checkpoints.write(liquidity_provider, current_round_id);
                }
            }

            // Update the total unlocked balance of the vault
            self.total_unlocked_balance.write(self.get_total_unlocked_balance() - amount);

            // Transfer eth from Vault to caller
            let eth = self.get_eth_dispatcher();
            eth.transfer(liquidity_provider, amount);

            // Emit withdrawal event
            let updated_lp_unlocked_balance = lp_unlocked_balance - amount;
            self
                .emit(
                    Event::Withdrawal(
                        Withdrawal {
                            account: liquidity_provider,
                            position_balance_before: lp_unlocked_balance,
                            position_balance_after: updated_lp_unlocked_balance,
                        }
                    )
                );

            // Return the value of the caller's unlocked position after the withdrawal
            Result::Ok(updated_lp_unlocked_balance)
        }

        /// LP token related

        fn convert_position_to_lp_tokens(ref self: ContractState, amount: u256) {}

        fn convert_lp_tokens_to_position(
            ref self: ContractState, source_round: u256, amount: u256
        ) {}

        fn convert_lp_tokens_to_newer_lp_tokens(
            ref self: ContractState, source_round: u256, target_round: u256, amount: u256
        ) -> Result<u256, VaultError> {
            Result::Ok(1)
        }
    }


    // Internal Functions
    #[generate_trait]
    impl InternalImpl of VaultInternalTrait {
        // Get a dispatcher for the ETH contract
        fn get_eth_dispatcher(self: @ContractState) -> IERC20Dispatcher {
            let eth_address: ContractAddress = self.eth_address();
            IERC20Dispatcher { contract_address: eth_address }
        }

        // Get a dispatcher for the Vault
        fn get_round_dispatcher(self: @ContractState, round_id: u256) -> IOptionRoundDispatcher {
            let round_address = self.get_option_round_address(round_id);
            IOptionRoundDispatcher { contract_address: round_address }
        }

        // Deploy the next option round contract, update the current round id & round address mapping
        fn deploy_next_round(ref self: ContractState) {
            // The round id for the next round
            let next_round_id = self.current_option_round_id() + 1;

            // The constructor params for the next round
            let mut calldata: Array<felt252> = array![];
            // Vault address & round id
            calldata.append_serde(starknet::get_contract_address()); // vault address
            calldata.append_serde(next_round_id); // option round id
            // Dates
            let now = starknet::get_block_timestamp();
            let auction_start_date = now + self.round_transition_period.read();
            let auction_end_date = auction_start_date + self.auction_run_time.read();
            let option_settlement_date = auction_end_date + self.option_run_time.read();
            calldata.append_serde(auction_start_date); // auction start date
            calldata.append_serde(auction_end_date);
            calldata.append_serde(option_settlement_date);
            // Reserve price, cap level, & strike price
            calldata.append_serde(self.fetch_reserve_price());
            calldata.append_serde(self.fetch_cap_level());
            calldata.append_serde(self.fetch_strike_price());

            // Deploy the next option round contract
            let (next_round_address, _) = deploy_syscall(
                self.option_round_class_hash.read(), 'some salt', calldata.span(), false
            )
                .unwrap();

            // Update the current round id & round address mapping
            self.current_option_round_id.write(next_round_id);
            self.round_addresses.write(next_round_id, next_round_address);

            // Emit option round deployed event
            self
                .emit(
                    Event::OptionRoundDeployed(
                        OptionRoundDeployed { round_id: next_round_id, address: next_round_address }
                    )
                );
        }

        // Helper function to return the liquidity provider's unlocked balance broken up into its components
        // @return (previous_round_remaining_balance, current_round_collectable_balance, upcoming_round_deposit)
        // @dev A user's unlocked balance could be a combination of their: remaining balance at the end of the previous round,
        // their portion of the current round's total premiums/unsold liquidity (minus any premiums/unsold liquidity not yet collected),
        // and their deposit for the upcoming round, depending on the state of the current round
        // - If auctioning, returns {0, 0, upcoming_round_deposit}.
        // - If running, returns {0, collectable_balance, upcoming_round_deposit}
        // - If open, returns {remaining_liquidity_from_previous_round, 0, upcoming_round_deposit}
        fn get_lp_unlocked_balance_internal(
            self: @ContractState, liquidity_provider: ContractAddress
        ) -> (u256, u256, u256) {
            // Get the liquidity provider's deposit for the upcoming round
            let current_round_id = self.current_option_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            let upcoming_round_id = self.get_upcoming_round_id(@current_round);
            let upcoming_round_deposit = self
                .positions
                .read((liquidity_provider, upcoming_round_id));

            // @dev If the current round is Auctioning, then the liquidity provider's unlocked balance
            // is only their deposit for the upcoming round
            // @dev This is because their remaining balance from the previous round is locked in the current round,
            // and the auction has not ended (no premiums/unsold liquidity yet)
            if (current_round.get_state() == OptionRoundState::Auctioning) {
                (0, 0, upcoming_round_deposit)
            } else {
                // The liquidity provider's position value at the end of the previous round (start of the current round)
                let previous_round_id = current_round_id - 1;
                let previous_round_remaining_balance = self
                    .calculate_value_of_position_from_checkpoint_to_round(
                        liquidity_provider, previous_round_id
                    );

                // @dev If the current round is Open, then the liquidity provider's unlocked balance is
                // their deposit for the upcoming round, and their remaining balance from the previous round
                // @dev The auction has not started so there are no premiums/unsold liquidity to collect
                if (current_round.get_state() == OptionRoundState::Open) {
                    (previous_round_remaining_balance, 0, upcoming_round_deposit)
                } // @dev If the current round is Running, then the liquidity provider's unlocked balance is
                // their deposit for the upcoming round and their share of the current round's collectable balance
                // (premiums and unsold liquidity)
                // @dev Their remaining balance from the previous round is locked in the current round
                else {
                    // The total collectable balance for the current round
                    let total_collectable = current_round.total_premiums()
                        + self.unsold_liquidity.read(current_round_id);
                    // Calculate the liquidity provider's share of the total collectable balance
                    // @dev The liquidity provider's share is proportional to the amount of liquidity they
                    // had in the previous round + the amount they deposited for the current round
                    let lp_weight_total = previous_round_remaining_balance
                        + self.positions.read((liquidity_provider, current_round_id));
                    let lp_collectable = (total_collectable * lp_weight_total)
                        / current_round.starting_liquidity();

                    // Get the amount that the liquidity provider has already collected
                    let lp_collected = self
                        .get_premiums_collected(liquidity_provider, current_round_id);

                    (0, lp_collectable - lp_collected, upcoming_round_deposit)
                }
            }
        }


        // Calculate the value of the liquidity provider's position from
        // their checkpoint to the end of the the ending round
        fn calculate_value_of_position_from_checkpoint_to_round(
            self: @ContractState, liquidity_provider: ContractAddress, ending_round_id: u256
        ) -> u256 {
            // Ending round must be Settled to calculate the value of the position at the end of it
            // @dev If the ending round is 0, it means the first round of the protocol is Open,
            // and therefore the value of the position is 0
            if (ending_round_id == 0) {
                0
            } else {
                // Assert the ending round is Settled
                if (self
                    .get_round_dispatcher(ending_round_id)
                    .get_state() != OptionRoundState::Settled) {
                    panic!(
                        "Vault: Ending round must be Settled to calculate the value of the position at the end of it"
                    );
                }
                // Last round the liquidity provider withdrew from
                let checkpoint = self.withdraw_checkpoints.read(liquidity_provider);
                // @dev The first round of the protocol is 1, therefore if the checkpoint is 0
                // we need to start at round 1
                let mut i = match checkpoint == 0 {
                    true => 1,
                    false => checkpoint
                };

                // Value of the position at the end of each round
                let mut ending_amount = 0;
                loop {
                    if (i > ending_round_id) {
                        // Now ending amount is equal to the value of the position at the end of the ending round
                        break (ending_amount);
                    } else {
                        // Include the deposit into this round
                        ending_amount += self.positions.read((liquidity_provider, i));

                        // How much liquidity remained in this round
                        let this_round = self.get_round_dispatcher(i);
                        let remaininig_liquidity = this_round.starting_liquidity()
                            + this_round.total_premiums()
                            - this_round.total_payout()
                            - self.unsold_liquidity.read(i);

                        // What portion of the remaining liquidity the liquidity provider owned
                        let mut lp_portion_of_remaining_liquidity = (remaininig_liquidity
                            * ending_amount)
                            / this_round.starting_liquidity();

                        // Subtract out any premiums and unsold liquidity the liquidity provider
                        // already collected from this round
                        ending_amount = lp_portion_of_remaining_liquidity
                            - self.get_premiums_collected(liquidity_provider, i);

                        i += 1;
                    }
                }
            }
        }

        // Get the upcoming round id
        fn get_upcoming_round_id(
            self: @ContractState, current_round: @IOptionRoundDispatcher
        ) -> u256 {
            let current_round = *current_round;
            let current_round_id = current_round.get_round_id();
            match current_round.get_state() {
                // @dev If the current round is Open, we are in the round transition period and the
                // the current round is about to start (is the upcoming round)
                OptionRoundState::Open => current_round_id,
                // @dev Else, the current round is either Auctioning or Running, and the
                // next round is the upcoming round
                _ => current_round_id + 1
            }
        }

        // Functions to return the reserve price, strike price, and cap level for the upcoming round
        // from Fossil
        // @note Fetch values upon deployment, if there are newer (less stale) vaules at the time of auction start,
        // we use the newer values to set the params
        // Phase F (fossil)

        fn fetch_reserve_price(self: @ContractState) -> u256 {
            1000000
        }

        fn fetch_cap_level(self: @ContractState) -> u256 {
            1000000
        }

        fn fetch_strike_price(self: @ContractState) -> u256 {
            1000000
        }

        fn fetch_settlement_price(self: @ContractState) -> u256 {
            2 * self.get_round_dispatcher(self.current_option_round_id()).get_reserve_price()
        }

        fn calculate_total_options_available(
            self: @ContractState, starting_liquidity: u256
        ) -> u256 {
            //Calculate total options accordingly
            100000000
        }
    }
}
