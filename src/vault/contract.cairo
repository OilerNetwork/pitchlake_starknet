#[starknet::contract]
mod Vault {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess,};
    use starknet::storage::{Map, StoragePathEntry};
    use starknet::{
        ContractAddress, ClassHash, deploy_syscall, get_caller_address, contract_address_const,
        get_contract_address, get_block_timestamp
    };
    use openzeppelin_token::erc20::{
        ERC20Component, interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait}
    };
    use openzeppelin_utils::serde::SerializedAppend;
    use pitch_lake::vault::interface::{
        ConstructorArgs, IVault, VaultType, L1DataRequest, L1Result, L1Data,
    };
    use pitch_lake::option_round::contract::OptionRound;
    use pitch_lake::option_round::interface::{
        ConstructorArgs as OptionRoundConstructorArgs, OptionRoundState, IOptionRoundDispatcher,
        IOptionRoundDispatcherTrait, PricingData,
    };
    use pitch_lake::types::{Consts::{BPS, JOB_TIMESTAMP_TOLERANCE}};
    use pitch_lake::library::utils::{assert_equal_in_range, generate_request_id,};
    use pitch_lake::library::pricing_utils::{calculate_strike_price, calculate_cap_level};
    use pitch_lake::library::constants::{
        MINUTE, HOUR, DAY, //ROUND_TRANSITION_PERIOD, AUCTION_RUN_TIME, OPTION_RUN_TIME
    };

    // *************************************************************************
    //                              Constants
    // *************************************************************************

    const PITCH_LAKE_V1: felt252 = 'PITCH_LAKE_V1';
    const TIMESTAMP_TOLERANCE: u64 = 1 * HOUR;

    // *************************************************************************
    //                              STORAGE
    // *************************************************************************

    #[storage]
    struct Storage {
        ///
        vault_type: VaultType,
        alpha: u128,
        ///
        l1_data: Map<u256, L1Data>,
        option_round_class_hash: ClassHash,
        fulfillment_whitelist: Map<ContractAddress, bool>,
        eth_address: ContractAddress,
        round_addresses: Map<u256, ContractAddress>,
        ///
        ///
        // @note could use usize ?
        current_round_id: u256,
        ///
        // @note could use CA, (usize, u256) ?
        positions: Map<ContractAddress, Map<u256, u256>>,
        ///
        vault_locked_balance: u256,
        vault_unlocked_balance: u256,
        vault_stashed_balance: u256,
        ///
        // @note could use CA, usize ?
        position_checkpoints: Map<ContractAddress, u256>,
        // @note could use CA, usize ?
        stash_checkpoints: Map<ContractAddress, u256>,
        // @note could use CA, (usize, bool) ?
        is_premium_moved: Map<ContractAddress, Map<u256, bool>>,
        ///
        // @note could use CA, (usize, u256)
        queued_liquidity: Map<ContractAddress, Map<u256, u256>>,
    }

    // *************************************************************************
    //                              Constructor
    // *************************************************************************

    #[constructor]
    fn constructor(ref self: ContractState, args: ConstructorArgs) {
        // @dev Get the constructor arguments
        let ConstructorArgs { request_fulfiller,
        eth_address,
        vault_type,
        option_round_class_hash } =
            args;

        // @dev Set the Vault's parameters
        self.fulfillment_whitelist.entry(request_fulfiller).write(true);
        self.eth_address.write(eth_address);
        self.vault_type.write(vault_type);
        self.option_round_class_hash.write(option_round_class_hash);

        // @dev Deploy the first round
        self.deploy_next_round(Default::default());
    }

    // *************************************************************************
    //                              Errors
    // *************************************************************************

    mod Errors {
        const JobRequestOutOfBounds: felt252 = 'Job request out of bounds';
        const JobRequestUpperBoundsMismatch: felt252 = 'Job request bounds mismatch';
        const JobRequestForIrrelevantTime: felt252 = 'Job request for irrelevant time';
        const L1DataOutOfRange: felt252 = 'L1 data out of range';
        const InsufficientBalance: felt252 = 'Insufficient unlocked balance';
        const QueueingMoreThanPositionValue: felt252 = 'Insufficient balance to queue';
        const WithdrawalQueuedWhileUnlocked: felt252 = 'Can only queue while locked';
        const OptionRoundDeploymentFailed: felt252 = 'Option round deployment failed';
    }

    // *************************************************************************
    //                              EVENTS
    // *************************************************************************

    #[event]
    #[derive(Serde, PartialEq, Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Withdrawal: Withdrawal,
        WithdrawalQueued: WithdrawalQueued,
        StashWithdrawn: StashWithdrawn,
        OptionRoundDeployed: OptionRoundDeployed,
        L1RequestFulfilled: L1RequestFulfilled,
        L1RequestNotFulfilled: L1RequestNotFulfilled,
    }

    // @dev Emitted when a deposit is made for an account
    // @member account: The account the deposit was made for
    // @member amount: The amount deposited
    // @member: account_unlocked_balance_now: The account's unlocked balance after the deposit
    // @member: vault_unlocked_balance_now: The vault's unlocked balance after the deposit
    #[derive(Serde, Drop, starknet::Event, PartialEq)]
    struct Deposit {
        #[key]
        account: ContractAddress,
        amount: u256,
        account_unlocked_balance_now: u256,
        vault_unlocked_balance_now: u256,
    }

    // @dev Emitted when an account makes a withdrawal
    // @member account: The account that made the withdrawal
    // @member amount: The amount withdrawn
    // @member account_unlocked_balance_now: The account's unlocked balance after the withdrawal
    // @member vault_unlocked_balance_now: The vault's unlocked balance after the withdrawal
    #[derive(Serde, Drop, starknet::Event, PartialEq)]
    struct Withdrawal {
        #[key]
        account: ContractAddress,
        amount: u256,
        account_unlocked_balance_now: u256,
        vault_unlocked_balance_now: u256,
    }

    // @dev Emitted when an account queues a withdrawal
    // @member account: The account that queued the withdrawal
    // @member bps: The BPS % of the account's remaining liquidity to stash
    // @member account_queued_liquidity_now: The account's starting liquidity queued after the
    // withdrawal @member vault_queued_liquidity_now: The vault's starting liquidity queued after
    // the withdrawal
    #[derive(Serde, Drop, starknet::Event, PartialEq)]
    struct WithdrawalQueued {
        #[key]
        account: ContractAddress,
        bps: u16,
        account_queued_liquidity_now: u256,
        vault_queued_liquidity_now: u256,
    }

    // @dev Emitted when an account withdraws their stashed liquidity
    // @member account: The account that withdrew the stashed liquidity
    // @member amount: The amount withdrawn
    // @member vault_stashed_balance_now: The vault's stashed balance after the withdrawal
    #[derive(Serde, Drop, starknet::Event, PartialEq)]
    struct StashWithdrawn {
        #[key]
        account: ContractAddress,
        amount: u256,
        vault_stashed_balance_now: u256,
    }

    // @dev Emitted when a new option round is deployed
    // @member round_id: The id of the deployed round
    // @member address: The address of the deployed round
    // @member reserve_price: The reserve price for the deployed round
    // @member strike_price: The strike price for the deployed round
    // @member cap_level: The cap level for the deployed round
    // @member auction_start_date: The auction start date for the deployed round
    // @member auction_end_date: The auction end date for the deployed round
    // @member option_settlement_date: The option settlement date for the deployed round
    #[derive(Serde, Drop, starknet::Event, PartialEq)]
    struct OptionRoundDeployed {
        round_id: u256,
        address: ContractAddress,
        auction_start_date: u64,
        auction_end_date: u64,
        option_settlement_date: u64,
        pricing_data: PricingData,
    }

    #[derive(Serde, Drop, starknet::Event, PartialEq)]
    struct L1RequestFulfilled {
        #[key]
        id: felt252,
        #[key]
        caller: ContractAddress,
    }

    #[derive(Serde, Drop, starknet::Event, PartialEq)]
    struct L1RequestNotFulfilled {
        #[key]
        id: felt252,
        #[key]
        caller: ContractAddress,
        reason: felt252,
    }

    // *************************************************************************
    //                            IMPLEMENTATION
    // *************************************************************************

    #[abi(embed_v0)]
    impl VaultImpl of IVault<ContractState> {
        // ***********************************
        //               READS
        // ***********************************

        ///

        fn get_vault_type(self: @ContractState) -> VaultType {
            self.vault_type.read()
        }

        fn get_eth_address(self: @ContractState) -> ContractAddress {
            self.eth_address.read()
        }

        //        fn get_auction_run_time(self: @ContractState) -> u64 {
        //            AUCTION_RUN_TIME
        //        }
        //
        //        fn get_option_run_time(self: @ContractState) -> u64 {
        //            OPTION_RUN_TIME
        //        }
        //
        //        fn get_round_transition_period(self: @ContractState) -> u64 {
        //            ROUND_TRANSITION_PERIOD
        //        }

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
            // @dev Get the vault's queued for the current round
            let queued_liq = self
                .queued_liquidity
                .entry(get_contract_address())
                .entry(self.current_round_id.read())
                .read();

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
                let queued_liq = self.queued_liquidity.entry(account).entry(i).read();
                if queued_liq.is_non_zero() {
                    // @dev Get the round's starting and remaining liquidity
                    let (starting_liq, remaining_liq, _) = self.get_round_outcome(i);
                    // @dev Calculate the amount of remaining liquidity that was stashed for the
                    // account, avoiding division by 0
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
            let queued_liq = self.queued_liquidity.entry(account).entry(current_round_id).read();

            // @dev Calculate the BPS % of the starting liquidity that is queued, avoiding division
            // by 0
            match total_liq.is_zero() {
                true => 0,
                false => self.divide_into_bps(queued_liq, total_liq)
            }
        }

        /// Fossil

        fn get_request_to_settle_round(self: @ContractState) -> L1DataRequest {
            // @dev Get the current round's settlement date
            let settlement_date = self
                .get_round_dispatcher(self.current_round_id.read())
                .get_option_settlement_date();

            // @dev Return the earliest request that will allow `settle_round()` to pass once
            // finished - A request is valid as long as its timestamp is >= settlement date -
            // tolerance and <= settlement date
            L1DataRequest {
                identifiers: array![PITCH_LAKE_V1].span(),
                timestamp: settlement_date - TIMESTAMP_TOLERANCE,
            }
        }

        fn get_request_to_start_auction(self: @ContractState) -> L1DataRequest {
            // @dev Get the current round's deployment date
            let deployment_date = self
                .get_round_dispatcher(self.current_round_id.read())
                .get_deployment_date();

            // @dev Return the earliest request that will allow `start_auction()` to pass once
            // finished (if refreshing or not set yet)
            // - A request is valid as long as its timestamp is >= deployment date and
            // <= auction start date
            L1DataRequest { identifiers: array![PITCH_LAKE_V1].span(), timestamp: deployment_date, }
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
            let upcoming_round_deposit = self
                .positions
                .entry(account)
                .entry(upcoming_round_id)
                .read();
            let account_unlocked_balance_now = upcoming_round_deposit + amount;
            self
                .positions
                .entry(account)
                .entry(upcoming_round_id)
                .write(account_unlocked_balance_now);

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
            let upcoming_round_deposit = self
                .positions
                .entry(account)
                .entry(upcoming_round_id)
                .read();

            // @dev Check the caller is not withdrawing more than their upcoming round deposit
            assert(amount <= upcoming_round_deposit, Errors::InsufficientBalance);

            // @dev Update the account's upcoming round deposit
            let account_unlocked_balance_now = upcoming_round_deposit - amount;
            self
                .positions
                .entry(account)
                .entry(upcoming_round_id)
                .write(account_unlocked_balance_now);

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

            // @dev Calculate the's starting liquidity for the vault being queued
            let vault_previously_queued_liquidity = self
                .queued_liquidity
                .entry(get_contract_address())
                .entry(current_round_id)
                .read();
            let account_previously_queued_liquidity = self
                .queued_liquidity
                .entry(account)
                .entry(current_round_id)
                .read();
            let vault_queued_liquidity_now = vault_previously_queued_liquidity
                - account_previously_queued_liquidity
                + account_queued_liquidity_now;

            // @dev Update the vault and account's queued liquidity
            let vault = get_contract_address();
            self
                .queued_liquidity
                .entry(vault)
                .entry(current_round_id)
                .write(vault_queued_liquidity_now);
            self
                .queued_liquidity
                .entry(account)
                .entry(current_round_id)
                .write(account_queued_liquidity_now);

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

        fn fulfill_request(
            ref self: ContractState, request: L1DataRequest, result: L1Result
        ) -> bool {
            // @dev Requests can only be fulfilled if the current round is Open || Running
            let current_round = self.get_round_dispatcher(self.current_round_id.read());
            let state = current_round.get_state();
            if (state == OptionRoundState::Auctioning || state == OptionRoundState::Settled) {
                // emit event ?
                return false;
            }

            // @dev If the current round is Open, the result is being used to refresh the current
            // round's pricing data; therefore, its timestamp must be between the round's deployment
            // date and auction start date
            let mut upper_bound = 0;
            let mut lower_bound = 0;
            if state == OptionRoundState::Open {
                upper_bound = current_round.get_auction_start_date();
                lower_bound = current_round.get_deployment_date();
            } // @dev If the current_round is Running, the result is being used to set the pricing
            // data to settle the current round and deploy the next; therefore, its timestamp must
            // be on or before the settlement date with some tolerance
            else {
                upper_bound = current_round.get_option_settlement_date();
                lower_bound = upper_bound - TIMESTAMP_TOLERANCE;
            }

            // @dev Ensure result is in bounds
            let timestamp = request.timestamp;
            if (timestamp < lower_bound || timestamp > upper_bound) {
                // emit event ?
                return false;
            }

            // @dev Since we are skipping the proof verification, Pitch Lake will use a whitelisted
            // address to fulfill requests, eventually update to proof verification instead
            let caller = get_caller_address();
            if self.fulfillment_whitelist.entry(caller).read() == false {
                // emit event ?
                return false;
            }

            // @dev If the current round is Open, set its pricing data directly
            if state == OptionRoundState::Open {
                current_round.set_pricing_data(self.l1_data_to_round_data(result.data));
            } // @dev If the current round is Running, set pricing data to use upon settlement
            else {
                // @dev Set l1 pricing data for upcoming round settlement
                self.l1_data.entry(current_round.get_round_id()).write(result.data);
            }

            // @dev Emit request fulfilled event
            self
                .emit(
                    Event::L1RequestFulfilled(
                        L1RequestFulfilled { id: generate_request_id(request), caller }
                    )
                );

            true
        }

        //        fn fulfill_request_to_settle_round(
        //            ref self: ContractState, request: L1DataRequest, result: L1Result
        //        ) -> bool {
        //            // @dev Get the request's ID and caller fulfilling the request
        //            let id = generate_request_id(request);
        ///            let caller = get_caller_address();
        //
        //            // @dev Pricing data can only be set if the current round is Running
        //            let current_round = self.get_round_dispatcher(self.current_round_id.read());
        //            if current_round.get_state() != OptionRoundState::Running {
        //                // @dev Emit L1 request not fulfilled event
        //                self
        //                    .emit(
        //                        Event::L1RequestNotFulfilled(
        //                            L1RequestNotFulfilled { id, caller, reason: 'REPLACE ME' }
        //                        )
        //                    );
        //                return false;
        //            }
        //
        //            // @dev A requst is valid to settle a round if it is the between some
        //            tolerance and the // settlement date
        //            let timestamp = request.timestamp;
        //            let settlement_date = current_round.get_option_settlement_date();
        //            if (timestamp < settlement_date - TIMESTAMP_TOLERANCE || timestamp >
        //            settlement_date) {
        //                // @dev Emit L1 request not fulfilled event
        //                self
        //                    .emit(
        //                        Event::L1RequestNotFulfilled(
        //                            L1RequestNotFulfilled { id, caller, reason: 'REPLACE ME' }
        //                        )
        //                    );
        //                return false;
        //            }
        //
        //            // @dev Pricing data can only be set if the correct script was ran
        //            (identifiers) and the // inputs (timestamp) & outputs (data) align with the
        //            supplied proof // @note Skipping for now until Fossil is further developed
        //            // verfifer_contract.prove_computation(program_hash: identifiers.at(...),
        //            inputs:
        //            // [timestamp], outputs: [twap, volatility, reserve_price])
        //
        //            // @dev Set l1 pricing data for upcoming round settlement
        //            self.l1_data.entry(current_round.get_round_id()).write(result.data);
        //
        //            // @dev Emit L1 request fulfilled event
        //            self.emit(Event::L1RequestFulfilled(L1RequestFulfilled { id, caller }));
        //
        //            true
        //        }
        //
        //        fn fulfill_request_to_start_auction(
        //            ref self: ContractState, request: L1DataRequest, result: L1Result
        //        ) -> bool {
        //            // @dev Get the request's ID and caller fulfilling the request
        //            let id = generate_request_id(request);
        //            let caller = get_caller_address();
        //
        //            // @dev Pricing data can only be set if the current round is Open
        //            let current_round = self.get_round_dispatcher(self.current_round_id.read());
        //            if current_round.get_state() != OptionRoundState::Open {
        //                return false;
        //            }
        //
        //            // @dev A requst is valid to start an auction if it is the between the
        //            deployment and // auction start date
        //            let timestamp = request.timestamp;
        //            let deployment_date = current_round.get_deployment_date();
        //            let auction_start_date = current_round.get_auction_start_date();
        //            if (timestamp < deployment_date || timestamp > auction_start_date) {
        //                // @dev Emit L1 request not fulfilled event
        //                self
        //                    .emit(
        //                        Event::L1RequestNotFulfilled(
        //                            L1RequestNotFulfilled { id, caller, reason: 'REPLACE ME' }
        //                        )
        //                    );
        //                return false;
        //            }
        //
        //            // @dev Pricing data can only be set if the correct script was ran
        //            (identifiers) and the // inputs (timestamp) & outputs (data) align with the
        //            supplied proof // @note Skipping for now until Fossil is further developed
        //            // verfifer_contract.prove_computation(program_hash: identifiers.at(...),
        //            inputs:
        //            // [timestamp], outputs: [twap, volatility, reserve_price])
        //
        //            // @dev Set pricing data for the Open round
        //            current_round.set_pricing_data(self.l1_data_to_round_data(result.data));
        //
        //            // @dev Emit L1 request fulfilled event
        //            self.emit(Event::L1RequestFulfilled(L1RequestFulfilled { id, caller }));
        //
        //            true
        //        }

        fn start_auction(ref self: ContractState) -> u256 {
            // @dev Update all unlocked liquidity to locked
            let unlocked_liquidity_before_auction = self.vault_unlocked_balance.read();
            self.vault_locked_balance.write(unlocked_liquidity_before_auction);
            self.vault_unlocked_balance.write(0);

            // @dev Start the current round's auction and return the total options available
            self
                .get_round_dispatcher(self.current_round_id.read())
                .start_auction(unlocked_liquidity_before_auction)
        }

        fn end_auction(ref self: ContractState) -> (u256, u256) {
            // @dev End the current round's auction
            let current_round = self.get_round_dispatcher(self.current_round_id.read());
            let (clearing_price, options_sold) = current_round.end_auction();

            // @dev Calculate the total premium and add it to the total unlocked liquidity
            let mut unlocked_liquidity = self.vault_unlocked_balance.read();
            let total_premium = clearing_price * options_sold;
            unlocked_liquidity += total_premium;

            // @dev If there is unsold liquidity it becomes unlocked
            let unsold_liquidity = current_round.get_unsold_liquidity();
            if unsold_liquidity.is_non_zero() {
                unlocked_liquidity += unsold_liquidity;
                self
                    .vault_locked_balance
                    .write(self.vault_locked_balance.read() - unsold_liquidity);
            }

            // @dev Update the vault's unlocked balance
            self.vault_unlocked_balance.write(unlocked_liquidity);

            // @dev Return the clearing price of the auction and the number of options sold
            (clearing_price, options_sold)
        }

        fn settle_round(ref self: ContractState) -> u256 {
            // @dev Get settlement pricing data if set for the current round's settlement
            let current_round_id = self.current_round_id.read();
            let l1_data = self.l1_data.entry(current_round_id).read();

            assert(l1_data != Default::default(), 'Replace w/Data not set');

            // @dev Settle the current round and return the total payout
            let current_round = self.get_round_dispatcher(current_round_id);
            let total_payout = current_round.settle_round(l1_data.twap);

            // @dev Calculate the remaining liquidity after the round settles
            let starting_liq = current_round.get_starting_liquidity();
            let unsold_liq = current_round.get_unsold_liquidity();
            let remaining_liq = starting_liq - unsold_liq - total_payout;

            // @dev Calculate the amount of liquidity that was stashed/not stashed by liquidity
            // providers, avoiding division by 0
            let vault = get_contract_address();
            let starting_liq_queued = self
                .queued_liquidity
                .entry(vault)
                .entry(current_round_id)
                .read();
            let remaining_liq_stashed = match starting_liq.is_zero() {
                true => 0,
                false => (remaining_liq * starting_liq_queued) / starting_liq
            };
            let remaining_liq_not_stashed = remaining_liq - remaining_liq_stashed;

            // @dev All of the remaining liquidity becomes unlocked, any stashed liquidity is
            // set aside and no longer participates in the protocol
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

            // @dev Deploy the next option round contract & update the current round id
            self.deploy_next_round(l1_data);

            // @dev Return the total payout of the settled round
            total_payout
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

        // @dev Deploy the next option round, if data is supplied, calculate the strike
        // price and cap level and set the next round's data
        fn deploy_next_round(ref self: ContractState, l1_data: L1Data) {
            let vault_address: ContractAddress = get_contract_address();
            let round_id: u256 = self.current_round_id.read() + 1;

            // @dev Create this round's constructor args
            let mut calldata: Array<felt252> = array![];
            let pricing_data = self.l1_data_to_round_data(l1_data);
            let constructor_args = OptionRoundConstructorArgs {
                vault_address, round_id, pricing_data
            };

            calldata.append_serde(constructor_args);

            // @dev Deploy the round
            let (address, _) = deploy_syscall(
                self.option_round_class_hash.read(), 'some salt', calldata.span(), false
            )
                .expect(Errors::OptionRoundDeploymentFailed);
            let round = IOptionRoundDispatcher { contract_address: address };

            // @dev Update the current round id
            self.current_round_id.write(round_id);

            // @dev Store this round address
            self.round_addresses.write(round_id, address);

            // @dev Emit option round deployed event
            self
                .emit(
                    Event::OptionRoundDeployed(
                        OptionRoundDeployed {
                            round_id,
                            address,
                            auction_start_date: round.get_auction_start_date(),
                            auction_end_date: round.get_auction_end_date(),
                            option_settlement_date: round.get_option_settlement_date(),
                            pricing_data
                        }
                    )
                );
        }

        /// Fossil

        // @dev Converts L1 data from Fossil (or 3rd party) to pricing data for the round
        fn l1_data_to_round_data(self: @ContractState, l1_data: L1Data) -> PricingData {
            let L1Data { twap, volatility, reserve_price } = l1_data;
            let alpha = self.alpha.read();
            let vault_type = self.vault_type.read();

            let cap_level = calculate_cap_level(alpha, volatility);
            let strike_price = calculate_strike_price(vault_type, twap, volatility);

            PricingData { strike_price, cap_level, reserve_price }
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
                realized_deposit += self.positions.entry(account).entry(i).read();

                // @dev Get the liquidity that became unlocked for the account in this round
                let account_unlocked_liq = self
                    .get_liquidity_unlocked_for_account_in_round(account, realized_deposit, i);

                // @dev Get the liquidity that remained for the account in this round
                let account_remaining_liq = self
                    .get_account_liquidity_that_remained_in_round_unstashed(
                        account, realized_deposit, i
                    );

                realized_deposit = account_unlocked_liq + account_remaining_liq;

                i += 1;
            };

            // @dev Add in the liquidity provider's current round deposit
            realized_deposit + self.positions.entry(account).entry(current_round_id).read()
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
                        .entry(account)
                        .entry(current_round_id + 1)
                        .read();
                    // @dev There are only premium/unsold liquidity after the auction ends
                    if state == OptionRoundState::Running {
                        // @dev Adds 0 if the premium/unsold liquidity was already moved as a
                        // deposit into the upcoming round
                        upcoming_round_deposit += self
                            .get_liquidity_unlocked_for_account_in_round(
                                account, current_round_deposit, current_round_id
                            );
                    }

                    (current_round_deposit, upcoming_round_deposit)
                },
            }
        }

        // @dev Combine deposits from the last checkpoint into a single deposit for the current
        // round, and if there are premiums/unsold liquidity collectable, add them as a deposit for
        // the upcoming round
        fn refresh_position(ref self: ContractState, account: ContractAddress) {
            // @dev Get the refreshed current and upcoming round deposits
            let current_round_id = self.current_round_id.read();
            let (current_round_deposit, upcoming_round_deposit) = self
                .get_refreshed_position(account);

            // @dev Update the account's current round deposit and checkpoint
            if current_round_deposit != self
                .positions
                .entry(account)
                .entry(current_round_id)
                .read() {
                self.positions.entry(account).entry(current_round_id).write(current_round_deposit);
            }
            if current_round_id - 1 != self.position_checkpoints.read(account) {
                self.position_checkpoints.write(account, current_round_id - 1);
            }

            // @dev If the current round is Running, there could be premiums/unsold liquidity to
            // to move to the upcoming round
            if self
                .get_round_dispatcher(current_round_id)
                .get_state() == OptionRoundState::Running {
                // @dev If the premiums/unsold liquidity were not moved as a deposit into the
                // next round, move them
                if !self.is_premium_moved.entry(account).entry(current_round_id).read() {
                    self.is_premium_moved.entry(account).entry(current_round_id).write(true);
                    // @dev Update the account's upcoming round deposit if it has changed
                    if upcoming_round_deposit != self
                        .positions
                        .entry(account)
                        .entry(current_round_id + 1)
                        .read() {
                        self
                            .positions
                            .entry(account)
                            .entry(current_round_id + 1)
                            .write(upcoming_round_deposit);
                    }
                }
            }
        }

        // @dev Get the premium and unsold liquidity unlocked for an account after a round's auction
        // @param account: The account in question
        // @param account_staring_liq: The liquidity the account locked at the start of the round
        // @param round_id: The round to lookup
        // @note Returns 0 if the round is Open | Running
        // @note Returns 0 if the unlocked liq was moved as a deposit into the next round
        // (refreshed)
        fn get_liquidity_unlocked_for_account_in_round(
            self: @ContractState,
            account: ContractAddress,
            account_starting_liq: u256,
            round_id: u256
        ) -> u256 {
            // @dev If the round is Open | Auctioning, there are no premiums/unsold liquidity yet,
            // return 0 @dev If the unlocked liquidity was moved as a deposit into the next round,
            // return  0
            let round = self.get_round_dispatcher(round_id);
            let state = round.get_state();
            if state == OptionRoundState::Open
                || state == OptionRoundState::Auctioning
                || self.is_premium_moved.entry(account).entry(round_id).read() {
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

        // @dev Get the liquidity that remained for an account after a round settled that was not
        // stashed @param account: The account in question
        // @param account_staring_liq: The liquidity the account locked at the start of the round
        // @param round_id: The round to lookup
        // @note Returns 0 if the round is not Settled
        fn get_account_liquidity_that_remained_in_round_unstashed(
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
                let account_liq_queued = self
                    .queued_liquidity
                    .entry(account)
                    .entry(round_id)
                    .read();
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
