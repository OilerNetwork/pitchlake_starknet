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
    use pitch_lake::fossil_client::interface::{L1Data, JobRequest};
    use pitch_lake::vault::interface::{ConstructorArgs, IVault, VaultType,};
    use pitch_lake::option_round::contract::{OptionRound, OptionRound::Errors as RoundErrors};
    use pitch_lake::option_round::interface::{
        ConstructorArgs as OptionRoundConstructorArgs, OptionRoundState, IOptionRoundDispatcher,
        IOptionRoundDispatcherTrait, PricingData,
    };
    use pitch_lake::library::constants::{BPS_i128, BPS_felt252, BPS_u128, BPS_u256};
    use pitch_lake::library::utils::{assert_equal_in_range, generate_request_id};
    use pitch_lake::library::pricing_utils::{calculate_strike_price, calculate_cap_level};
    use pitch_lake::library::constants::{REQUEST_TOLERANCE, PROGRAM_ID};
    use pitch_lake::types::{Bid};

    // *************************************************************************
    //                              STORAGE
    // *************************************************************************

    #[storage]
    struct Storage {
        ///
        vault_type: VaultType,
        alpha: u128,
        strike_level: i128,
        round_transition_duration: u64,
        auction_duration: u64,
        round_duration: u64,
        ///
        l1_data: Map<u64, L1Data>,
        option_round_class_hash: ClassHash,
        eth_address: ContractAddress,
        fossil_client_address: ContractAddress,
        round_addresses: Map<u64, ContractAddress>,
        ///
        // @note could use usize ?
        current_round_id: u64,
        ///
        // @note could use CA, (usize, u256) ?
        positions: Map<ContractAddress, Map<u64, u256>>,
        ///
        vault_locked_balance: u256,
        vault_unlocked_balance: u256,
        vault_stashed_balance: u256,
        ///
        // @note could use CA, usize ?
        position_checkpoints: Map<ContractAddress, u64>,
        // @note could use CA, usize ?
        stash_checkpoints: Map<ContractAddress, u64>,
        // @note could use CA, (usize, bool) ?
        is_premium_moved: Map<ContractAddress, Map<u64, bool>>,
        ///
        // @note could use CA, (usize, u256)
        queued_liquidity: Map<ContractAddress, Map<u64, u256>>,
    }

    // *************************************************************************
    //                              Constructor
    // *************************************************************************

    #[constructor]
    fn constructor(ref self: ContractState, args: ConstructorArgs) {
        // @dev Get the constructor arguments
        let ConstructorArgs { fossil_client_address,
        eth_address,
        option_round_class_hash,
        strike_level,
        alpha,
        round_transition_duration,
        auction_duration,
        round_duration } =
            args;

        // @dev Set the Vault's parameters
        self.fossil_client_address.write(fossil_client_address);
        self.eth_address.write(eth_address);
        self.option_round_class_hash.write(option_round_class_hash);
        self.round_transition_duration.write(round_transition_duration);
        self.auction_duration.write(auction_duration);
        self.round_duration.write(round_duration);

        // @dev Alpha is between 0.01% and 100.00%
        assert(alpha.is_non_zero() && alpha <= BPS_u128, Errors::AlphaOutOfRange);
        self.alpha.write(alpha);

        // @dev Strike level is at least -99.99%
        assert(strike_level > -BPS_i128, Errors::StrikeLevelOutOfRange);
        self.strike_level.write(strike_level);

        // @dev Deploy the first round
        self.deploy_next_round(Default::default());
    }

    // *************************************************************************
    //                              Errors
    // *************************************************************************

    mod Errors {
        const AlphaOutOfRange: felt252 = 'Alpha out of range';
        const StrikeLevelOutOfRange: felt252 = 'Strike level out of range';
        // Fossil
        const CallerNotFossilClient: felt252 = 'Caller not Fossil client';
        const InvalidL1Data: felt252 = 'Invalid L1 data';
        const L1DataNotAcceptedNow: felt252 = 'L1 data not accepted now';
        const L1DataOutOfRange: felt252 = 'L1 data out of range';
        // Withdraw/queuing withdrawals
        const InsufficientBalance: felt252 = 'Insufficient unlocked balance';
        const QueueingMoreThanPositionValue: felt252 = 'Insufficient balance to queue';
        const WithdrawalQueuedWhileUnlocked: felt252 = 'Can only queue while locked';
        // Deploying option rounds
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

        // Option round events
        PricingDataSet: PricingDataSet,
        AuctionStarted: AuctionStarted,
        AuctionEnded: AuctionEnded,
        OptionRoundSettled: OptionRoundSettled,
        BidPlaced: BidPlaced,
        BidUpdated: BidUpdated,
        UnusedBidsRefunded: UnusedBidsRefunded,
        OptionsMinted: OptionsMinted,
        OptionsExercised: OptionsExercised,
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
        bps: u128,
        round_id: u64,
        account_queued_liquidity_before: u256,
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
        round_id: u64,
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

    #[derive(Drop, starknet::Event, PartialEq)]
    struct PricingDataSet {
        pricing_data: PricingData,
        round_id: u64,
        round_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct AuctionStarted {
        starting_liquidity: u256,
        options_available: u256,
        round_id: u64,
        round_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct AuctionEnded {
        options_sold: u256,
        clearing_price: u256,
        unsold_liquidity: u256,
        clearing_bid_tree_nonce: u64,
        round_id: u64,
        round_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct OptionRoundSettled {
        settlement_price: u256,
        payout_per_option: u256,
        round_id: u64,
        round_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct BidPlaced {
        #[key]
        account: ContractAddress,
        bid_id: felt252,
        amount: u256,
        price: u256,
        bid_tree_nonce_now: u64,
        round_id: u64,
        round_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct BidUpdated {
        #[key]
        account: ContractAddress,
        bid_id: felt252,
        price_increase: u256,
        bid_tree_nonce_before: u64,
        bid_tree_nonce_now: u64,
        round_id: u64,
        round_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct UnusedBidsRefunded {
        #[key]
        account: ContractAddress,
        refunded_amount: u256,
        round_id: u64,
        round_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct OptionsMinted {
        #[key]
        account: ContractAddress,
        minted_amount: u256,
        round_id: u64,
        round_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct OptionsExercised {
        #[key]
        account: ContractAddress,
        total_options_exercised: u256,
        mintable_options_exercised: u256,
        exercised_amount: u256,
        round_id: u64,
        round_address: ContractAddress,
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

        fn get_fossil_client_address(self: @ContractState) -> ContractAddress {
            self.fossil_client_address.read()
        }

        fn get_alpha(self: @ContractState) -> u128 {
            self.alpha.read()
        }

        fn get_strike_level(self: @ContractState) -> i128 {
            self.strike_level.read()
        }

        fn get_round_transition_duration(self: @ContractState) -> u64 {
            self.round_transition_duration.read()
        }

        fn get_auction_duration(self: @ContractState) -> u64 {
            self.auction_duration.read()
        }

        fn get_round_duration(self: @ContractState) -> u64 {
            self.round_duration.read()
        }


        fn get_round_address(self: @ContractState, option_round_id: u64) -> ContractAddress {
            self.round_addresses.read(option_round_id)
        }

        fn get_current_round_id(self: @ContractState) -> u64 {
            self.current_round_id.read()
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

        fn get_vault_queued_bps(self: @ContractState) -> u128 {
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
                false => ((BPS_u256 * queued_liq) / total_liq).try_into().unwrap()
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

        fn get_account_queued_bps(self: @ContractState, account: ContractAddress) -> u128 {
            // @dev Get the liquidity locked at the start of the current round
            let current_round_id = self.current_round_id.read();
            let total_liq = self.get_realized_deposit_for_current_round(account);
            // @dev Get the amount the account queued
            let queued_liq = self.queued_liquidity.entry(account).entry(current_round_id).read();

            // @dev Calculate the BPS % of the starting liquidity that is queued, avoiding division
            // by 0
            match total_liq.is_zero() {
                true => 0,
                false => ((BPS_u256 * queued_liq) / total_liq).try_into().unwrap()
            }
        }

        /// Fossil

        fn get_request_to_settle_round(self: @ContractState) -> Span<felt252> {
            // @dev Get the current round's settlement date
            let settlement_date = self
                .get_round_dispatcher(self.current_round_id.read())
                .get_option_settlement_date();

            self.generate_job_request(settlement_date)
        }

        fn get_request_to_start_first_round(self: @ContractState) -> Span<felt252> {
            // @dev Get the current round's deployment date
            let deployment_date = self.get_round_dispatcher(1).get_deployment_date();

            self.generate_job_request(deployment_date)
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

        fn queue_withdrawal(ref self: ContractState, bps: u128) {
            // @dev If the current round is Open, there is no locked liqudity to queue, exit early
            let current_round_id = self.current_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            let state = current_round.get_state();
            if state == OptionRoundState::Open {
                return;
            }

            // @dev Check the caller is not queueing more than the max BPS
            assert(bps <= BPS_u128, Errors::QueueingMoreThanPositionValue);

            // @dev Get the caller's calculated current round deposit
            let account = get_caller_address();
            self.refresh_position(account);
            let current_round_deposit = self.get_realized_deposit_for_current_round(account);

            // @dev Calculate the starting liquidity for the account being queued
            let account_queued_liquidity_now = (current_round_deposit * bps.into()) / BPS_u256;

            // @dev Calculate the's starting liquidity for the vault being queued
            let vault_previously_queued_liquidity = self
                .queued_liquidity
                .entry(get_contract_address())
                .entry(current_round_id)
                .read();
            let account_queued_liquidity_before = self
                .queued_liquidity
                .entry(account)
                .entry(current_round_id)
                .read();
            let vault_queued_liquidity_now = vault_previously_queued_liquidity
                - account_queued_liquidity_before
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
                            account,
                            bps,
                            round_id: current_round_id,
                            account_queued_liquidity_before,
                            account_queued_liquidity_now,
                            vault_queued_liquidity_now
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
        fn fossil_client_callback(ref self: ContractState, l1_data: L1Data, timestamp: u64) {
            // @dev Only the Fossil Client contract can call this function
            assert(
                get_caller_address() == self.fossil_client_address.read(),
                Errors::CallerNotFossilClient
            );

            // @dev Assert the L1 data is valid
            let L1Data { twap, volatility: _, reserve_price } = l1_data;
            assert(twap.is_non_zero() && reserve_price.is_non_zero(), Errors::InvalidL1Data);

            // @dev Requests can only be fulfilled if the current round is Running, or if the
            // first round is Open
            let current_round_id = self.current_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            let state = current_round.get_state();

            assert(
                state == OptionRoundState::Running
                    || (current_round_id == 1 && state == OptionRoundState::Open),
                Errors::L1DataNotAcceptedNow
            );

            // @dev If the current round is Running, the l1 data is being used to settle it
            if state == OptionRoundState::Running {
                // @dev Ensure now is >= the settlement date
                let now = get_block_timestamp();
                let settlement_date = current_round.get_option_settlement_date();
                assert(now >= settlement_date, Errors::L1DataNotAcceptedNow);

                // @dev Ensure the job request's timestamp is for the settlement date
                assert(timestamp == settlement_date, Errors::L1DataOutOfRange);

                // @dev Store l1 data for this round's settlement
                // @note Could settle round right now instead of storing the results ?
                self.l1_data.entry(current_round_id).write(l1_data);
            } // @dev If the first round is Open, the result is being used to set the pricing data for its auction to start
            else {
                // // @dev Ensure now < auction start date
                // let now = get_block_timestamp();
                // let auction_start_date = current_round.get_auction_start_date();
                // assert(now < auction_start_date, Errors::L1DataNotAcceptedNow);

                // @dev Ensure the job request's timestamp is for the round's deployment date
                let deployment_date = current_round.get_deployment_date();
                assert(timestamp == deployment_date, Errors::L1DataOutOfRange);

                // @dev Set the round's pricing data directly
                current_round.set_pricing_data(self.convert_l1_data_to_round_data(l1_data));

                // @dev Emit pricing data set event
                self
                    .emit(
                        Event::PricingDataSet(
                            PricingDataSet { pricing_data: l1_data, round_id: current_round_id }
                        )
                    );
            }
        }

        fn start_auction(ref self: ContractState) -> u256 {
            // @dev Update all unlocked liquidity to locked
            let unlocked_liquidity_before_auction = self.vault_unlocked_balance.read();
            self.vault_locked_balance.write(unlocked_liquidity_before_auction);
            self.vault_unlocked_balance.write(0);

            // @dev Start the current round's auction and return the total options available
            let current_round_id = self.current_round_id.read();
            let current_round_address = self.round_addresses.read(current_round_id);
            let options_available = self
                .get_round_dispatcher(current_round_id)
                .start_auction(unlocked_liquidity_before_auction);

            self.emit(Event::AuctionStarted(AuctionStarted {
                starting_liquidity: unlocked_liquidity_before_auction,
                options_available,
                round_id: current_round_id,
                round_address: current_round_address,
            }));

            options_available
        }

        fn end_auction(ref self: ContractState) -> (u256, u256) {
            // @dev End the current round's auction
            let current_round_id = self.current_round_id.read();
            let current_round_address = self.round_addresses.read(current_round_id);
            let current_round = self.get_round_dispatcher(current_round_id);
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
            self.emit(Event::AuctionEnded(AuctionEnded {
                options_sold,
                clearing_price,
                unsold_liquidity,
                clearing_bid_tree_nonce: current_round.get_bid_tree_nonce(),
                round_id: current_round_id,
                round_address: current_round_address,
            }));

            (clearing_price, options_sold)
        }

        fn settle_round(ref self: ContractState) -> u256 {
            // @dev Get pricing data set for the current round's settlement
            let current_round_id = self.current_round_id.read();
            let L1Data { twap, volatility, reserve_price } = self
                .l1_data
                .entry(current_round_id)
                .read();

            assert(
                twap.is_non_zero() && reserve_price.is_non_zero(), RoundErrors::PricingDataNotSet
            );

            // @dev Settle the current round and return the total payout
            let current_round = self.get_round_dispatcher(current_round_id);
            let total_payout = current_round.settle_round(twap);

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
            self.deploy_next_round(L1Data { twap, volatility, reserve_price });

            // @dev Return the total payout of the settled round
            total_payout
        }

        // Option round user actions

        fn place_bid(ref self: ContractState, amount: u256, price: u256) -> Bid {
            let account = get_caller_address();
            let current_round_id = self.current_round_id.read();
            let current_round_address = self.round_addresses.read(current_round_id);
            let current_round = self.get_round_dispatcher(current_round_id);
            
            let bid = current_round.place_bid(account, amount, price);
            
            self.emit(Event::BidPlaced(BidPlaced {
                account,
                bid_id: bid.bid_id,
                amount,
                price,
                bid_tree_nonce_now: bid.tree_nonce + 1,
                round_id: current_round_id,
                round_address: current_round_address,
            }));

            bid
        }

        fn update_bid(ref self: ContractState, bid_id: felt252, price_increase: u256) -> Bid {
            let account = get_caller_address();
            let current_round_id = self.current_round_id.read();
            let current_round_address = self.round_addresses.read(current_round_id);
            let current_round = self.get_round_dispatcher(current_round_id);
            
            let updated_bid = current_round.update_bid(account, bid_id, price_increase);
            
            self.emit(Event::BidUpdated(BidUpdated {
                account,
                bid_id,
                price_increase,
                bid_tree_nonce_before: updated_bid.tree_nonce,
                bid_tree_nonce_now: updated_bid.tree_nonce + 1,
                round_id: current_round_id,
                round_address: current_round_address,
            }));

            updated_bid
        }

        fn refund_unused_bids(
            ref self: ContractState, 
            round_address: ContractAddress, 
            account: ContractAddress
        ) -> u256 {
            // Get round info from address
            let round = IOptionRoundDispatcher { contract_address: round_address };
            let round_id = round.get_round_id();

            // Refund unused bids
            let refunded_amount = round.refund_unused_bids(account);

            // Emit event
            self.emit(Event::UnusedBidsRefunded(UnusedBidsRefunded {
                account,
                refunded_amount,
                round_id,
                round_address,
            }));

            refunded_amount
        }

        fn mint_options(ref self: ContractState, round_address: ContractAddress) -> u256 {
            let account = get_caller_address();
            let round = IOptionRoundDispatcher { contract_address: round_address };
            let round_id = round.get_round_id();
            
            let minted_amount = round.mint_options(account);
            
            self.emit(Event::OptionsMinted(OptionsMinted {
                account,
                minted_amount,
                round_id,
                round_address,
            }));

            minted_amount
        }

        fn exercise_options(ref self: ContractState, round_address: ContractAddress) -> u256 {
            let account = get_caller_address();
            let round = IOptionRoundDispatcher { contract_address: round_address };
            let round_id = round.get_round_id();
            
            let (exercised_amount, total_options_exercised, mintable_options_exercised) = 
                round.exercise_options(account);
            
            self.emit(Event::OptionsExercised(OptionsExercised {
                account,
                total_options_exercised,
                mintable_options_exercised,
                exercised_amount,
                round_id,
                round_address,
            }));

            exercised_amount
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

        fn get_round_dispatcher(self: @ContractState, round_id: u64) -> IOptionRoundDispatcher {
            IOptionRoundDispatcher { contract_address: self.round_addresses.read(round_id) }
        }

        /// Basic helpers

        fn get_upcoming_round_id(self: @ContractState) -> u64 {
            let current_round_id = self.current_round_id.read();
            match self.get_round_dispatcher(current_round_id).get_state() {
                OptionRoundState::Open => current_round_id,
                _ => current_round_id + 1
            }
        }

        fn get_round_outcome(self: @ContractState, round_id: u64) -> (u256, u256, u256) {
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

        /// Deploying rounds

        // @dev Deploy the next option round, if data is supplied, calculate the strike
        // price and cap level and set the next round's data
        fn deploy_next_round(ref self: ContractState, l1_data: L1Data) {
            let vault_address: ContractAddress = get_contract_address();
            let round_id: u64 = self.current_round_id.read() + 1;

            // @dev Create this round's constructor args
            let mut calldata: Array<felt252> = array![];
            let pricing_data = self.convert_l1_data_to_round_data(l1_data);

            let round_transition_duration = self.round_transition_duration.read();
            let auction_duration = self.auction_duration.read();
            let round_duration = self.round_duration.read();

            let constructor_args = OptionRoundConstructorArgs {
                vault_address,
                round_id,
                pricing_data,
                round_transition_duration,
                auction_duration,
                round_duration
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
        fn convert_l1_data_to_round_data(self: @ContractState, l1_data: L1Data) -> PricingData {
            if l1_data == Default::default() {
                return PricingData { strike_price: 0, cap_level: 0, reserve_price: 0 };
            }

            let L1Data { twap, volatility, reserve_price } = l1_data;

            let alpha = self.alpha.read();
            let k = self.strike_level.read();

            let cap_level = calculate_cap_level(alpha, k, volatility);
            let strike_price = calculate_strike_price(k, twap);

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
            round_id: u64
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
            round_id: u64
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

                // @dev If the starting liquidity is 0, avoid division by 0
                if round_starting_liq.is_zero() {
                    0
                } else {
                    // @dev Calculate the amount of liquidity the account did not stash
                    let account_remaining_liq_stashed = (round_remaining_liq * account_liq_queued)
                        / round_starting_liq;
                    let account_remaining_liq = (round_remaining_liq * account_starting_liq)
                        / round_starting_liq;
                    let account_remaining_liq_not_stashed = account_remaining_liq
                        - account_remaining_liq_stashed;

                    // @dev Return the remaining liquidity not stashed
                    account_remaining_liq_not_stashed
                }
            }
        }

        // @dev Generate a JobRequest for a specific timestamp
        fn generate_job_request(self: @ContractState, timestamp: u64) -> Span<felt252> {
            let mut serialized_request = array![];
            JobRequest { program_id: PROGRAM_ID, vault_address: get_contract_address(), timestamp }
                .serialize(ref serialized_request);
            serialized_request.span()
        }
    }
}
