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
        vault::interface::IVault,
        option_round::{
            contract::OptionRound, interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait},
        },
        market_aggregator::interface::{
            IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait
        },
        types::{VaultType, OptionRoundState, Errors}, library::utils::{divide_with_precision},
    };

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
    // @current_option_round_id: The id of the current option round
    // @round_addresses: Mapping of round id -> round address
    // @round_transition_period: Time between settling of current round and starting of next round
    // @auction_run_time: running time for the auction
    #[storage]
    struct Storage {
        eth_address: ContractAddress,
        option_round_class_hash: ClassHash,
        positions: LegacyMap<(ContractAddress, u256), u256>,
        withdraw_checkpoints: LegacyMap<ContractAddress, u256>,
        queue_checkpoints: LegacyMap<ContractAddress, u256>,
        total_unlocked_balance: u256,
        total_locked_balance: u256,
        total_stashed_balance: u256,
        premiums_collected: LegacyMap<(ContractAddress, u256), u256>,
        total_stashes: LegacyMap<u256, u256>,
        // (LP, round_id) -> (is_marked_for_stash, starting_amount)
        lp_stashes: LegacyMap<(ContractAddress, u256), (bool, u256)>,
        current_option_round_id: u256,
        vault_manager: ContractAddress,
        vault_type: VaultType,
        market_aggregator: ContractAddress,
        round_addresses: LegacyMap<u256, ContractAddress>,
        round_transition_period: u64,
        auction_run_time: u64,
        option_run_time: u64,
    }

    // *************************************************************************
    //                              Constructor
    // *************************************************************************
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
        self.round_transition_period.write(round_transition_period);
        self.auction_run_time.write(auction_run_time);
        self.option_run_time.write(option_run_time);
        // @dev Deploy the 1st option round
        self.deploy_next_round();
    }

    // *************************************************************************
    //                              EVENTS
    // *************************************************************************
    #[event]
    #[derive(PartialEq, Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Withdrawal: Withdrawal,
        StashedWithdrawal: StashedWithdrawal,
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
    struct StashedWithdrawal {
        #[key]
        account: ContractAddress,
        stashed_amount: u256,
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
    //                            IMPLEMENTATION
    // *************************************************************************
    #[abi(embed_v0)]
    impl VaultImpl of IVault<ContractState> {
        // ***********************************
        //               READS
        // ***********************************

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

        /// Rounds ///

        fn current_option_round_id(self: @ContractState) -> u256 {
            self.current_option_round_id.read()
        }

        fn get_option_round_address(
            self: @ContractState, option_round_id: u256
        ) -> ContractAddress {
            self.round_addresses.read(option_round_id)
        }

        /// Liquidity ///

        // Get the value of a liquidity provider's position that is locked

        // If open, none is locked
        // if auctioning, prev round ending amount + this round deposit is locked
        // if running, prev round ending amount + this round deposit - unsold amount locked
        fn get_lp_locked_balance(
            self: @ContractState, liquidity_provider: ContractAddress
        ) -> u256 {
            // @dev If the current round is Open, no liquidity is locked
            let current_round_id = self.current_option_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            let state = current_round.get_state();
            if state == OptionRoundState::Open {
                return 0;
            }

            // @dev The liquidity provider's position value at the start of the current round
            let lp_position = self
                .position_value_from_checkpoint_to_start_of_round(
                    liquidity_provider, current_round_id
                );
            let (position_value_at_end_of_previous_round, deposit_into_current_round) = lp_position;
            let position_value_at_start_of_current_round = position_value_at_end_of_previous_round
                + deposit_into_current_round;

            // @dev If the current round is Auctioning, the entire position is locked
            if (state == OptionRoundState::Auctioning) {
                return position_value_at_start_of_current_round;
            }

            // @dev If the current round is Running, the unsold liquidity becomes unlocked
            let round_starting_liquidity = current_round.starting_liquidity();
            let round_unsold_liquidity = current_round.unsold_liquidity();
            let lp_unsold_liquidity = divide_with_precision(
                position_value_at_start_of_current_round * round_unsold_liquidity,
                round_starting_liquidity
            );

            return position_value_at_start_of_current_round - lp_unsold_liquidity;
        //            // Get a dispatcher for the current round
        //            let current_round_id = self.current_option_round_id.read();
        //            let current_round = self.get_round_dispatcher(current_round_id);
        //            // @dev If the current round is Open, no liquidity is locked
        //            if (current_round.get_state() == OptionRoundState::Open) {
        //                0
        //            } // @dev If the current round is Auctioning or Running, the liquidity provider's
        //            // locked balance is their remaining balance from the previous round and their deposit
        //            // for the current round
        //            else {
        //                // The liquidity provider's deposit for the current round
        //                let current_round_deposit = self
        //                    .positions
        //                    .read((liquidity_provider, current_round_id));
        //                // The liquidity provider's position value at the end of the previous round
        //                let previous_round_remaining_balance = self
        //                    .calculate_value_of_position_from_checkpoint_to_round(
        //                        liquidity_provider, current_round_id - 1
        //                    );
        //
        //                // if settled, panic
        //                // if auctioning, all liq is locke
        //                // if running, liq - unsold is locked, premiums + unsold is unlocked
        //
        //                // Total unsold liquidity for the current round
        //                let round_unsold_liquidity = current_round.unsold_liquidity();
        //                // Lp portion of the unsold liquidity
        //                let lp_unsold_liquidity = divide_with_precision(
        //                    round_unsold_liquidity
        //                        * (previous_round_remaining_balance + current_round_deposit),
        //                    current_round.starting_liquidity()
        //                );
        //
        //                previous_round_remaining_balance + current_round_deposit - lp_unsold_liquidity
        //            }
        }

        // Get the value of a liquidity provider's position that is unlocked
        // If open, prev round ending amount + current round deposit unlocked
        // If auctioning, the upcoming round deposit is unlocked
        // If running, the upcoming round deposit, current round premiums + unsold are unlocked
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


        // Get the liquidity an LP has stashed in the vault from withdrawl queues
        // For all states, stashed amount is total from [checkpoint -> prev round]
        fn get_lp_stashed_balance(
            self: @ContractState, liquidity_provider: ContractAddress
        ) -> u256 {
            // @dev Stashed values can only be realized once the round setttles,
            // therefore the current round must be > 1 for any stashes to exist
            let current_round_id = self.current_option_round_id();
            if current_round_id == 1 {
                return 0;
            }

            let mut i = self.queue_checkpoints.read(liquidity_provider) + 1;
            let mut total = 0;

            while i < current_round_id {
                let (is_queued, lp_starting_liq) = self.lp_stashes.read((liquidity_provider, i));
                if (is_queued) {
                    let (round_starting_liq, round_remaining_liq, _) = self.get_round_outcome(i);
                    let lp_remaining_liq = divide_with_precision(
                        round_remaining_liq * lp_starting_liq, round_starting_liq
                    );
                    total += lp_remaining_liq;
                }
                i += 1;
            };

            total
        //
        //            // @dev When a position is queued for withdrawal, the value of the amount stashed at the end of the round
        //            // can only be realized after the round settles
        //            // @dev The current round is always either Open | Auctioning | Running, all previous
        //            // rounds are Settled
        //            let previous_round_id = self.current_option_round_id() - 1;
        //
        //            // @dev The last round the liquidity provider collected from their
        //            // stash during
        //
        //            // Last round the liquidity provider collected their stash during
        //            let checkpoint = self.queue_checkpoints.read(liquidity_provider);
        //            let mut i = if checkpoint.is_zero() {
        //                1
        //            } else {
        //                checkpoint
        //            };
        //
        //            // The total amount of liquidity the liquidity provider has stashed
        //            let mut total = 0;
        //            loop {
        //                if i > previous_round_id {
        //                    break (total);
        //                } else {
        //                    // @dev Did the liquidity provider queue this round
        //                    // @dev The value of their position at the start of this round
        //                    let (is_queued, lp_starting_liq) = self
        //                        .lp_stashes
        //                        .read((liquidity_provider, i));
        //                    // @dev Only include stashes for queued rounds
        //                    if (is_queued) {
        //                        // @dev This round's details
        //                        let (round_starting_liq, round_remaining_liq, _round_earned_liq) = self
        //                            .get_round_outcome(i);
        //
        //                        // @dev `(lp_starting_amount / round_starting_amount) * round_remaining_liq`
        //                        let lp_remaining_liq = divide_with_precision(
        //                            round_remaining_liq * lp_starting_liq, round_starting_liq
        //                        );
        //
        //                        total += lp_remaining_liq;
        //                    }
        //                    i += 1;
        //                }
        //            }
        }

        fn get_lp_total_balance(self: @ContractState, liquidity_provider: ContractAddress) -> u256 {
            self.get_lp_locked_balance(liquidity_provider)
                + self.get_lp_unlocked_balance(liquidity_provider)
                + self.get_lp_stashed_balance(liquidity_provider)
        }

        fn get_total_locked_balance(self: @ContractState) -> u256 {
            self.total_locked_balance.read()
        }

        fn get_total_stashed_balance(self: @ContractState) -> u256 {
            self.total_stashed_balance.read()
        }

        fn get_total_unlocked_balance(self: @ContractState) -> u256 {
            self.total_unlocked_balance.read()
        }

        fn get_total_balance(self: @ContractState,) -> u256 {
            self.get_total_locked_balance()
                + self.get_total_unlocked_balance()
                + self.get_total_stashed_balance()
        }

        /// Premiums ///

        fn get_premiums_collected(
            self: @ContractState, liquidity_provider: ContractAddress, round_id: u256
        ) -> u256 {
            self.premiums_collected.read((liquidity_provider, round_id))
        }

        // ***********************************
        //               WRITES
        // ***********************************

        /// State Transition ///

        // FOSSIL
        // Update the current option round's parameters if there are newer values
        fn update_round_params(ref self: ContractState) {
            let current_round_id = self.current_option_round_id();
            let current_round = self.get_round_dispatcher(current_round_id);
            let from = current_round.get_auction_start_date();
            let to = current_round.get_option_settlement_date();

            let reserve_price = self.fetch_reserve_price_for_time_period(from, to);
            let cap_level = self.fetch_cap_level_for_time_period(from, to);
            let strike_price = self.fetch_strike_price_for_time_period(from, to);

            current_round.update_round_params(reserve_price, cap_level, strike_price);
        }

        // Start the auction on the current option round
        // @return The total options available in the auction
        fn start_auction(ref self: ContractState) -> u256 {
            // @dev Start the current round's auction
            let current_round_id = self.current_option_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            let unlocked_liquidity = self.get_total_unlocked_balance();
            let options_available = current_round.start_auction(unlocked_liquidity);

            // @dev All unlocked liquidity becomes locked
            self.total_unlocked_balance.write(0);
            self.total_locked_balance.write(unlocked_liquidity);

            options_available
        }

        // @return The clearing price of the auction and number of options that sold
        fn end_auction(ref self: ContractState) -> (u256, u256) {
            // @dev End the current round's auction
            let current_round = self.get_round_dispatcher(self.current_option_round_id());
            let (clearing_price, options_sold) = current_round.end_auction();
            let total_premiums = clearing_price * options_sold;

            // @dev Premiums and unsold liquidity become unlocked
            let mut unlocked_liquidity = self.get_total_unlocked_balance();
            unlocked_liquidity += total_premiums;

            let unsold_liquidity = current_round.unsold_liquidity();
            if unsold_liquidity.is_non_zero() {
                unlocked_liquidity += unsold_liquidity;
                self.total_locked_balance.write(self.get_total_locked_balance() - unsold_liquidity);
            }

            self.total_unlocked_balance.write(unlocked_liquidity);

            (clearing_price, options_sold)
        }

        fn settle_option_round(ref self: ContractState) -> (u256, u256) {
            // @dev Settle the round
            let current_round_id = self.current_option_round_id();
            let current_round = self.get_round_dispatcher(current_round_id);
            // FOSSIL
            let from = current_round.get_auction_start_date();
            let to = current_round.get_option_settlement_date();
            let settlement_price = self.fetch_TWAP_for_time_period(from, to);

            let (total_payout, settlement_price) = current_round
                .settle_option_round(settlement_price);

            // @dev The remaining liquidity becomes unlocked except for the stashed amount
            self.total_locked_balance.write(0);

            // @dev Remaining liquidity
            let starting_liq = current_round.starting_liquidity();
            let unsold_liq = current_round.unsold_liquidity();
            let remaining_liq = starting_liq - unsold_liq - total_payout;

            // @dev Stashed liquidity
            let starting_liq_queued = self.total_stashes.read(current_round_id);
            let remaining_liq_stashed = divide_with_precision(
                remaining_liq * starting_liq_queued, starting_liq
            );
            let remaining_liq_not_stashed = remaining_liq - remaining_liq_stashed;

            let total_stashed = self.total_stashed_balance.read();
            let total_unlocked = self.total_unlocked_balance.read();
            self.total_stashed_balance.write(total_stashed + remaining_liq_stashed);
            self.total_unlocked_balance.write(total_unlocked + remaining_liq_not_stashed);

            // @dev Transfer payout from the vault to the settled option round,
            if (total_payout > 0) {
                let eth_dispatcher = self.get_eth_dispatcher();
                eth_dispatcher.transfer(current_round.contract_address, total_payout);
            }

            // @dev Deploy next option round contract & update the current round id
            self.deploy_next_round();

            (total_payout, settlement_price)
        }

        /// Liquidity Provider ///

        // @note gas saver is to not return unlocked balance after
        // - would not need to calculate the currentl unlocked position value

        // Increases unlocked balance
        fn deposit_liquidity(
            ref self: ContractState, amount: u256, liquidity_provider: ContractAddress
        ) -> u256 {
            // @dev The liquidity provider's unlocked balance before and after the deposit
            let lp_unlocked_balance_before = self.get_lp_unlocked_balance(liquidity_provider);
            let lp_unlocked_balance_after = lp_unlocked_balance_before + amount;

            // @dev Deposits are unlocked at the time of deposit for the upcoming round
            // id. If the current round is Open, the upcoming round is the current round.
            // If the current round is Auctioning | Running, the upcoming round is the next round
            let current_round = self.get_round_dispatcher(self.current_option_round_id());
            let upcoming_round_id = self.get_upcoming_round_id(@current_round);
            let upcoming_round_amount = self
                .positions
                .read((liquidity_provider, upcoming_round_id));
            self
                .positions
                .write((liquidity_provider, upcoming_round_id), upcoming_round_amount + amount);

            let total_unlocked = self.get_total_unlocked_balance();
            self.total_unlocked_balance.write(total_unlocked + amount);

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

        // Decreases unlocked balance
        fn withdraw_liquidity(ref self: ContractState, amount: u256) -> u256 {
            // Get the liquidity provider's unlocked balance broken up into its components
            let liquidity_provider = get_caller_address();
            let (lp_prev_round_remaining_liquidity, collectable_balance, upcoming_round_deposit) =
                self
                .get_lp_unlocked_balance_internal(liquidity_provider);
            let lp_unlocked_balance = lp_prev_round_remaining_liquidity
                + collectable_balance
                + upcoming_round_deposit;

            // Assert the amount being withdrawn is <= the liquidity provider's unlocked balance
            assert(amount <= lp_unlocked_balance, Errors::InsufficientBalance);

            // @dev Take from the liquidity provider's upcoming round deposit first
            let current_round_id = self.current_option_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            let upcoming_round_id = self.get_upcoming_round_id(@current_round);
            let upcoming_round_new_deposit = if amount > upcoming_round_deposit {
                0
            } else {
                upcoming_round_deposit - amount
            };
            self
                .positions
                .write((liquidity_provider, upcoming_round_id), upcoming_round_new_deposit);

            // @dev If there is any remaining amount to withdraw, continue
            if amount > upcoming_round_deposit {
                let amount_difference = amount - upcoming_round_deposit;
                let state = current_round.get_state();
                // @dev If the current round is Running, take from the liquidity provider's premiums and unsold liquidity
                if state == OptionRoundState::Running {
                    let lp_collected = self
                        .premiums_collected
                        .read((liquidity_provider, current_round_id));
                    self
                        .premiums_collected
                        .write(
                            (liquidity_provider, current_round_id), lp_collected + amount_difference
                        );
                } // @dev If the current round is Open, take from the remaining liquidity of the previous round
                else if state == OptionRoundState::Open {
                    // @dev Actuate the position's value as a new deposit into the current round
                    let updated_remaining_liquidity = lp_prev_round_remaining_liquidity
                        - amount_difference;
                    self
                        .positions
                        .write((liquidity_provider, current_round_id), updated_remaining_liquidity);
                    self.withdraw_checkpoints.write(liquidity_provider, current_round_id - 1);
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

        // Stasht the value of the position at the start of the current roun
        // Ignore unsold, it will be handled later, this will be
        // prev round remaining balance + current round deposit
        // Should be able to do x + y for any round/id state, modifty the 'calculate_value_of_position_from_checkpoint_to_round'
        // function to handle when r0 is passed/traverssed
        fn queue_withdrawal(ref self: ContractState) {
            // @dev If the current round is Open, there is no locked liqudity to queue
            let current_round_id = self.current_option_round_id();
            let current_round = self.get_round_dispatcher(current_round_id);
            let state = current_round.get_state();
            if state == OptionRoundState::Open {
                return;
            }

            // @dev Has the liquidity provider already queued a withdrawal for this round
            let liquidity_provider = get_caller_address();
            let (is_queued, _) = self.lp_stashes.read((liquidity_provider, current_round_id));
            if is_queued {
                return;
            }

            // @dev The value of the liquidity provider's position at the start of the current round
            let position_value = self
                .position_value_from_checkpoint_to_start_of_round(
                    liquidity_provider, current_round_id
                );
            let (value_at_end_of_previous_round, deposit_into_current_round) = position_value;
            let position_value = value_at_end_of_previous_round + deposit_into_current_round;

            // @dev Update stash details
            let total_stashes = self.total_stashes.read(current_round_id);
            self.lp_stashes.write((liquidity_provider, current_round_id), (true, position_value));
            self.total_stashes.write(current_round_id, total_stashes + position_value);
        }


        // @note add event
        // Liquidity provider withdraws their stashed (queued) withdrawals
        // Sums stashes from checkpoint -> prev round and sends them to caller
        // resets checkpoint to current round so that next time the count starts from the current round
        // @note update total stashed
        fn withdraw_stashed_liquidity(
            ref self: ContractState, liquidity_provider: ContractAddress
        ) -> u256 {
            // @dev How much does the liquidity provider have stashed
            let stashed_balance = self.get_lp_stashed_balance(liquidity_provider);

            // @dev Update the vault's total stashed
            let total_stashed = self.get_total_stashed_balance();
            self.total_stashed_balance.write(total_stashed - stashed_balance);

            // @dev Update the liquidity provider's queue checkpoint
            self.queue_checkpoints.write(liquidity_provider, self.current_option_round_id() - 1);

            // Transfer the stashed balance to the liquidity provider
            let eth = self.get_eth_dispatcher();
            eth.transfer(liquidity_provider, stashed_balance);

            // Emit stashed withdrawal event
            self
                .emit(
                    Event::StashedWithdrawal(
                        StashedWithdrawal {
                            account: liquidity_provider, stashed_amount: stashed_balance
                        }
                    )
                );

            stashed_balance
        }


        /// OTHER (FOR NOW) ///

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

    // *************************************************************************
    //                          INTERNAL FUNCTIONS
    // *************************************************************************
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
            let next_round_id: u256 = self.current_option_round_id() + 1;

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
            // Reserve price, cap level, & strike price adjust these to take to and from
            let reserve_price = self
                .fetch_reserve_price_for_time_period(auction_start_date, option_settlement_date);
            let cap_level = self
                .fetch_cap_level_for_time_period(auction_start_date, option_settlement_date);
            let strike_price = self
                .fetch_strike_price_for_time_period(auction_start_date, option_settlement_date);
            calldata.append_serde(reserve_price);
            calldata.append_serde(cap_level);
            calldata.append_serde(strike_price);

            // Deploy the next option round contract
            let (next_round_address, _) = deploy_syscall(
                self.option_round_class_hash.read(), 'some salt', calldata.span(), false
            )
                .expect(Errors::OptionRoundDeploymentFailed);

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
        // - If open, returns {remaining_liquidity_from_previous_round, 0, upcoming_round_deposit}
        // - If auctioning, returns {0, 0, upcoming_round_deposit}.
        // - If running, returns {0, collectable_balance, upcoming_round_deposit}
        // error in future, withdraw checks that amount <= unlocked balance but this will include what is stashable ?
        // need to handle the unsold

        ////// modifying this
        fn get_lp_unlocked_balance_internal(
            self: @ContractState, liquidity_provider: ContractAddress
        ) -> (u256, u256, u256) {
            // @dev The liquidity provider's position value at the start of the current round
            let current_round_id = self.current_option_round_id.read();
            let lp_position = self
                .position_value_from_checkpoint_to_start_of_round(
                    liquidity_provider, current_round_id
                );
            let (position_value_at_end_of_previous_round, deposit_into_current_round) = lp_position;
            //let position_value_at_start_of_current_round = position_value_at_end_of_previous_round
            //    + deposit_into_current_round;

            // @dev If the current round is Open, the liquidity provider's unlocked balance is
            // their remaining balance from the previous round and their deposit for the current round
            let current_round = self.get_round_dispatcher(current_round_id);
            let state = current_round.get_state();
            if state == OptionRoundState::Open {
                return (position_value_at_end_of_previous_round, 0, deposit_into_current_round);
            }

            // @dev If the current round is Auctioning, the liquidity provider's unlocked balance is
            // just their deposit for the next next round
            let deposit_into_next_round = self
                .positions
                .read((liquidity_provider, current_round_id + 1));
            if state == OptionRoundState::Auctioning {
                return (0, 0, deposit_into_next_round);
            }

            // @dev If the current round is Running, the liquidity provider's unlocked balance is
            // their next round depsit and their share of the current round's collectable balance
            let round_starting_liq = current_round.starting_liquidity();
            let lp_starting_liq = position_value_at_end_of_previous_round
                + deposit_into_current_round;
            let round_collectable_liq = current_round.total_premiums()
                + current_round.unsold_liquidity();
            // @dev The collectable balance is the premiums and the unsold liquidity not already collected
            let mut lp_collectable_liq = divide_with_precision(
                round_collectable_liq * lp_starting_liq, round_starting_liq
            );
            let lp_collected_liq = self
                .get_premiums_collected(liquidity_provider, current_round_id);

            lp_collectable_liq -= lp_collected_liq;

            (0, lp_collectable_liq, deposit_into_next_round)
        //           // Get the liquidity provider's deposit for the upcoming round
        //            let current_round_id = self.current_option_round_id.read();
        //            let current_round = self.get_round_dispatcher(current_round_id);
        //            let upcoming_round_id = self.get_upcoming_round_id(@current_round);
        //            let upcoming_round_deposit = self
        //                .positions
        //                .read((liquidity_provider, upcoming_round_id));
        //
        //            // @dev If the current round is Auctioning, then the liquidity provider's unlocked balance
        //            // is only their deposit for the upcoming round
        //            // @dev This is because their remaining balance from the previous round is locked in the current round,
        //            // and the auction has not ended (no premiums/unsold liquidity yet)
        //            if (current_round.get_state() == OptionRoundState::Auctioning) {
        //                (0, 0, upcoming_round_deposit)
        //            } else {
        //                // The liquidity provider's position value at the end of the previous round (start of the current round)
        //                let lp_previous_round_remaining_balance = self
        //                    .calculate_value_of_position_from_checkpoint_to_round(
        //                        liquidity_provider, current_round_id - 1
        //                    );
        //
        //                // @dev If the current round is Open, then the liquidity provider's unlocked balance is
        //                // their deposit for the upcoming round, and their remaining balance from the previous round
        //                // @dev The auction has not started so there are no premiums/unsold liquidity to collect
        //                if (current_round.get_state() == OptionRoundState::Open) {
        //                    (lp_previous_round_remaining_balance, 0, upcoming_round_deposit)
        //                } // @dev If the current round is Running, then the liquidity provider's unlocked balance is
        //                // their deposit for the upcoming round and their share of the current round's collectable balance
        //                // (premiums and unsold liquidity)
        //                // @dev Their remaining balance from the previous round is locked in the current round
        //                else {
        //                    // If Running
        //
        //                    // @dev The liquidity provider's share of the collectable amount is proportional to the amount of liquidity they
        //                    // had in the previous round + the amount they deposited for the current round
        //                    let mut lp_current_round_starting_liq = self
        //                        .positions
        //                        .read((liquidity_provider, current_round_id));
        //                    lp_current_round_starting_liq += lp_previous_round_remaining_balance;
        //                    let current_round_starting_liq = current_round.starting_liquidity();
        //
        //                    // @dev The collectable amount is the premiums and the unsold liquidity
        //                    let total_collectable = current_round.total_premiums()
        //                        + current_round.unsold_liquidity();
        //
        //                    // @dev `(lp_current_round_starting_liq / current_round_starting_liq) * total_collectable`
        //                    let mut lp_collectable = divide_with_precision(
        //                        total_collectable * lp_current_round_starting_liq,
        //                        current_round_starting_liq
        //                    );
        //
        //                    // @dev Subtract the amount the liquidity provider already collected
        //                    lp_collectable -= self
        //                        .get_premiums_collected(liquidity_provider, current_round_id);
        //
        //                    (0, lp_collectable, upcoming_round_deposit)
        //                }
        //            }
        }

        // @new @note TODO: If round is flagged for stashing, then the roll over amount has the portion of collat.
        // subtracted out.
        // easily do this by saying:
        // lp portion of premiums/unsold = ...
        // lp portion of payout = ...

        // Calculate a positions's value at the start of the round_id
        // @return (value at the end of the previous round, deposit into this round)
        fn position_value_from_checkpoint_to_start_of_round(
            self: @ContractState, liquidity_provider: ContractAddress, round_id: u256
        ) -> (u256, u256) {
            if (round_id == 0) {
                return (0, 0);
            }

            let deposit_into_round = self.positions.read((liquidity_provider, round_id));
            let current_round_id = self.current_option_round_id();

            if (round_id == 1 || round_id > current_round_id) {
                return (0, deposit_into_round);
            }

            // Calculate position value from the round following the last withdrawal -> round_id
            let mut i = self.withdraw_checkpoints.read(liquidity_provider) + 1;

            // From checkpoint to round before round_id
            let mut position_value = 0;
            while i < round_id {
                // @dev How much the liquidity provider deposited into this round
                position_value += self.positions.read((liquidity_provider, i));

                // @dev Get round outcome
                let (round_starting_liq, round_remaining_liq, round_collectable_liq) = self
                    .get_round_outcome(i);

                // @dev How much the liquidity provider could collect from this round not already collected
                let lp_collectable_liq = divide_with_precision(
                    round_collectable_liq * position_value, round_starting_liq
                );
                let lp_collected_liq = self.premiums_collected.read((liquidity_provider, i));
                let mut lp_rollover_liq = lp_collectable_liq - lp_collected_liq;

                // @dev How much the liquidity provider queued to not roll over
                // @dev If the this round was not queued, the remaining liquidity rolls over
                let (is_queued, _) = self.lp_stashes.read((liquidity_provider, i));
                if !is_queued {
                    let lp_remaining_liq = divide_with_precision(
                        round_remaining_liq * position_value, round_starting_liq
                    );
                    lp_rollover_liq += lp_remaining_liq;
                }

                position_value = lp_rollover_liq;

                i += 1;
            };

            return (position_value, deposit_into_round);
        }

        // Calculate the value of the liquidity provider's position from
        // their checkpoint to the end of the the ending round
        // @new, return
        fn calculate_value_of_position_from_checkpoint_to_round(
            self: @ContractState, liquidity_provider: ContractAddress, ending_round_id: u256
        ) -> u256 {
            // @dev If the ending round is 0, it means the protocol is still in the first round (1),
            // and therefore there is no previous round to calculate the value of the position from
            // @dev A round must be Settled in order to calculate the value of the position at the end of it,
            // an
            if (ending_round_id == 0) {
                0
            } else {
                // Assert the ending round is Settled in order to calculate the value of the position at the end of it
                if (self
                    .get_round_dispatcher(ending_round_id)
                    .get_state() != OptionRoundState::Settled) {
                    // @note replace with err const
                    panic!(
                        "Vault: Ending round must be Settled to calculate the value of the position at the end of it"
                    );
                }
                // Last round the liquidity provider withdrew from
                let checkpoint = self.withdraw_checkpoints.read(liquidity_provider);
                // @dev The first round of the protocol is 1, therefore if the checkpoint is 0
                // we need to start at round 1
                let mut i = if checkpoint.is_zero() {
                    1
                } else {
                    checkpoint
                };

                // Value of the position at the end of each round
                let mut ending_amount = 0;
                loop {
                    if (i > ending_round_id) {
                        // Now ending amount is equal to the value of the position at the end of the ending round
                        break (ending_amount);
                    } else {
                        // @dev This round's details
                        let (round_starting_liq, round_remaining_liq, round_earned_liq) = self
                            .get_round_outcome(i);
                        // @dev How much liquidity the liquidity provider had at the start of this round
                        let lp_starting_liq = self.positions.read((liquidity_provider, i))
                            + ending_amount;

                        // @dev The amount of premiums/unsold liquidity that was collected during this round
                        let lp_collected_liq = self
                            .premiums_collected
                            .read((liquidity_provider, i));

                        // @dev The liquidity provider's portion of the premiums/unsold liquidity that was not already collected
                        // @dev `((lp_starting_liq / round_starting_liq) * round_earned_liq) - lp_collected_liq`
                        let lp_earned_liq = divide_with_precision(
                            round_earned_liq * lp_starting_liq, round_starting_liq
                        )
                            - lp_collected_liq;

                        // @dev If this round is queued, the remaining liquidity is stashed, only the earned liquidity
                        // rolls over
                        let (is_queued, _) = self.lp_stashes.read((liquidity_provider, i));
                        if is_queued {
                            ending_amount = lp_earned_liq;
                        } else {
                            // @dev If this round is not queued, the remaining liquidity & the earned liquidity rolls over
                            // @dev `(lp_starting_liq / round_starting_liq) * round_remaining_liq`
                            let lp_remaining_liq = divide_with_precision(
                                round_remaining_liq * lp_starting_liq, round_starting_liq
                            );

                            ending_amount = lp_remaining_liq + lp_earned_liq;
                        }

                        i += 1;
                    }
                }
            }
        }


        // Returns the starting, remaining, and earned liquidity for a round
        fn get_round_outcome(self: @ContractState, round_id: u256) -> (u256, u256, u256) {
            let round = self.get_round_dispatcher(round_id);
            let state = round.get_state();
            assert!(
                state == OptionRoundState::Settled, "Round must be settled to get round outcome"
            );

            // @dev This round's details
            let round_starting_liq = round.starting_liquidity();
            let round_unsold_liq = round.unsold_liquidity();
            let round_premiums = round.total_premiums();
            let round_payout = round.total_payout();

            // @dev The remaining liquidity at the end of this round
            let remaining_liq = round_starting_liq - round_payout - round_unsold_liq;
            // @dev The amount of premiums/unsold liquidity the liquidity provider gained this round
            let round_earned_liq = round_premiums + round_unsold_liq;

            (round_starting_liq, remaining_liq, round_earned_liq)
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

        fn get_market_aggregator_dispatcher(self: @ContractState) -> IMarketAggregatorDispatcher {
            IMarketAggregatorDispatcher { contract_address: self.get_market_aggregator() }
        }

        fn fetch_reserve_price_for_time_period(self: @ContractState, from: u64, to: u64) -> u256 {
            let mk_agg = self.get_market_aggregator_dispatcher();
            let res = mk_agg.get_reserve_price_for_time_period(from, to);
            match res {
                Option::Some(reserve_price) => { reserve_price },
                //Option::None => panic!("No reserve price found")
                Option::None => { 0 }
            }
        }

        fn fetch_cap_level_for_time_period(self: @ContractState, from: u64, to: u64) -> u128 {
            let mk_agg = self.get_market_aggregator_dispatcher();
            let res = mk_agg.get_cap_level_for_time_period(from, to);
            match res {
                Option::Some(cap_level) => cap_level,
                //Option::None => panic!("No cap level found")
                Option::None => 0
            }
        }

        fn fetch_strike_price_for_time_period(self: @ContractState, from: u64, to: u64) -> u256 {
            let mk_agg = self.get_market_aggregator_dispatcher();
            let res = mk_agg.get_strike_price_for_time_period(from, to);
            match res {
                Option::Some(strike_price) => strike_price,
                //Option::None => panic!("No strike price found")
                Option::None => 0
            }
        }

        fn fetch_TWAP_for_time_period(self: @ContractState, from: u64, to: u64) -> u256 {
            let mk_agg = self.get_market_aggregator_dispatcher();
            let res = mk_agg.get_TWAP_for_time_period(from, to);
            match res {
                Option::Some(TWAP) => TWAP,
                //Option::None => panic!("No TWAP found")
                Option::None => 0
            }
        }
    }
}
