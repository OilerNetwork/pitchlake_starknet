#[starknet::contract]
pub mod Vault {
    use core::num::traits::Zero;
    use fp::{UFixedPoint123x128, UFixedPoint123x128Impl, UFixedPoint123x128StorePacking};
    use openzeppelin_token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin_utils::serde::SerializedAppend;
    use pitch_lake::library::constants::{BPS_i128, BPS_u128, BPS_u256};
    use pitch_lake::library::pricing_utils::{calculate_cap_level, calculate_strike_price};
    use pitch_lake::option_round::interface::{
        ConstructorArgs as OptionRoundConstructorArgs, IOptionRoundDispatcher,
        IOptionRoundDispatcherTrait, OptionRoundState, PricingData,
    };
    use pitch_lake::vault::interface::{ConstructorArgs, IVault, JobRequest, L1Data, VerifierData};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::syscalls::deploy_syscall;
    use starknet::{
        ClassHash, ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
    };


    // *************************************************************************
    //                              STORAGE
    // *************************************************************************

    #[storage]
    struct Storage {
        ///
        alpha: u128,
        strike_level: i128,
        deployment_block: u64,
        round_transition_duration: u64,
        auction_duration: u64,
        round_duration: u64,
        program_id: felt252,
        proving_delay: u64,
        ///
        l1_data: Map<u64, L1Data>,
        option_round_class_hash: ClassHash,
        eth_address: ContractAddress,
        verifier_address: ContractAddress,
        round_addresses: Map<u64, ContractAddress>,
        ///
        current_round_id: u64,
        ///
        positions: Map<ContractAddress, Map<u64, u256>>,
        ///
        vault_locked_balance: u256,
        vault_unlocked_balance: u256,
        vault_stashed_balance: u256,
        ///
        position_checkpoints: Map<ContractAddress, u64>,
        stash_checkpoints: Map<ContractAddress, u64>,
        is_premium_moved: Map<ContractAddress, Map<u64, bool>>,
        ///
        queued_liquidity: Map<ContractAddress, Map<u64, u256>>,
    }

    // *************************************************************************
    //                              Constructor
    // *************************************************************************

    #[constructor]
    fn constructor(ref self: ContractState, args: ConstructorArgs) {
        // @dev Get the constructor arguments
        let ConstructorArgs {
            verifier_address,
            eth_address,
            option_round_class_hash,
            strike_level,
            alpha,
            round_transition_duration,
            auction_duration,
            round_duration,
            program_id,
            proving_delay,
        } = args;

        // @dev Set the Vault's parameters
        self.verifier_address.write(verifier_address);
        self.eth_address.write(eth_address);
        self.option_round_class_hash.write(option_round_class_hash);
        self.round_transition_duration.write(round_transition_duration);
        self.auction_duration.write(auction_duration);
        self.round_duration.write(round_duration);
        self.deployment_block.write(starknet::get_block_number());
        self.program_id.write(program_id);
        self.proving_delay.write(proving_delay);

        // @dev Alpha is between 0.01% and 100.00%
        assert(alpha.is_non_zero() && alpha <= BPS_u128, Errors::AlphaOutOfRange);
        self.alpha.write(alpha);

        // @dev Strike level is at least -99.99%
        assert(strike_level > -BPS_i128, Errors::StrikeLevelOutOfRange);
        self.strike_level.write(strike_level);

        // @dev Deploy the first round with default pricing data, will be initialized later
        // before the auction can start
        self.deploy_next_round(Default::default(), 1);
    }

    // *************************************************************************
    //                              Errors
    // *************************************************************************

    pub mod Errors {
        pub const AlphaOutOfRange: felt252 = 'Alpha out of range';
        pub const StrikeLevelOutOfRange: felt252 = 'Strike level out of range';
        // Verifier
        pub const L1DataNotAcceptedNow: felt252 = 'L1 data not accepted now';
        pub const L1DataOutOfRange: felt252 = 'L1 data out of range';
        pub const InvalidL1Data: felt252 = 'Invalid L1 data';
        pub const CallerNotVerifier: felt252 = 'Caller not the verifier';
        pub const InvalidRequest: felt252 = 'Invalid request';
        pub const FailedToDeserializeJobRequest: felt252 = 'Failed to deserialize request';
        pub const FailedToDeserializeVerifierData: felt252 = 'Failed to desr. verifier data';
        // Withdraw/queuing withdrawals
        pub const InsufficientBalance: felt252 = 'Insufficient unlocked balance';
        pub const QueueingMoreThanPositionValue: felt252 = 'Insufficient balance to queue';
        pub const WithdrawalQueuedWhileUnlocked: felt252 = 'Can only queue while locked';
        // Deploying option rounds
        pub const OptionRoundDeploymentFailed: felt252 = 'Option round deployment failed';
    }

    // *************************************************************************
    //                              EVENTS
    // *************************************************************************

    #[event]
    #[derive(Serde, PartialEq, Drop, starknet::Event)]
    pub enum Event {
        Deposit: Deposit,
        Withdrawal: Withdrawal,
        WithdrawalQueued: WithdrawalQueued,
        StashWithdrawn: StashWithdrawn,
        OptionRoundDeployed: OptionRoundDeployed,
        FossilCallbackSuccess: FossilCallbackSuccess,
    }

    // @dev Emitted when a deposit is made for an account
    // @member account: The account the deposit was made for
    // @member amount: The amount deposited
    // @member: account_unlocked_balance_now: The account's unlocked balance after the deposit
    // @member: vault_unlocked_balance_now: The vault's unlocked balance after the deposit
    #[derive(Serde, Drop, starknet::Event, PartialEq)]
    pub struct Deposit {
        #[key]
        pub account: ContractAddress,
        pub amount: u256,
        pub account_unlocked_balance_now: u256,
        pub vault_unlocked_balance_now: u256,
    }

    // @dev Emitted when an account makes a withdrawal
    // @member account: The account that made the withdrawal
    // @member amount: The amount withdrawn
    // @member account_unlocked_balance_now: The account's unlocked balance after the withdrawal
    // @member vault_unlocked_balance_now: The vault's unlocked balance after the withdrawal
    #[derive(Serde, Drop, starknet::Event, PartialEq)]
    pub struct Withdrawal {
        #[key]
        pub account: ContractAddress,
        pub amount: u256,
        pub account_unlocked_balance_now: u256,
        pub vault_unlocked_balance_now: u256,
    }

    // @dev Emitted when an account queues a withdrawal
    // @member account: The account that queued the withdrawal
    // @member bps: The BPS % of the account's remaining liquidity to stash
    // @member account_queued_liquidity_now: The account's starting liquidity queued after the
    // withdrawal @member vault_queued_liquidity_now: The vault's starting liquidity queued after
    // the withdrawal
    #[derive(Serde, Drop, starknet::Event, PartialEq)]
    pub struct WithdrawalQueued {
        #[key]
        pub account: ContractAddress,
        pub bps: u128,
        pub round_id: u64,
        pub account_queued_liquidity_before: u256,
        pub account_queued_liquidity_now: u256,
        pub vault_queued_liquidity_now: u256,
    }

    // @dev Emitted when an account withdraws their stashed liquidity
    // @member account: The account that withdrew the stashed liquidity
    // @member amount: The amount withdrawn
    // @member vault_stashed_balance_now: The vault's stashed balance after the withdrawal
    #[derive(Serde, Drop, starknet::Event, PartialEq)]
    pub struct StashWithdrawn {
        #[key]
        pub account: ContractAddress,
        pub amount: u256,
        pub vault_stashed_balance_now: u256,
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
    pub struct OptionRoundDeployed {
        pub round_id: u64,
        pub address: ContractAddress,
        pub auction_start_date: u64,
        pub auction_end_date: u64,
        pub option_settlement_date: u64,
        pub pricing_data: PricingData,
    }

    // @dev Emitted when L1 data is successfully processed by the vault
    #[derive(Serde, Drop, starknet::Event, PartialEq)]
    pub struct FossilCallbackSuccess {
        pub l1_data: L1Data,
        pub timestamp: u64,
    }


    // *************************************************************************
    //                            IMPLEMENTATION
    // *************************************************************************

    #[abi(embed_v0)]
    pub impl VaultImpl of IVault<ContractState> {
        // ***********************************
        //               READS
        // ***********************************

        ///

        fn get_eth_address(self: @ContractState) -> ContractAddress {
            self.eth_address.read()
        }

        fn get_verifier_address(self: @ContractState) -> ContractAddress {
            self.verifier_address.read()
        }

        fn get_alpha(self: @ContractState) -> u128 {
            self.alpha.read()
        }

        fn get_strike_level(self: @ContractState) -> i128 {
            self.strike_level.read()
        }

        fn get_deployment_block(self: @ContractState) -> u64 {
            self.deployment_block.read()
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

        fn get_program_id(self: @ContractState) -> felt252 {
            self.program_id.read()
        }

        fn get_proving_delay(self: @ContractState) -> u64 {
            self.proving_delay.read()
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
                false => ((BPS_u256 * queued_liq) / total_liq).try_into().unwrap(),
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
                false => (locked_liq * account_liq) / total_liq,
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
            }

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
                false => ((BPS_u256 * queued_liq) / total_liq).try_into().unwrap(),
            }
        }

        /// L1 Data

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
                            vault_unlocked_balance_now,
                        },
                    ),
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
                            vault_unlocked_balance_now,
                        },
                    ),
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
                            vault_queued_liquidity_now,
                        },
                    ),
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
                        StashWithdrawn { account, amount, vault_stashed_balance_now },
                    ),
                );

            amount
        }

        /// State transitions

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

        /// L1 Data/Settlement

        fn fossil_callback(
            ref self: ContractState, mut job_request: Span<felt252>, mut result: Span<felt252>,
        ) -> u256 {
            // @dev This function is used to either start round 1's auction (Open -> Auctioning), or
            // to settle each round (Running -> Settled), otherwise data is not being accepted at
            // this time
            let current_round_id = self.current_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);
            let state = current_round.get_state();

            assert(
                (current_round_id == 1 && state == OptionRoundState::Open)
                    || state == OptionRoundState::Running,
                Errors::L1DataNotAcceptedNow,
            );

            /// @dev Validate the request/result (see @proposal for simplification details)

            // @dev Deserialize the job_request and result
            let req: JobRequest = Serde::deserialize(ref job_request)
                .expect(Errors::FailedToDeserializeJobRequest);
            // @dev Deserialize the verifier data
            let res: VerifierData = Serde::deserialize(ref result)
                .expect(Errors::FailedToDeserializeVerifierData);

            // @dev Extract the L1 data we need (could just use res if @proposal is used)
            let l1_data = self.interpret_verifier_data(res);

            // @dev Only the Pitchlake Verifier can call this function
            self.assert_caller_is_verifier();

            // @dev Validate request program ID and vault address
            assert!(
                req.vault_address == get_contract_address(),
                "Invalid Request: vault address expected: {:?}, got: {:?}",
                get_contract_address(),
                req.vault_address,
            );
            assert!(
                req.program_id == self.program_id.read(),
                "Invalid Request: program ID expected: {}, got: {}",
                self.program_id.read(),
                req.program_id,
            );

            // @dev Validate request timestamp is not before block headers are provable
            let now = get_block_timestamp();
            let max_provable_timestamp = now - self.proving_delay.read();
            assert!(
                req.timestamp <= max_provable_timestamp,
                "Invalid Request: timestamp expected: {}, got: {}",
                max_provable_timestamp,
                req.timestamp,
            );

            // @dev Validate bounds for each parameter
            // - If this is the first (special/initialization) callback, the upper bound is the
            // first round's deployment date.
            // - If all other callbacks, the upper bound is the current round's settlement date
            // @dev In either case, the lower bound for the TWAP is the upper bound minus the
            // round_duration, and the reserve price & max return lower bounds are both the upper
            // bound minus (3 x the round_duration)
            let round_duration = self.round_duration.read();
            let upper_bound = if state == OptionRoundState::Running {
                current_round.get_option_settlement_date()
            } else {
                current_round.get_deployment_date()
            };

            let twap_lower_bound = upper_bound - round_duration;
            let reserve_price_lower_bound = upper_bound - (3 * round_duration);
            let max_return_lower_bound = reserve_price_lower_bound;

            assert(
                res.twap_start_timestamp == twap_lower_bound
                    && res.reserve_price_start_timestamp == reserve_price_lower_bound
                    && res.max_return_start_timestamp == max_return_lower_bound
                    && res.twap_end_timestamp == upper_bound
                    && res.reserve_price_end_timestamp == upper_bound
                    && res.max_return_end_timestamp == upper_bound,
                Errors::L1DataOutOfRange,
            );

            // @dev This is needed if the ranges do not correlate to the exact request bounds
            // assert_equal_in_range(...); i.e withing 12 seconds on either side

            // @dev Assert the L1 data is valid
            assert(
                res.twap_result.is_non_zero() && res.reserve_price.is_non_zero(),
                Errors::InvalidL1Data,
            );

            // @dev If the current round is 1 and Open, the L1 data is being used
            // to initialize it, so we send it directly to the round
            if current_round_id == 1 && state == OptionRoundState::Open {
                current_round.set_pricing_data(self.convert_l1_data_to_round_data(l1_data));
                self
                    .emit(
                        Event::FossilCallbackSuccess(
                            FossilCallbackSuccess { l1_data, timestamp: req.timestamp },
                        ),
                    );

                0
            } // @dev If the current round is Running, the L1 data is being used to settle it
            else {
                self.settle_round(current_round_id, current_round, l1_data, req.timestamp)
            }
        }
    }

    // *************************************************************************
    //                          INTERNAL FUNCTIONS
    // *************************************************************************

    #[generate_trait]
    pub impl InternalImpl of VaultInternalTrait {
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
                _ => current_round_id + 1,
            }
        }

        fn get_round_outcome(self: @ContractState, round_id: u64) -> (u256, u256, u256) {
            let round = self.get_round_dispatcher(round_id);
            assert!(
                round_id < self.current_round_id.read(), "Round must be settled to get outcome",
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

        /// Deploying and starting rounds

        // @dev Settle the current round and Open the next
        fn settle_round(
            ref self: ContractState,
            current_round_id: u64,
            current_round: IOptionRoundDispatcher,
            l1_data: L1Data,
            job_request_timestamp: u64,
        ) -> u256 {
            // @dev Settle the current round and return the total payout
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
                false => (remaining_liq * starting_liq_queued) / starting_liq,
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
            self.deploy_next_round(l1_data, current_round_id + 1);

            // @dev Emit fossil callback success event
            self
                .emit(
                    Event::FossilCallbackSuccess(
                        FossilCallbackSuccess { l1_data, timestamp: job_request_timestamp },
                    ),
                );

            // @dev Return the total payout of the settled round
            total_payout
        }

        // @dev Deploy the next option round, then calculate the strike price & cap level to
        // initialize the next round
        fn deploy_next_round(ref self: ContractState, l1_data: L1Data, new_round_id: u64) {
            let vault_address: ContractAddress = get_contract_address();

            // @dev Create this round's constructor args
            let mut calldata: Array<felt252> = array![];

            let round_transition_duration = self.round_transition_duration.read();
            let auction_duration = self.auction_duration.read();
            let round_duration = self.round_duration.read();

            // @dev Cap level is bound > 0 by this function. Only the first round will be deployed
            // with default (0) pricing data (it is initialized after deployment), every other round
            // will have valid pricing
            let pricing_data = if new_round_id == 1 {
                Default::default()
            } else {
                self.convert_l1_data_to_round_data(l1_data)
            };

            let constructor_args = OptionRoundConstructorArgs {
                vault_address,
                pricing_data,
                round_transition_duration,
                auction_duration,
                round_duration,
                round_id: new_round_id,
            };
            calldata.append_serde(constructor_args);

            // @dev Deploy the round
            let (address, _) = deploy_syscall(
                self.option_round_class_hash.read(), 'some salt', calldata.span(), false,
            )
                .expect(Errors::OptionRoundDeploymentFailed);
            let round = IOptionRoundDispatcher { contract_address: address };

            // @dev Update the current round id
            self.current_round_id.write(new_round_id);

            // @dev Store this round address
            self.round_addresses.write(new_round_id, address);

            // @dev Emit option round deployed event
            self
                .emit(
                    Event::OptionRoundDeployed(
                        OptionRoundDeployed {
                            round_id: new_round_id,
                            address,
                            auction_start_date: round.get_auction_start_date(),
                            auction_end_date: round.get_auction_end_date(),
                            option_settlement_date: round.get_option_settlement_date(),
                            pricing_data,
                        },
                    ),
                );
        }

        /// Verifier Integration

        fn assert_caller_is_verifier(self: @ContractState) {
            assert(get_caller_address() == self.verifier_address.read(), Errors::CallerNotVerifier);
        }

        // @dev Generate a JobRequest for a specific timestamp
        fn generate_job_request(self: @ContractState, timestamp: u64) -> Span<felt252> {
            let mut serialized_request = array![];
            JobRequest {
                program_id: self.program_id.read(),
                vault_address: get_contract_address(),
                timestamp,
            }
                .serialize(ref serialized_request);
            serialized_request.span()
        }

        // Interpret l1 data to useful types
        fn interpret_verifier_data(self: @ContractState, raw_l1_data: VerifierData) -> L1Data {
            let VerifierData {
                reserve_price_start_timestamp: _,
                reserve_price_end_timestamp: _,
                reserve_price: reserve_price_fp_felt,
                twap_start_timestamp: _,
                twap_end_timestamp: _,
                twap_result: twap_fp_felt,
                max_return_start_timestamp: _,
                max_return_end_timestamp: _,
                max_return: max_return_fp_felt,
            } = raw_l1_data;

            // @dev Each felt in the VerifierData is a UFixedPoint123x128 representation of a
            // decimal

            // @dev Twap and reserve price are in Wei, we only want the integer portion
            // @dev Cast felt -> fp -> u256
            let (twap, reserve_price): (u256, u256) = {
                let (twap_fp, reserve_price_fp) = {
                    (twap_fp_felt.into(), reserve_price_fp_felt.into())
                };
                (twap_fp.get_integer().into(), reserve_price_fp.get_integer().into())
            };

            // @dev Max return is a percentage, convert to BPS (cast felt -> fp -> u128)
            let BPS: UFixedPoint123x128 = BPS_u128.try_into().unwrap();
            let max_return_fp: UFixedPoint123x128 = max_return_fp_felt.into();
            let max_return: u128 = (max_return_fp * BPS).get_integer().into();

            L1Data { twap, max_return, reserve_price }
        }

        // @dev Converts L1 data from Verifier (twap, max return, reserve price) to pricing data for
        // the round (strike price, cap level, reserve price)
        fn convert_l1_data_to_round_data(self: @ContractState, l1_data: L1Data) -> PricingData {
            if l1_data == Default::default() {
                Default::default()
            }

            let alpha = self.alpha.read();
            let k = self.strike_level.read();
            let L1Data { twap, max_return, reserve_price } = l1_data;

            let cap_level = calculate_cap_level(alpha, k, max_return);
            let strike_price = calculate_strike_price(k, twap);

            PricingData { strike_price, cap_level, reserve_price }
        }

        /// Position management

        // @dev Calculate an account's starting deposit for the current round
        fn get_realized_deposit_for_current_round(
            self: @ContractState, account: ContractAddress,
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
                        account, realized_deposit, i,
                    );

                realized_deposit = account_unlocked_liq + account_remaining_liq;

                i += 1;
            }

            // @dev Add in the liquidity provider's current round deposit
            realized_deposit + self.positions.entry(account).entry(current_round_id).read()
        }

        // @dev Calculate an account's starting deposit for the current round and their deposit
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
                                account, current_round_deposit, current_round_id,
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
            round_id: u64,
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
                    false => { (round_unlocked_liq * account_starting_liq) / round_starting_liq },
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
            round_id: u64,
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
    }
}
