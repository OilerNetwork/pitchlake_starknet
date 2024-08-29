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
        types::{VaultType, OptionRoundState, Errors, Consts::BPS},
    };
    use pitch_lake_starknet::library::utils::{calculate_strike_price};

    const TWAP_DURATION: u64 = 60 * 60 * 24 * 14; // 2 weeks

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
        ///
        vault_type: VaultType,
        vault_manager: ContractAddress,
        market_aggregator: ContractAddress,
        eth_address: ContractAddress,
        option_round_class_hash: ClassHash,
        ///
        round_transition_period: u64,
        auction_run_time: u64,
        option_run_time: u64,
        ///
        current_round_id: u256,
        round_addresses: LegacyMap<u256, ContractAddress>,
        ///
        positions: LegacyMap<(ContractAddress, u256), u256>,
        ///
        total_locked_balance: u256,
        total_unlocked_balance: u256,
        total_stashed_balance: u256,
        ///
        withdraw_checkpoints: LegacyMap<ContractAddress, u256>,
        queue_checkpoints: LegacyMap<ContractAddress, u256>,
        ///
        premiums_moved: LegacyMap<(ContractAddress, u256), bool>,
        ///
        round_queued_liquidity: LegacyMap<u256, u256>,
        user_queued_liquidity: LegacyMap<(ContractAddress, u256), (u16, u256)>,
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
        self.deploy_first_round();
    }

    // *************************************************************************
    //                              EVENTS
    // *************************************************************************
    #[event]
    #[derive(PartialEq, Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Withdrawal: Withdrawal,
        WithdrawalQueued: WithdrawalQueued,
        QueuedLiquidityCollected: QueuedLiquidityCollected,
        OptionRoundDeployed: OptionRoundDeployed,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct Deposit {
        #[key]
        account: ContractAddress,
        amount: u256,
        account_unlocked_balance_now: u256,
        vault_unlocked_balance_now: u256,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct Withdrawal {
        #[key]
        account: ContractAddress,
        amount: u256,
        account_unlocked_balance_now: u256,
        vault_unlocked_balance_now: u256,
    }

    // @dev Emitted when a liquidity provider queues a withdrawal
    #[derive(Drop, starknet::Event, PartialEq)]
    struct WithdrawalQueued {
        #[key]
        account: ContractAddress,
        bps: u16,
        account_queued_amount_now: u256,
        vault_queued_amount_now: u256,
    }

    // @dev Emitted when a liquidity provider claims stashed liquidity
    #[derive(Drop, starknet::Event, PartialEq)]
    struct QueuedLiquidityCollected {
        #[key]
        account: ContractAddress,
        amount: u256,
        vault_stashed_balance_now: u256,
    }


    #[derive(Drop, starknet::Event, PartialEq)]
    struct OptionRoundDeployed {
        round_id: u256,
        address: ContractAddress,
        reserve_price: u256,
        strike_price: u256,
        cap_level: u128,
        auction_start_date: u64,
        auction_end_date: u64,
        option_settlement_date: u64,
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

        fn current_round_id(self: @ContractState) -> u256 {
            self.current_round_id.read()
        }

        fn get_round_address(self: @ContractState, option_round_id: u256) -> ContractAddress {
            self.round_addresses.read(option_round_id)
        }

        /// Liquidity ///

        fn get_total_locked_balance(self: @ContractState) -> u256 {
            self.total_locked_balance.read()
        }

        fn get_total_unlocked_balance(self: @ContractState) -> u256 {
            self.total_unlocked_balance.read()
        }

        fn get_total_queued_balance(self: @ContractState) -> u256 {
            self.round_queued_liquidity.read(self.current_round_id.read())
        }

        fn get_total_stashed_balance(self: @ContractState) -> u256 {
            self.total_stashed_balance.read()
        }

        fn get_total_balance(self: @ContractState,) -> u256 {
            self.get_total_locked_balance()
                + self.get_total_unlocked_balance()
                + self.get_total_stashed_balance()
        }

        // @dev Get the amount of liquidity an account locked at the start of the current round
        fn get_lp_starting_balance(self: @ContractState, account: ContractAddress) -> u256 {
            self.get_realized_deposit_for_current_round(account)
        }


        // @dev Get the amount of liquidity an account has locked at the current time
        fn get_lp_locked_balance(self: @ContractState, account: ContractAddress) -> u256 {
            let current_round_id = self.current_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            let state = current_round.get_state();
            match state {
                // @dev If the current round is Open, all liquidity is unlocked
                OptionRoundState::Open => { 0 },
                // @dev If the current round is Auctioning | Running, the account's locked balance is proportional
                // to the the liquidity they locked at the start of the round
                // @dev
                _ => {
                    let round_starting_liq = current_round.starting_liquidity();
                    let total_locked_liq = self.total_locked_balance.read();
                    let current_round_deposit = self
                        .get_realized_deposit_for_current_round(account);

                    (total_locked_liq * current_round_deposit) / round_starting_liq
                },
            }
        }

        // @dev Get the amount of liquidity an account has unlocked at the current time
        fn get_lp_unlocked_balance(self: @ContractState, account: ContractAddress) -> u256 {
            // @dev Get the account's calculated current round deposit, and upcoming round deposit
            let current_round_id = self.current_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            let current_round_deposit = self.get_realized_deposit_for_current_round(account);
            let upcoming_round_deposit = self.positions.read((account, current_round_id + 1));

            let state = current_round.get_state();
            match state {
                // @dev If Open, the current round's deposit is unlocked and there is no upcoming round
                OptionRoundState::Open => { current_round_deposit },
                // @dev If Auctioning | Running, the current round's deposit is locked, but the upcoming round's
                // deposit and any premiums and unsold liquidity from the current round are unlocked
                _ => {
                    // @dev Get the amount of premium and unsold liquidity the account has unlocked; 0
                    // if Auctioning or the liquiidty was moved as a deposit for the upcoming round
                    let premiums_and_unsold_liq = self
                        .get_liquidity_unlocked_for_account_in_round(
                            account, current_round_deposit, current_round_id
                        );

                    upcoming_round_deposit + premiums_and_unsold_liq
                },
            }
        }

        // @dev Get how much liquidity is queued for stashing in the current round
        // @return The BPS percentage being queued for
        fn get_lp_queued_bps(self: @ContractState, account: ContractAddress) -> u16 {
            let (bps, _) = self.user_queued_liquidity.read((account, self.current_round_id.read()));
            bps
        }


        // @dev Get the stashed liquidity an account can collect
        fn get_lp_stashed_balance(self: @ContractState, account: ContractAddress) -> u256 {
            // @dev Sum the account's stashed amounts for each round after the last collection round
            // @dev Sum to the previous round because the current round will be on-going
            let mut total = 0;
            let mut i = self.queue_checkpoints.read(account) + 1;
            let current_round_id = self.current_round_id();
            while i < current_round_id {
                // @dev Get the account's remaining liquidity that was stashed
                let (_, account_queued_liq) = self.user_queued_liquidity.read((account, i));
                if account_queued_liq.is_non_zero() {
                    let (round_starting_liq, round_remaining_liq, _) = self.get_round_outcome(i);

                    total += (round_remaining_liq * account_queued_liq) / round_starting_liq;
                }
                i += 1;
            };

            total
        }

        fn get_lp_total_balance(self: @ContractState, account: ContractAddress) -> u256 {
            self.get_lp_locked_balance(account)
                + self.get_lp_unlocked_balance(account)
                + self.get_lp_stashed_balance(account)
        }

        // ***********************************
        //               WRITES
        // ***********************************

        /// State Transition ///

        // FOSSIL
        // Update the current option round's parameters if there are newer values
        // @note Return to this during fossil integration
        fn update_round_params(ref self: ContractState) {
            let current_round_id = self.current_round_id();
            let current_round = self.get_round_dispatcher(current_round_id);

            let cap_level = self.fetch_cap_level_for_round(current_round_id);
            let reserve_price = self.fetch_reserve_price_for_round(current_round_id);
            // @note needs to be updated to most recent set range
            let twap_end = current_round.get_auction_start_date();
            let twap_start = twap_end - TWAP_DURATION;
            let current_avg_basefee = self.fetch_TWAP_for_time_period(twap_start, twap_end);
            let volatility = self.fetch_volatility_for_round(current_round_id);
            let strike_price = calculate_strike_price(
                self.vault_type.read(), current_avg_basefee, volatility
            );

            current_round.update_round_params(reserve_price, cap_level, strike_price);
        }

        // @return The total options available in the auction
        fn start_auction(ref self: ContractState) -> u256 {
            // @dev Start the current round's auction
            let current_round_id = self.current_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            let unlocked_liquidity = self.get_total_unlocked_balance();

            // @dev All unlocked liquidity becomes locked
            self.total_unlocked_balance.write(0);
            self.total_locked_balance.write(unlocked_liquidity);

            current_round.start_auction(unlocked_liquidity)
        }

        // @return The clearing price of the auction and number of options that sold
        fn end_auction(ref self: ContractState) -> (u256, u256) {
            // @dev End the current round's auction
            let current_round = self.get_round_dispatcher(self.current_round_id.read());
            let (clearing_price, options_sold) = current_round.end_auction();

            // @dev Premiums earned are unlocked
            let mut unlocked_liquidity = self.get_total_unlocked_balance();
            let earned_premiums = clearing_price * options_sold;
            unlocked_liquidity += earned_premiums;

            // @dev If there is unsold_liquidity, it becomes unlocked
            let unsold_liquidity = current_round.unsold_liquidity();
            if unsold_liquidity.is_non_zero() {
                unlocked_liquidity += unsold_liquidity;
                self.total_locked_balance.write(self.get_total_locked_balance() - unsold_liquidity);
            }

            self.total_unlocked_balance.write(unlocked_liquidity);

            (clearing_price, options_sold)
        }


        // @return The total payout and settlement price for the option round
        fn settle_option_round(ref self: ContractState) -> (u256, u256) {
            // @dev Settle the round
            let current_round_id = self.current_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            // FOSSIL
            let to = current_round.get_option_settlement_date();
            let from = to - TWAP_DURATION;
            let settlement_price = self.fetch_TWAP_for_time_period(from, to);
            let (total_payout, settlement_price) = current_round
                .settle_option_round(settlement_price);

            // @dev The remaining liquidity becomes unlocked except for the stashed amount
            let starting_liq = current_round.starting_liquidity();
            let unsold_liq = current_round.unsold_liquidity();
            let remaining_liq = starting_liq - unsold_liq - total_payout;

            // @dev Stashed liquidity
            let starting_liq_queued = self.round_queued_liquidity.read(current_round_id);
            let remaining_liq_stashed = (remaining_liq * starting_liq_queued) / starting_liq;
            let remaining_liq_not_stashed = remaining_liq - remaining_liq_stashed;

            // @dev All of the remaining locked liquidity becomes unlocked
            self.total_locked_balance.write(0);
            self
                .total_stashed_balance
                .write(self.get_total_stashed_balance() + remaining_liq_stashed);
            self
                .total_unlocked_balance
                .write(self.get_total_unlocked_balance() + remaining_liq_not_stashed);

            // @dev Transfer payout from the vault to the just settled round,
            if (total_payout > 0) {
                self.get_eth_dispatcher().transfer(current_round.contract_address, total_payout);
            }

            // @dev Deploy next option round contract & update the current round id
            self.deploy_next_round(settlement_price);

            (total_payout, settlement_price)
        }

        /// Liquidity Provider ///

        // @dev Caller adds liquidity to an account's upcoming round deposit
        fn deposit_liquidity(
            ref self: ContractState, amount: u256, account: ContractAddress
        ) -> u256 {
            // @dev Update the account's current and upcoming round deposit
            self.refresh_position(account);
            let upcoming_round_id = self.get_upcoming_round_id();
            let upcoming_round_deposit = self.positions.read((account, upcoming_round_id));
            let account_unlocked_balance_now = upcoming_round_deposit + amount;
            self.positions.write((account, upcoming_round_id), account_unlocked_balance_now);

            // @dev Transfer the liquidity from the caller to this contract
            let eth = self.get_eth_dispatcher();
            eth.transfer_from(get_caller_address(), get_contract_address(), amount);

            // @dev Update the total unlocked balance of the Vault
            let vault_unlocked_balance_now = self.total_unlocked_balance.read() + amount;
            self.total_unlocked_balance.write(vault_unlocked_balance_now);

            // @dev Emit deposit event
            self
                .emit(
                    Event::Deposit(
                        Deposit {
                            account,
                            amount,
                            account_unlocked_balance_now,
                            vault_unlocked_balance_now
                        }
                    )
                );

            account_unlocked_balance_now
        }

        // @dev Caller takes liquidity from their upcoming round deposit
        fn withdraw_liquidity(ref self: ContractState, amount: u256) -> u256 {
            // @dev Update the account's upcoming round deposit
            let account = get_caller_address();
            self.refresh_position(account);
            let upcoming_round_id = self.get_upcoming_round_id();
            let upcoming_round_deposit = self.positions.read((account, upcoming_round_id));

            // @dev The account can only withdraw <= the upcoming round deposit
            assert(amount <= upcoming_round_deposit, Errors::InsufficientBalance);
            let account_unlocked_balance_now = upcoming_round_deposit - amount;
            self.positions.write((account, upcoming_round_id), account_unlocked_balance_now);

            // @dev Update the total unlocked balance of the Vault
            let vault_unlocked_balance_now = self.get_total_unlocked_balance() - amount;
            self.total_unlocked_balance.write(vault_unlocked_balance_now);

            // @dev Transfer the liquidity from the caller to this contract
            let eth = self.get_eth_dispatcher();
            eth.transfer(account, amount);

            // @dev Emit withdrawal event
            self
                .emit(
                    Event::Withdrawal(
                        Withdrawal {
                            account,
                            amount,
                            account_unlocked_balance_now,
                            vault_unlocked_balance_now
                        }
                    )
                );

            account_unlocked_balance_now
        }

        // Stash the value of the position at the start of the current round
        // Ignore unsold, it will be handled later, this will be
        // prev round remaining balance + current round deposit
        // Should be able to do x + y for any round/id state, modifty the 'calculate_value_of_position_from_checkpoint_to_round'
        // function to handle when r0 is passed/traverssed
        // @amount is the Total amount to stash, allowing a user to set an updated
        // @param BPS: The percentage points <= 10,000 the account queues to stash when the round settles
        fn queue_withdrawal(ref self: ContractState, bps: u16) {
            // @dev If the current round is Open, there is no locked liqudity to queue, exit early
            let current_round_id = self.current_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            let state = current_round.get_state();
            if state == OptionRoundState::Open {
                return;
            }

            // @dev An account can only queue <= 10,000 BPS
            assert(bps.into() <= BPS, Errors::QueueingMoreThanPositionValue);

            // @dev Get the user's starting deposit for the current round
            let account = get_caller_address();
            self.refresh_position(account);
            let current_round_deposit = self.get_realized_deposit_for_current_round(account);

            // @dev Calculate the starting liquidity for the account being queued
            let account_queued_amount_now = (current_round_deposit * bps.into()) / BPS.into();

            // @dev The caller could be increasing or decreasing their already queued amount
            // so we need to update the total queued balance for the round accordingly
            let round_previously_queued_amount = self.round_queued_liquidity.read(current_round_id);
            let (_, account_queued_amount_before) = self
                .user_queued_liquidity
                .read((account, current_round_id));
            let vault_queued_amount_now = round_previously_queued_amount
                - account_queued_amount_before
                + account_queued_amount_now;
            self.round_queued_liquidity.write(current_round_id, vault_queued_amount_now);

            // @dev Update queued amount for the liquidity provider in the current round
            self
                .user_queued_liquidity
                .write((account, current_round_id), (bps, account_queued_amount_now));

            // @dev Emit withdrawal queued event
            self
                .emit(
                    Event::WithdrawalQueued(
                        WithdrawalQueued {
                            account, bps, account_queued_amount_now, vault_queued_amount_now
                        }
                    )
                );
        }


        // @note add event
        // Liquidity provider withdraws their stashed (queued) withdrawals
        // Sums stashes from checkpoint -> prev round and sends them to caller
        // resets checkpoint to current round so that next time the count starts from the current round
        // @note update total stashed
        fn claim_queued_liquidity(ref self: ContractState, account: ContractAddress) -> u256 {
            // @dev How much does the liquidity provider have stashed
            let amount = self.get_lp_stashed_balance(account);

            // @dev Update the vault's total stashed
            let vault_stashed_balance_now = self.total_stashed_balance.read() - amount;
            self.total_stashed_balance.write(vault_stashed_balance_now);

            // @dev Update the liquidity provider's stash checkpoint
            self.queue_checkpoints.write(account, self.current_round_id.read() - 1);

            // @dev Transfer the stashed balance to the liquidity provider
            let eth = self.get_eth_dispatcher();
            eth.transfer(account, amount);

            // @dev Emit stashed withdrawal event
            self
                .emit(
                    Event::QueuedLiquidityCollected(
                        QueuedLiquidityCollected { account, amount, vault_stashed_balance_now }
                    )
                );

            amount
        }


        /// OTHER (FOR NOW) ///
        // @note remove these

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
            let round_address = self.round_addresses.read(round_id);
            IOptionRoundDispatcher { contract_address: round_address }
        }

        fn deploy_first_round(ref self: ContractState) {
            let now = starknet::get_block_timestamp();
            let TWAP_end_date = now;
            let TWAP_start_date = now - TWAP_DURATION;
            let current_avg_basefee = self
                .fetch_TWAP_for_time_period(TWAP_start_date, TWAP_end_date);

            self.deploy_next_round(current_avg_basefee);
        }

        fn calculate_dates(self: @ContractState) -> (u64, u64, u64) {
            let now = starknet::get_block_timestamp();
            let auction_start_date = now + self.round_transition_period.read();
            let auction_end_date = auction_start_date + self.auction_run_time.read();
            let option_settlement_date = auction_end_date + self.option_run_time.read();

            (auction_start_date, auction_end_date, option_settlement_date)
        }

        // Deploy the next option round contract, update the current round id & round address mapping
        // @note will need to add current_vol as well
        fn deploy_next_round(ref self: ContractState, current_avg_basefee: u256) {
            // The constructor params for the next round
            let mut calldata: Array<felt252> = array![];
            // The Vault's address
            let vault_address = get_contract_address();
            // Vault address & round id
            // The round id for the next round
            let round_id: u256 = self.current_round_id.read() + 1;
            // Dates
            let (auction_start_date, auction_end_date, option_settlement_date) = self
                .calculate_dates();
            // Reserve price, cap level, & strike price adjust these to take to and from
            let reserve_price = self.fetch_reserve_price_for_round(round_id);
            let cap_level = self.fetch_cap_level_for_round(round_id);
            // @dev Calculate strike price based on current avg basefee and Vault's type
            let volatility = self.fetch_volatility_for_round(round_id);
            let strike_price = calculate_strike_price(
                self.vault_type.read(), current_avg_basefee, volatility
            );

            calldata.append_serde(vault_address);
            calldata.append_serde(round_id);
            calldata.append_serde(auction_start_date);
            calldata.append_serde(auction_end_date);
            calldata.append_serde(option_settlement_date);
            calldata.append_serde(reserve_price);
            calldata.append_serde(cap_level);
            calldata.append_serde(strike_price);

            // Deploy the next option round contract
            let (address, _) = deploy_syscall(
                self.option_round_class_hash.read(), 'some salt', calldata.span(), false
            )
                .expect(Errors::OptionRoundDeploymentFailed);

            // Update the current round id & round address mapping
            self.current_round_id.write(round_id);
            self.round_addresses.write(round_id, address);

            // Emit option round deployed event
            self
                .emit(
                    Event::OptionRoundDeployed(
                        OptionRoundDeployed {
                            round_id,
                            address,
                            reserve_price,
                            strike_price,
                            cap_level,
                            auction_start_date,
                            auction_end_date,
                            option_settlement_date
                        }
                    )
                );
        }

        // @dev Get the amount of liquidity unlocked for an account after a round's auction
        // @param account: The account in question
        // @param account_staring_liq: The amount of liquidity the account locked at the start of the round
        // @param round_id: The round to lookup
        // @note Returns 0 if the round is Open | Running
        // @note Returns 0 if the unlocked liq was moved as a deposit into the next round
        fn get_liquidity_unlocked_for_account_in_round(
            self: @ContractState,
            account: ContractAddress,
            account_starting_liq: u256,
            round_id: u256
        ) -> u256 {
            let round = self.get_round_dispatcher(round_id);
            let state = round.get_state();
            // @dev If the round is Open | Auctioning, there are no premiums/unsold liquidity yet
            if state == OptionRoundState::Open || state == OptionRoundState::Auctioning {
                0
            } else {
                if self.premiums_moved.read((account, round_id)) {
                    0
                } else {
                    // @dev How much unlockable liquidity is there in the round
                    let round_starting_liq = round.starting_liquidity();
                    let round_unlocked_liq = round.total_premiums() + round.unsold_liquidity();

                    // @dev Liquidity provider's share of the unlocked liquidity
                    (round_unlocked_liq * account_starting_liq) / round_starting_liq
                }
            }
        }

        // @dev Get the amount of liquidity that remained for an account after a round that was not stashed
        // @param account: The account in question
        // @param account_staring_liq: The amount of liquidity the account locked at the start of the round
        // @param round_id: The round to lookup
        // @note Returns 0 if the round is not Settled
        // @return The remaining liquidity not stashed
        fn get_liquidity_that_remained_in_round_unstashed(
            self: @ContractState,
            account: ContractAddress,
            account_starting_liq: u256,
            round_id: u256
        ) -> u256 {
            let round = self.get_round_dispatcher(round_id);
            let state = round.get_state();
            // @dev If the round is not Settled then remaining liquiditiy is not known yet
            if state != OptionRoundState::Settled {
                0
            } else {
                // @dev How much remaining liquidity was there in the round
                let (round_starting_liq, round_remaining_liq, _) = self.get_round_outcome(round_id);

                // @dev How much did the account stash
                let (_, account_amount_queued) = self
                    .user_queued_liquidity
                    .read((account, round_id));
                let account_remaining_liq_stashed = (round_remaining_liq * account_amount_queued)
                    / round_starting_liq;

                // @dev How much did the account not stash
                let account_remaining_liq = (round_remaining_liq * account_starting_liq)
                    / round_starting_liq;
                let account_remaining_liq_not_stashed = account_remaining_liq
                    - account_remaining_liq_stashed;

                account_remaining_liq_not_stashed
            }
        }


        // @dev Returns the value of the user's position at the start of the current round
        fn get_realized_deposit_for_current_round(
            self: @ContractState, account: ContractAddress
        ) -> u256 {
            // @dev Calculate the value of the liquidity provider's position from the round
            // after their withdraw checkpoint to the end of the previous round
            let mut realized_position = 0;
            let mut i = self.withdraw_checkpoints.read(account) + 1;
            let current_round_id = self.current_round_id.read();
            while i < current_round_id {
                // @dev The position's value at start of this round includes deposits into the round
                realized_position += self.positions.read((account, i));

                // @dev How much liquidity became unlocked for the account in this round
                let account_unlocked_liq = self
                    .get_liquidity_unlocked_for_account_in_round(account, realized_position, i);

                // @dev How much liquidity remained for the account in this round
                let account_remaining_liq = self
                    .get_liquidity_that_remained_in_round_unstashed(account, realized_position, i);

                realized_position = account_unlocked_liq + account_remaining_liq;

                i += 1;
            };

            // @dev Add in the liquidity provider's deposit into the current round
            let current_round_deposit = self.positions.read((account, current_round_id));
            realized_position + current_round_deposit
        }

        // Returns the starting, remaining, and earned liquidity for a round
        fn get_round_outcome(self: @ContractState, round_id: u256) -> (u256, u256, u256) {
            let round = self.get_round_dispatcher(round_id);
            assert!(
                round_id < self.current_round_id.read(), "Round must be settled to get outcome"
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

        // @note Fetch values upon deployment, if there are newer (less stale) vaules at the time of auction start,
        // we use the newer values to set the params

        fn get_market_aggregator_dispatcher(self: @ContractState) -> IMarketAggregatorDispatcher {
            IMarketAggregatorDispatcher { contract_address: self.get_market_aggregator() }
        }

        fn fetch_reserve_price_for_round(self: @ContractState, round_id: u256) -> u256 {
            let mk_agg = self.get_market_aggregator_dispatcher();
            let res = mk_agg.get_reserve_price_for_round(get_contract_address(), round_id);
            match res {
                Option::Some(reserve_price) => reserve_price,
                //Option::None => panic!("No reserve price found")
                Option::None => 0
            }
        }

        fn fetch_cap_level_for_round(self: @ContractState, round_id: u256) -> u128 {
            let mk_agg = self.get_market_aggregator_dispatcher();
            let res = mk_agg.get_cap_level_for_round(get_contract_address(), round_id);
            match res {
                Option::Some(cap_level) => cap_level,
                //Option::None => panic!("No cap level found")
                Option::None => 0
            }
        }

        fn fetch_volatility_for_round(self: @ContractState, round_id: u256) -> u128 {
            let mk_agg = self.get_market_aggregator_dispatcher();
            let res = mk_agg.get_volatility_for_round(get_contract_address(), round_id);
            match res {
                Option::Some(volatility) => volatility,
                //Option::None => panic!("No volatility found")
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

        // @dev Combine deposits from the last checkpoint into a single deposit for the current round,
        // also if there are premiums/unsold liq collectable, add them as a deposit for the upcoming round
        fn refresh_position(ref self: ContractState, account: ContractAddress) {
            // @dev Calculate the account's position at start of the current round
            let current_round_id = self.current_round_id.read();
            let current_round_deposit = self.get_realized_deposit_for_current_round(account);

            // @dev Update the account's current round deposit and checkpoint
            self.withdraw_checkpoints.write(account, current_round_id - 1);
            self.positions.write((account, self.current_round_id()), current_round_deposit);

            // @dev Move the account's unlocked liquidity (premiums and unsold liquidty)
            // as a deposit into the next round if not already moved
            let state = self.get_round_dispatcher(current_round_id).get_state();
            if state == OptionRoundState::Running {
                if !self.premiums_moved.read((account, current_round_id)) {
                    let account_unlocked_liq = self
                        .get_liquidity_unlocked_for_account_in_round(
                            account, current_round_deposit, current_round_id
                        );
                    let upcoming_round_deposit = self
                        .positions
                        .read((account, current_round_id + 1));

                    self.premiums_moved.write((account, current_round_id), true);
                    self
                        .positions
                        .write(
                            (account, current_round_id + 1),
                            upcoming_round_deposit + account_unlocked_liq
                        );
                }
            }
        }

        fn get_upcoming_round_id(self: @ContractState) -> u256 {
            let current_round_id = self.current_round_id.read();
            match self.get_round_dispatcher(current_round_id).get_state() {
                OptionRoundState::Open => current_round_id,
                _ => current_round_id + 1
            };
        }
    }
}
