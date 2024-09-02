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
        market_aggregator_address: ContractAddress,
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
        vault_locked_balance: u256,
        vault_unlocked_balance: u256,
        vault_stashed_balance: u256,
        ///
        position_checkpoints: LegacyMap<ContractAddress, u256>,
        stash_checkpoints: LegacyMap<ContractAddress, u256>,
        ///
        is_premium_moved: LegacyMap<(ContractAddress, u256), bool>,
        ///
        round_queued_liquidity: LegacyMap<u256, u256>,
        account_queued_liquidity: LegacyMap<(ContractAddress, u256), u256>,
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
        vault_type: VaultType,
        market_aggregator_address: ContractAddress,
        option_round_class_hash: ClassHash,
    ) {
        self.eth_address.write(eth_address);
        self.vault_type.write(vault_type);
        self.market_aggregator_address.write(market_aggregator_address);
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
        StashWithdrawn: StashWithdrawn,
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

    #[derive(Drop, starknet::Event, PartialEq)]
    struct WithdrawalQueued {
        #[key]
        account: ContractAddress,
        bps: u16,
        account_queued_liquidity_now: u256,
        vault_queued_liquidity_now: u256,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct StashWithdrawn {
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

        fn get_vault_type(self: @ContractState) -> VaultType {
            self.vault_type.read()
        }

        fn get_market_aggregator_address(self: @ContractState) -> ContractAddress {
            self.market_aggregator_address.read()
        }

        fn get_eth_address(self: @ContractState) -> ContractAddress {
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

        fn get_current_round_id(self: @ContractState) -> u256 {
            self.current_round_id.read()
        }

        fn get_round_address(self: @ContractState, option_round_id: u256) -> ContractAddress {
            self.round_addresses.read(option_round_id)
        }

        /// Liquidity

        fn get_vault_total_balance(self: @ContractState) -> u256 {
            self.get_vault_locked_balance()
                + self.get_vault_unlocked_balance()
                + self.get_vault_stashed_balance()
        }

        fn get_vault_locked_balance(self: @ContractState) -> u256 {
            self.vault_locked_balance.read()
        }

        fn get_vault_unlocked_balance(self: @ContractState) -> u256 {
            self.vault_unlocked_balance.read()
        }

        fn get_vault_stashed_balance(self: @ContractState) -> u256 {
            self.vault_stashed_balance.read()
        }

        fn get_vault_queued_bps(self: @ContractState) -> u16 {
            // @dev Get the liquidity locked at the start of the current round
            let total_liq = self
                .get_round_dispatcher(self.current_round_id.read())
                .get_starting_liquidity();
            // @dev Get the amount queued
            let queued_liq = self.round_queued_liquidity.read(self.current_round_id.read());

            // @dev Calculate the queued BPS %, avoiding division by 0
            match total_liq.is_zero() {
                true => 0,
                false => self.divide_into_bps(queued_liq, total_liq)
            }
        }

        fn get_account_total_balance(self: @ContractState, account: ContractAddress) -> u256 {
            self.get_account_locked_balance(account)
                + self.get_account_unlocked_balance(account)
                + self.get_account_stashed_balance(account)
        }

        fn get_account_locked_balance(self: @ContractState, account: ContractAddress) -> u256 {
            // @dev Get the liquidity locked at the start of the current round
            let total_liq = self
                .get_round_dispatcher(self.current_round_id.read())
                .get_starting_liquidity();
            // @dev Get the liquidity the account locked at the start of the current round
            let account_liq = self.get_realized_deposit_for_current_round(account);
            // @dev Get the liquidity currently locked
            let locked_liq = self.vault_locked_balance.read();

            // @dev Calculate how much belongs to the account, avoiding division by 0
            match total_liq.is_zero() {
                true => 0,
                false => (locked_liq * account_liq) / total_liq
            }
        }

        fn get_account_unlocked_balance(self: @ContractState, account: ContractAddress) -> u256 {
            // @dev Get the account's refreshed upcoming round deposit
            let (_, upcoming_round_deposit) = self.get_refreshed_position(account);

            upcoming_round_deposit
        }

        fn get_account_stashed_balance(self: @ContractState, account: ContractAddress) -> u256 {
            // @dev Sum the account's stashed amounts for each round after the last collection round
            // to the previous round
            let current_round_id = self.current_round_id.read();
            let mut i = self.stash_checkpoints.read(account) + 1;
            let mut total = 0;
            while i < current_round_id {
                // @dev Get the liquidity the account queued
                let queued_liq = self.account_queued_liquidity.read((account, i));
                if queued_liq.is_non_zero() {
                    // @dev Get the round's starting and remaining liquidity
                    let (starting_liq, remaining_liq, _) = self.get_round_outcome(i);
                    // @dev Calculate the amount of remaining liquidity that was stashed for the account,
                    // avoiding division by 0
                    if starting_liq.is_non_zero() {
                        let stashed_liq = (remaining_liq * queued_liq) / starting_liq;
                        total += stashed_liq;
                    }
                }

                i += 1;
            };

            total
        }

        fn get_account_queued_bps(self: @ContractState, account: ContractAddress) -> u16 {
            // @dev Get the liquidity locked at the start of the current round
            let current_round_id = self.current_round_id.read();
            let total_liq = self.get_realized_deposit_for_current_round(account);
            // @dev Get the amount the account queued
            let queued_liq = self.account_queued_liquidity.read((account, current_round_id));

            // @dev Calculate the BPS % of the starting liquidity that is queued, avoiding division by 0
            match total_liq.is_zero() {
                true => 0,
                false => self.divide_into_bps(queued_liq, total_liq)
            }
        }


        // ***********************************
        //               WRITES
        // ***********************************

        /// Account functions

        // @dev Caller deposits liquidity for an account in the upcoming round
        fn deposit(ref self: ContractState, amount: u256, account: ContractAddress) -> u256 {
            // @dev Update the account's current and upcoming round deposits
            self.refresh_position(account);
            let upcoming_round_id = self.get_upcoming_round_id();
            let upcoming_round_deposit = self.positions.read((account, upcoming_round_id));
            let account_unlocked_balance_now = upcoming_round_deposit + amount;
            self.positions.write((account, upcoming_round_id), account_unlocked_balance_now);

            // @dev Transfer the deposit amount from the caller to this contract
            let eth = self.get_eth_dispatcher();
            eth.transfer_from(get_caller_address(), get_contract_address(), amount);

            // @dev Update the vault's unlocked balance
            let vault_unlocked_balance_now = self.vault_unlocked_balance.read() + amount;
            self.vault_unlocked_balance.write(vault_unlocked_balance_now);

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

            // @dev Return the account's unlocked balance after the deposit
            account_unlocked_balance_now
        }

        // @dev Caller withdraws liquidity from the upcoming round
        fn withdraw(ref self: ContractState, amount: u256) -> u256 {
            // @dev Update the account's upcoming round deposit
            let account = get_caller_address();
            self.refresh_position(account);
            let upcoming_round_id = self.get_upcoming_round_id();
            let upcoming_round_deposit = self.positions.read((account, upcoming_round_id));

            // @dev Check the caller is not withdrawing more than their upcoming round deposit
            assert(amount <= upcoming_round_deposit, Errors::InsufficientBalance);

            // @dev Update the account's upcoming round deposit
            let account_unlocked_balance_now = upcoming_round_deposit - amount;
            self.positions.write((account, upcoming_round_id), account_unlocked_balance_now);

            // @dev Update the vault's unlocked balance
            let vault_unlocked_balance_now = self.vault_unlocked_balance.read() - amount;
            self.vault_unlocked_balance.write(vault_unlocked_balance_now);

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

            // @dev Return the account's unlocked balance after the withdrawal
            account_unlocked_balance_now
        }

        fn queue_withdrawal(ref self: ContractState, bps: u16) {
            // @dev If the current round is Open, there is no locked liqudity to queue, exit early
            let current_round_id = self.current_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            let state = current_round.get_state();
            if state == OptionRoundState::Open {
                return;
            }

            // @dev Check the caller is not queueing more than the max BPS
            assert(bps.into() <= BPS, Errors::QueueingMoreThanPositionValue);

            // @dev Get the caller's calculated current round deposit
            let account = get_caller_address();
            self.refresh_position(account);
            let current_round_deposit = self.get_realized_deposit_for_current_round(account);

            // @dev Calculate the starting liquidity for the account being queued
            let account_queued_liquidity_now = (current_round_deposit * bps.into()) / BPS.into();

            // @dev Calculate the vault's updated queued liquidity
            let round_previously_queued_liquidity = self
                .round_queued_liquidity
                .read(current_round_id);
            let account_previously_queued_liquidity = self
                .account_queued_liquidity
                .read((account, current_round_id));
            let vault_queued_liquidity_now = round_previously_queued_liquidity
                - account_previously_queued_liquidity
                + account_queued_liquidity_now;

            // @dev Update the vault and account's queued liquidity
            self.round_queued_liquidity.write(current_round_id, vault_queued_liquidity_now);
            self
                .account_queued_liquidity
                .write((account, current_round_id), account_queued_liquidity_now);

            // @dev Emit withdrawal queued event
            self
                .emit(
                    Event::WithdrawalQueued(
                        WithdrawalQueued {
                            account, bps, account_queued_liquidity_now, vault_queued_liquidity_now
                        }
                    )
                );
        }

        fn withdraw_stash(ref self: ContractState, account: ContractAddress) -> u256 {
            // @dev Get how much the account has stashed
            let amount = self.get_account_stashed_balance(account);

            // @dev Update the account's stash checkpoint
            self.stash_checkpoints.write(account, self.current_round_id.read() - 1);

            // @dev Update the vault's total stashed
            let vault_stashed_balance_now = self.vault_stashed_balance.read() - amount;
            self.vault_stashed_balance.write(vault_stashed_balance_now);

            // @dev Transfer the stashed balance to the liquidity provider
            let eth = self.get_eth_dispatcher();
            eth.transfer(account, amount);

            // @dev Emit stashed withdrawal event
            self
                .emit(
                    Event::StashWithdrawn(
                        StashWithdrawn { account, amount, vault_stashed_balance_now }
                    )
                );

            amount
        }

        /// State transitions

        fn start_auction(ref self: ContractState) -> u256 {
            // @dev How much liquidity is currently unlocked
            let unlocked_liquidity_at_start = self.vault_unlocked_balance.read();

            // @dev All unlocked liquidity becomes locked
            self.vault_locked_balance.write(unlocked_liquidity_at_start);
            self.vault_unlocked_balance.write(0);

            // @dev Start the current round's auction, and return the total options available in the auction
            self
                .get_round_dispatcher(self.current_round_id.read())
                .start_auction(unlocked_liquidity_at_start)
        }

        fn end_auction(ref self: ContractState) -> (u256, u256) {
            // @dev End the current round's auction
            let current_round = self.get_round_dispatcher(self.current_round_id.read());
            let (clearing_price, options_sold) = current_round.end_auction();

            // @dev Calculate the premium and add it to the total unlocked liquidity
            let mut unlocked_liquidity = self.vault_unlocked_balance.read();
            let earned_premiums = clearing_price * options_sold;
            unlocked_liquidity += earned_premiums;

            // @dev Get how much of the locked liquidity was not sold
            let unsold_liquidity = current_round.get_unsold_liquidity();
            if unsold_liquidity.is_non_zero() {
                // @dev Move unsold liquidity from locked to unlocked
                unlocked_liquidity += unsold_liquidity;
                self
                    .vault_locked_balance
                    .write(self.vault_locked_balance.read() - unsold_liquidity);
            }

            // @dev Update the vault's unlocked balance
            self.vault_unlocked_balance.write(unlocked_liquidity);

            // Return the clearing price of the auction and number of options that sold
            (clearing_price, options_sold)
        }

        fn settle_round(ref self: ContractState) -> u256 {
            // @dev Settle the current round
            let current_round_id = self.current_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            // FOSSIL //
            let to = current_round.get_option_settlement_date();
            let from = to - TWAP_DURATION;
            let settlement_price = self.fetch_TWAP_for_time_period(from, to);
            let total_payout = current_round.settle_round(settlement_price);

            // @dev Calculate the remaining liquidity after the round settles
            let starting_liq = current_round.get_starting_liquidity();
            let unsold_liq = current_round.get_unsold_liquidity();
            let remaining_liq = starting_liq - unsold_liq - total_payout;

            // @dev Calculate the amount of liquidity that was not stashed by liquidity providers,
            // avoiding division by 0
            let starting_liq_queued = self.round_queued_liquidity.read(current_round_id);
            let remaining_liq_stashed = match starting_liq.is_zero() {
                true => 0,
                false => (remaining_liq * starting_liq_queued) / starting_liq
            };
            let remaining_liq_not_stashed = remaining_liq - remaining_liq_stashed;

            // @dev All of the remaining liquidity becomes unlocked, any stashed liquidity is set
            // aside and no longer participates in the protocol
            self.vault_locked_balance.write(0);
            self
                .vault_stashed_balance
                .write(self.vault_stashed_balance.read() + remaining_liq_stashed);
            self
                .vault_unlocked_balance
                .write(self.vault_unlocked_balance.read() + remaining_liq_not_stashed);

            // @dev Transfer payout from the vault to the just settled round,
            if (total_payout > 0) {
                self.get_eth_dispatcher().transfer(current_round.contract_address, total_payout);
            }

            // @dev Deploy next option round contract & update the current round id
            self.deploy_next_round(settlement_price);

            // Return the total payout for the option round
            total_payout
        }

        // @note will probably remove this
        fn update_round_params(ref self: ContractState) {
            let current_round_id = self.current_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);

            let cap_level = self.fetch_cap_level_for_round(current_round_id);
            let reserve_price = self.fetch_reserve_price_for_round(current_round_id);
            let twap_end = current_round.get_auction_start_date();
            let twap_start = twap_end - TWAP_DURATION;
            let current_avg_basefee = self.fetch_TWAP_for_time_period(twap_start, twap_end);
            let volatility = self.fetch_volatility_for_round(current_round_id);
            let strike_price = calculate_strike_price(
                self.vault_type.read(), current_avg_basefee, volatility
            );

            current_round.update_round_params(reserve_price, cap_level, strike_price);
        }
    }

    // *************************************************************************
    //                          INTERNAL FUNCTIONS
    // *************************************************************************
    #[generate_trait]
    impl InternalImpl of VaultInternalTrait {
        /// Get contract dispatchers

        fn get_eth_dispatcher(self: @ContractState) -> ERC20ABIDispatcher {
            ERC20ABIDispatcher { contract_address: self.eth_address.read() }
        }

        fn get_market_aggregator_dispatcher(self: @ContractState) -> IMarketAggregatorDispatcher {
            IMarketAggregatorDispatcher { contract_address: self.market_aggregator_address.read() }
        }

        fn get_round_dispatcher(self: @ContractState, round_id: u256) -> IOptionRoundDispatcher {
            IOptionRoundDispatcher { contract_address: self.round_addresses.read(round_id) }
        }

        /// Basic helpers

        fn get_upcoming_round_id(self: @ContractState) -> u256 {
            let current_round_id = self.current_round_id.read();
            match self.get_round_dispatcher(current_round_id).get_state() {
                OptionRoundState::Open => current_round_id,
                _ => current_round_id + 1
            }
        }

        fn get_round_outcome(self: @ContractState, round_id: u256) -> (u256, u256, u256) {
            let round = self.get_round_dispatcher(round_id);
            assert!(
                round_id < self.current_round_id.read(), "Round must be settled to get outcome"
            );

            // @dev Get the round's details
            let round_starting_liq = round.get_starting_liquidity();
            let round_unsold_liq = round.get_unsold_liquidity();
            let round_premiums = round.get_total_premium();
            let round_payout = round.get_total_payout();

            // @dev Calculate the round's remaining and earned liquidity
            let remaining_liq = round_starting_liq - round_payout - round_unsold_liq;
            let round_earned_liq = round_premiums + round_unsold_liq;

            // Return the starting, remaining, and earned liquidity for a settled round
            (round_starting_liq, remaining_liq, round_earned_liq)
        }


        // @dev Divide numerator by denominator and turn into a u16 BPS
        fn divide_into_bps(self: @ContractState, numerator: u256, denominator: u256) -> u16 {
            assert!(
                numerator <= denominator,
                "Numerator must be less than or equal to the denominator to fit into BPS"
            );

            ((BPS.into() * numerator) / denominator).try_into().unwrap()
        }

        /// Deploying rounds

        fn calculate_dates(self: @ContractState) -> (u64, u64, u64) {
            let now = starknet::get_block_timestamp();
            let auction_start_date = now + self.round_transition_period.read();
            let auction_end_date = auction_start_date + self.auction_run_time.read();
            let option_settlement_date = auction_end_date + self.option_run_time.read();

            (auction_start_date, auction_end_date, option_settlement_date)
        }

        fn deploy_first_round(ref self: ContractState) {
            let now = starknet::get_block_timestamp();
            let TWAP_end_date = now;
            let TWAP_start_date = now - TWAP_DURATION;
            let current_avg_basefee = self
                .fetch_TWAP_for_time_period(TWAP_start_date, TWAP_end_date);

            self.deploy_next_round(current_avg_basefee);
        }

        fn deploy_next_round(ref self: ContractState, current_avg_basefee: u256) {
            // @dev Create this round's constructor args
            let mut calldata: Array<felt252> = array![];
            // @dev Get this vault's address
            let vault_address: ContractAddress = get_contract_address();
            // @dev Cauclulate this round's id
            let round_id: u256 = self.current_round_id.read() + 1;
            // @dev Calcualte this round's dates
            let (auction_start_date, auction_end_date, option_settlement_date) = self
                .calculate_dates();
            // @dev Fetch this round's reserve price and cap level
            let reserve_price = self.fetch_reserve_price_for_round(round_id);
            let cap_level = self.fetch_cap_level_for_round(round_id);
            // @dev Calculate this round's strike price
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

            // @dev Deploy the round
            let (address, _) = deploy_syscall(
                self.option_round_class_hash.read(), 'some salt', calldata.span(), false
            )
                .expect(Errors::OptionRoundDeploymentFailed);

            // @dev Update the current round id
            self.current_round_id.write(round_id);
            // @dev Set this round address
            self.round_addresses.write(round_id, address);

            // @dev Emit option round deployed event
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

        /// Fossil

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

        /// Position management

        // @dev Calculate the account's starting deposit for the current round
        fn get_realized_deposit_for_current_round(
            self: @ContractState, account: ContractAddress
        ) -> u256 {
            // @dev Calculate the value of the account's deposit from the round after their
            // deposit checkpoint to the start of the current round
            let current_round_id = self.current_round_id.read();
            let mut i = self.position_checkpoints.read(account) + 1;
            let mut realized_deposit = 0;
            while i < current_round_id {
                // @dev Increment the realized deposit by the account's deposit in this round
                realized_deposit += self.positions.read((account, i));

                // @dev Get the liquidity that became unlocked for the account in this round
                let account_unlocked_liq = self
                    .get_liquidity_unlocked_for_account_in_round(account, realized_deposit, i);

                // @dev Get the liquidity that remained for the account in this round
                let account_remaining_liq = self
                    .get_liquidity_that_remained_in_round_unstashed(account, realized_deposit, i);

                realized_deposit = account_unlocked_liq + account_remaining_liq;

                i += 1;
            };

            // @dev Add in the liquidity provider's current round deposit
            realized_deposit + self.positions.read((account, current_round_id))
        }


        // @dev Calculate the account's starting deposit for the current round and their deposit
        // for the upcoming round
        fn get_refreshed_position(self: @ContractState, account: ContractAddress) -> (u256, u256) {
            // @dev Calculate the account's deposit at start of the current round
            let current_round_id = self.current_round_id.read();
            let current_round_deposit = self.get_realized_deposit_for_current_round(account);
            let state = self.get_round_dispatcher(current_round_id).get_state();
            match state {
                // @dev If the current round is Open, it is also the upcoming round
                OptionRoundState::Open => (current_round_deposit, current_round_deposit),
                // @dev Else, there is an upcoming round
                _ => {
                    // @dev Get the account's upcoming round deposit
                    let mut upcoming_round_deposit = self
                        .positions
                        .read((account, current_round_id + 1));
                    // @dev There are only premium/unsold liquidity after the auction ends
                    if state == OptionRoundState::Running {
                        // @dev Adds 0 if the premium/unsold liquidity was already moved as a deposit
                        // into the upcoming round
                        upcoming_round_deposit += self
                            .get_liquidity_unlocked_for_account_in_round(
                                account, current_round_deposit, current_round_id
                            );
                    }

                    (current_round_deposit, upcoming_round_deposit)
                },
            }
        }

        // @dev Combine deposits from the last checkpoint into a single deposit for the current round,
        // and if there are premiums/unsold liquidity collectable, add them as a deposit for the
        // upcoming round
        fn refresh_position(ref self: ContractState, account: ContractAddress) {
            // @dev Get the refreshed current and upcoming round deposits
            let current_round_id = self.current_round_id.read();
            let (current_round_deposit, upcoming_round_deposit) = self
                .get_refreshed_position(account);

            // @dev Update the account's current round deposit and checkpoint
            if current_round_deposit != self.positions.read((account, current_round_id)) {
                self.positions.write((account, current_round_id), current_round_deposit);
            }
            if current_round_id - 1 != self.position_checkpoints.read(account) {
                self.position_checkpoints.write(account, current_round_id - 1);
            }

            // @dev If the current round is Running, there could be premiums/unsold liquidity to
            // to move to the upcoming round
            if self
                .get_round_dispatcher(current_round_id)
                .get_state() == OptionRoundState::Running {
                if !self.is_premium_moved.read((account, current_round_id)) {
                    self.is_premium_moved.write((account, current_round_id), true);
                    if upcoming_round_deposit != self
                        .positions
                        .read((account, current_round_id + 1)) {
                        self
                            .positions
                            .write((account, current_round_id + 1), upcoming_round_deposit);
                    }
                }
            }
        }

        // @dev Get the premium and unsold liquidity unlocked for an account after a round's auction
        // @param account: The account in question
        // @param account_staring_liq: The liquidity the account locked at the start of the round
        // @param round_id: The round to lookup
        // @note Returns 0 if the round is Open | Running
        // @note Returns 0 if the unlocked liq was moved as a deposit into the next round (refreshed)
        fn get_liquidity_unlocked_for_account_in_round(
            self: @ContractState,
            account: ContractAddress,
            account_starting_liq: u256,
            round_id: u256
        ) -> u256 {
            // @dev If the round is Open | Auctioning, there are no premiums/unsold liquidity yet, return 0
            // @dev If the unlocked liquidity was moved as a deposit into the next round, return  0
            let round = self.get_round_dispatcher(round_id);
            let state = round.get_state();
            if state == OptionRoundState::Open
                || state == OptionRoundState::Auctioning
                || self.is_premium_moved.read((account, round_id)) {
                0
            } else {
                // @dev How much unlockable liquidity is there in the round
                let round_starting_liq = round.get_starting_liquidity();
                let round_unlocked_liq = round.get_total_premium() + round.get_unsold_liquidity();

                // @dev Liquidity provider's share of the unlocked liquidity, avoiding division by 0
                match round_starting_liq.is_zero() {
                    true => 0,
                    false => { (round_unlocked_liq * account_starting_liq) / round_starting_liq }
                }
            }
        }

        // @dev Get the liquidity that remained for an account after a round settled that was not stashed
        // @param account: The account in question
        // @param account_staring_liq: The liquidity the account locked at the start of the round
        // @param round_id: The round to lookup
        // @note Returns 0 if the round is not Settled
        fn get_liquidity_that_remained_in_round_unstashed(
            self: @ContractState,
            account: ContractAddress,
            account_starting_liq: u256,
            round_id: u256
        ) -> u256 {
            // @dev Return 0 if the round is not Settled
            if self.get_round_dispatcher(round_id).get_state() != OptionRoundState::Settled {
                0
            } else {
                // @dev Get the round's starting and remaining liquidity
                let (round_starting_liq, round_remaining_liq, _) = self.get_round_outcome(round_id);

                // @dev Calculate the amount of liquidity the account stashed
                let account_liq_queued = self.account_queued_liquidity.read((account, round_id));
                let account_remaining_liq_stashed = (round_remaining_liq * account_liq_queued)
                    / round_starting_liq;

                // @dev Calculate the amount of liquidity the account did not stashed
                let account_remaining_liq = (round_remaining_liq * account_starting_liq)
                    / round_starting_liq;
                let account_remaining_liq_not_stashed = account_remaining_liq
                    - account_remaining_liq_stashed;

                // @dev Return the remaining liquidity not stashed
                account_remaining_liq_not_stashed
            }
        }
    }
}
