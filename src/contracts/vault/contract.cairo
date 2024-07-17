#[starknet::contract]
mod Vault {
    use starknet::{
        ContractAddress, ClassHash, deploy_syscall, get_caller_address, contract_address_const,
        get_contract_address, get_block_timestamp
    };
    use openzeppelin::{
        token::erc20::{ERC20Component, interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait,}},
        utils::serde::SerializedAppend
    };
    use pitch_lake_starknet::{
        contracts::{
            vault::interface::IVault,
            option_round::{
                contract::OptionRound,
                interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait},
            },
            market_aggregator::{IMarketAggregatorDispatcher}
        },
        types::{
            OptionRoundConstructorParams, StartAuctionParams, SettleOptionRoundParams,
            OptionRoundState, VaultType, Errors
        }
    };

    // The type of vault
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


    // *************************************************************************
    //                              STORAGE
    // *************************************************************************
    // Note: Write description of any storage variable here->
    // @eth_address: Address for eth contract
    // @option_round_class_hash: Hash for the latest implementation of OptionRound class
    // @position: The amount liquidity providers deposit into each round: (liquidity_provider, round_id) -> deposit_amount
    // @withdraw_checkpoints: Withdraw checkpoints: (liquidity_provider) -> round_id
    // @total_unlocked_balance: Total unlocked liquidity
    // @total_locked_balance: Total locked liquidity
    // @premiums_collected:The amount of premiums a liquidity provider collects from each round: (liquidity_provider, round_id) -> collected_amount
    // @unsold_liquidity: The amount of liquidity not sold during each round's auction (if any): (round_id) -> unsold_liquidity
    // @current_option_round_id: The id of the current option round
    // @round_addresses: Mapping of round id -> round address
    // @round_transition_period: Time between settling of current round and starting of next round
    // @auction_run_time: running time for the auction
    //
    #[storage]
    struct Storage {
        eth_address: ContractAddress,
        option_round_class_hash: ClassHash,
        positions: LegacyMap<(ContractAddress, u256), u256>,
        withdraw_checkpoints: LegacyMap<ContractAddress, u256>,
        total_unlocked_balance: u256,
        total_locked_balance: u256,
        premiums_collected: LegacyMap<(ContractAddress, u256), u256>,
        unsold_liquidity: LegacyMap<u256, u256>,
        current_option_round_id: u256,
        vault_manager: ContractAddress,
        vault_type: VaultType,
        market_aggregator: ContractAddress,
        round_addresses: LegacyMap<u256, ContractAddress>,
        round_transition_period: u64,
        auction_run_time: u64,
        option_run_time: u64,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        round_transition_period: u64,
        auction_run_time: u64,
        option_run_time: u64,
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
        self.round_transition_period.write(round_transition_period);
        self.auction_run_time.write(auction_run_time);
        self.option_run_time.write(option_run_time);

        // @dev Deploy the 1st option round
        self.deploy_next_round();
    }


    #[abi(embed_v0)]
    impl VaultImpl of IVault<ContractState> {
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

        fn get_auction_run_time(self: @ContractState) -> u64 {
            self.auction_run_time.read()
        }

        fn get_option_run_time(self: @ContractState) -> u64 {
            self.option_run_time.read()
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
                // Total unsold liquidity for the current round
                let round_unsold_liquidity = self.unsold_liquidity.read(current_round_id);
                // Lp portion of the unsold liquidity
                let lp_unsold_liquidity = (round_unsold_liquidity
                    * (previous_round_remaining_balance + current_round_deposit))
                    / current_round.starting_liquidity();

                previous_round_remaining_balance + current_round_deposit - lp_unsold_liquidity
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

        fn start_auction(ref self: ContractState) -> u256 {
            // Get a dispatcher for the current option round
            let current_round_id = self.current_option_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);

            // The liquidity being locked at the start of the round
            let starting_liquidity = self.get_total_unlocked_balance();

            // Calculate the total options available to sell in the auction
            let total_options_available = self
                .calculate_total_options_available(starting_liquidity);

            // Update total_locked_liquidity
            self.total_locked_balance.write(starting_liquidity);

            // Update total_unlocked_liquidity
            self.total_unlocked_balance.write(0);

            // Fetch params to start the auction
            let reserve_price = self.fetch_reserve_price();
            let cap_level = self.fetch_cap_level();
            let strike_price = self.fetch_strike_price();

            // Start the auction on the current round and return the total options available
            current_round
                .start_auction(
                    StartAuctionParams {
                        total_options_available,
                        starting_liquidity,
                        reserve_price,
                        cap_level,
                        strike_price
                    }
                )
        }

        fn end_auction(ref self: ContractState) -> (u256, u256) {
            // Get a dispatcher for the current round
            let current_round_id = self.current_option_round_id();
            let current_round = self.get_round_dispatcher(current_round_id);

            // End the auction on the option round
            let (clearing_price, total_options_sold) = current_round.end_auction();

            // Get the amount of liquidity currently locked & unlocked
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
                let unsold_liquidity = (locked_liquidity * unsold_options)
                    / total_options_available;

                // Decrement locked liquidity by the unsold liquidity and
                // update the storage variable
                locked_liquidity -= unsold_liquidity;
                self.total_locked_balance.write(locked_liquidity);

                // Increment unlocked liquidity by the unsold liquidity
                unlocked_liquidity += unsold_liquidity;

                // Store how much liquidity goes unsold for future balance calculations
                self.unsold_liquidity.write(current_round_id, unsold_liquidity);
            }

            // Update the total_unlocked_balance storage variable
            self.total_unlocked_balance.write(unlocked_liquidity);

            // Return the clearing_price & total_options_sold
            (clearing_price, total_options_sold)
        }

        fn settle_option_round(ref self: ContractState) -> u256 {
            // Get a dispatcher for the current option round
            let current_round_id = self.current_option_round_id();
            let current_round_dispatcher = self.get_round_dispatcher(current_round_id);

            // Fetch the price to settle the option round
            let settlement_price = self.fetch_settlement_price();

            // Settle the option round
            let total_payout = current_round_dispatcher
                .settle_option_round(SettleOptionRoundParams { settlement_price });

            // @dev The remaining liquidity for a round is how much was locked minus the total payout
            let mut remaining_liquidity = self.get_total_locked_balance();

            // If there is a payout, transfer it from the vault to the settled option round
            if (total_payout > 0) {
                let eth_dispatcher = self.get_eth_dispatcher();
                eth_dispatcher.transfer(current_round_dispatcher.contract_address, total_payout);
                remaining_liquidity -= total_payout;
            }

            // The remaining liquidity becomes unlocked and the locked liquidity becomes 0
            let total_unlocked_balance_before = self.get_total_unlocked_balance();
            self.total_unlocked_balance.write(total_unlocked_balance_before + remaining_liquidity);
            self.total_locked_balance.write(0);

            // Deploy next option round contract, update current round id & round address mapping
            self.deploy_next_round();

            // Return the total payout
            total_payout
        }

        /// Liquidity provider functions

        // Caller deposits liquidity on behalf of the liquidity provider for the upcoming round
        fn deposit_liquidity(
            ref self: ContractState, amount: u256, liquidity_provider: ContractAddress
        ) -> u256 {
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
            lp_unlocked_balance_after
        }

        // Caller withdraws liquidity from their unlocked balance
        fn withdraw_liquidity(ref self: ContractState, amount: u256) -> u256 {
            // Get the liquidity provider's unlocked balance broken up into its components
            let liquidity_provider = get_caller_address();
            let (remaining_liquidity, collectable_balance, upcoming_round_deposit) = self
                .get_lp_unlocked_balance_internal(liquidity_provider);
            let lp_unlocked_balance = remaining_liquidity
                + collectable_balance
                + upcoming_round_deposit;

            // Assert the amount being withdrawn is <= the liquidity provider's unlocked balance
            assert(amount <= lp_unlocked_balance, Errors::InsufficientBalance);

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
            updated_lp_unlocked_balance
        }

        /// LP token related

        fn convert_position_to_lp_tokens(ref self: ContractState, amount: u256) {}

        fn convert_lp_tokens_to_position(
            ref self: ContractState, source_round: u256, amount: u256
        ) {}

        fn convert_lp_tokens_to_newer_lp_tokens(
            ref self: ContractState, source_round: u256, target_round: u256, amount: u256
        ) -> u256 {
            1
        }
    }


    // Internal Functions
    #[generate_trait]
    impl InternalImpl of VaultInternalTrait {
        // Get a dispatcher for the ETH contract
        fn get_eth_dispatcher(self: @ContractState) -> ERC20ABIDispatcher {
            let eth_address: ContractAddress = self.eth_address();
            ERC20ABIDispatcher { contract_address: eth_address }
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
