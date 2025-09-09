use starknet::{ContractAddress, ClassHash};
use pitch_lake::option_round::interface::OptionRoundState;

// @dev Constructor arguments
#[derive(Drop, Serde)]
struct ConstructorArgs {
    verifier_address: ContractAddress,
    eth_address: ContractAddress,
    option_round_class_hash: ClassHash,
    alpha: u128,
    strike_level: i128,
    round_transition_duration: u64,
    auction_duration: u64,
    round_duration: u64,
}

// The interface for the vault contract
#[starknet::interface]
trait IVault<TContractState> {
    /// Reads ///

    // @dev Get the alpha risk factor of the vault
    fn get_alpha(self: @TContractState) -> u128;

    // @dev Get the strike level of the vault
    fn get_strike_level(self: @TContractState) -> i128;

    // @dev Get the ETH address
    fn get_eth_address(self: @TContractState) -> ContractAddress;

    // @dev The Fossil verifier address
    fn get_verifier_address(self: @TContractState) -> ContractAddress;

    // @dev The block this vault was deployed at
    fn get_deployment_block(self: @TContractState) -> u64;

    // @dev The number of seconds between a round deploying and its auction starting
    fn get_round_transition_duration(self: @TContractState) -> u64;

    // @dev The number of seconds a round's auction runs for
    fn get_auction_duration(self: @TContractState) -> u64;

    // @dev The number of seconds between a round's auction ending and the round settling
    fn get_round_duration(self: @TContractState) -> u64;

    // @return The current option round id
    fn get_current_round_id(self: @TContractState) -> u64;

    // @return The contract address of the option round
    fn get_round_address(self: @TContractState, option_round_id: u64) -> ContractAddress;

    /// Liquidity

    // @dev The total liquidity in the Vault
    fn get_vault_total_balance(self: @TContractState) -> u256;

    // @dev The total liquidity locked in the Vault
    fn get_vault_locked_balance(self: @TContractState) -> u256;

    // @dev The total liquidity unlocked in the Vault
    fn get_vault_unlocked_balance(self: @TContractState) -> u256;

    // @dev The total liquidity stashed in the Vault
    fn get_vault_stashed_balance(self: @TContractState) -> u256;

    // @dev The total % (bps) queued for withdrawal once the current round settles
    fn get_vault_queued_bps(self: @TContractState) -> u128;

    // @dev The total liquidity for an account
    fn get_account_total_balance(self: @TContractState, account: ContractAddress) -> u256;

    // @dev The liquidity locked for an account
    fn get_account_locked_balance(self: @TContractState, account: ContractAddress) -> u256;

    // @dev The liquidity unlocked for an account
    fn get_account_unlocked_balance(self: @TContractState, account: ContractAddress) -> u256;

    // @dev The liquidity stashed for an account
    fn get_account_stashed_balance(self: @TContractState, account: ContractAddress) -> u256;

    // @dev The account's % (bps) queued for withdrawal once the current round settles
    fn get_account_queued_bps(self: @TContractState, account: ContractAddress) -> u128;

    /// L1 Data

    // For each round, L1 data is required to:
    // 1) Settle the current round
    // 2) Deploy/initialize the next round

    // Round 1 requires a 1-time initialization with L1 data after the Vault's deployment (because
    // there is no previous round), but upon its (and all subsequent round's) settlement the L1 data
    // provided is also used to initialize the next round.
    // The flow looks like this:
    // -> Vault deployed
    // *-> L1 data provided to initialize round 1
    // -> Round 1 auction starts
    // -> Round 1 auction ends
    // *-> L1 data provided to settle round 1 and initialize round 2
    // -> Round 2 auction starts
    // -> Round 2 auction ends
    // *-> L1 data provided to settle round n (2) and initialize round n + 1
    // -> Round n + 1 auction starts
    // -> Round n + 1 auction ends
    // *-> L1 data provided to settle round n + 1 and initialize round n + 2
    // ...

    // Each of these job request is fulfilled and verified by the Pitchlake Verifier (via Fossil).
    // They both result in the `fossil_callback` function being called by the verfier to provide the
    // L1 data to the vault. This function is responsible for routing the data accordingly (either
    // to initialize round 1, or to settle the current round and initialize the next round).

    // @dev Gets the job request required to initialize round 1 (serialized)
    // @dev This job's result is only used once
    fn get_request_to_start_first_round(self: @TContractState) -> Span<felt252>;

    // @dev Gets the job request required to settle the current round (serialized)
    // @dev This job's result is used for each round's settlement. It is also used to initialize the
    // next round.
    fn get_request_to_settle_round(self: @TContractState) -> Span<felt252>;

    /// Writes ///

    /// Account functions

    // @dev The caller adds liquidity for an account's upcoming round deposit (unlocked balance)
    // @param amount: The amount of liquidity to deposit
    // @return The account's updated unlocked position
    fn deposit(ref self: TContractState, amount: u256, account: ContractAddress) -> u256;

    // @dev The caller takes liquidity from their upcoming round deposit (unlocked balance)
    // @param amount: The amount of liquidity to withdraw
    // @return The caller's updated unlocked position
    fn withdraw(ref self: TContractState, amount: u256) -> u256;

    // @dev The caller queues a % of their locked balance to be stashed once the current round
    // settles @param bps: The percentage points <= 10,000 the account queues to stash when the
    // round settles
    fn queue_withdrawal(ref self: TContractState, bps: u128);

    // @dev The caller withdraws all of an account's stashed liquidity for the account
    // @param account: The account to withdraw stashed liquidity for
    // @return The amount withdrawn
    fn withdraw_stash(ref self: TContractState, account: ContractAddress) -> u256;

    /// State transitions

    // @dev Start the current round's auction
    // @return The total options available in the auction
    fn start_auction(ref self: TContractState) -> u256;

    // @dev Ends the current round's auction
    // @return The clearing price and total options sold
    fn end_auction(ref self: TContractState) -> (u256, u256);

    // @dev This function is called by the Pitchlake Verifier to provide L1 data to
    // the vault.
    // @dev This function uses the data to initialize round 1 or to settle the current round (and
    // open the next).
    // @returns 0 if the callback was used to initialize round 1, or the total payout of the settled
    // round if it was used to settle
    fn fossil_callback(
        ref self: TContractState, job_request: Span<felt252>, result: Span<felt252>
    ) -> u256;
}

/// Verifier/Fossil Integration
// Job request sent to Fossil
// vault_address: Which vault is the data for
// timestamp: Upper bound timestamp of gas data used in data calculation
// program_id: 'PITCH_LAKE_V1'
#[derive(Copy, Drop, PartialEq)]
struct JobRequest {
    vault_address: ContractAddress,
    timestamp: u64,
    program_id: felt252,
}

// Fossil job results (args, data and tolerances)
#[derive(Copy, Drop, PartialEq)]
struct VerifierData {
    pub reserve_price_start_timestamp: u64,
    pub reserve_price_end_timestamp: u64,
    pub reserve_price: felt252,
    pub twap_start_timestamp: u64,
    pub twap_end_timestamp: u64,
    pub twap_result: felt252,
    pub max_return_start_timestamp: u64,
    pub max_return_end_timestamp: u64,
    pub max_return: felt252,
}

#[derive(Default, Copy, Drop, Serde, PartialEq, starknet::Store)]
struct L1Data {
    twap: u256,
    max_return: u128,
    reserve_price: u256,
}


// JobRequest <-> Array<felt252>
impl SerdeJobRequest of Serde<JobRequest> {
    fn serialize(self: @JobRequest, ref output: Array<felt252>) {
        self.vault_address.serialize(ref output);
        self.timestamp.serialize(ref output);
        self.program_id.serialize(ref output);
    }

    fn deserialize(ref serialized: Span<felt252>) -> Option<JobRequest> {
        let vault_address: ContractAddress = (*serialized.at(0))
            .try_into()
            .expect('failed to deserialize vault');
        let timestamp: u64 = (*serialized.at(1))
            .try_into()
            .expect('failed to deserialize timestamp');
        let program_id: felt252 = *serialized.at(2);
        Option::Some(JobRequest { program_id, vault_address, timestamp })
    }
}

// VerifierData <-> Array<felt252>
impl SerdeVerifierData of Serde<VerifierData> {
    fn serialize(self: @VerifierData, ref output: Array<felt252>) {
        self.reserve_price_start_timestamp.serialize(ref output);
        self.reserve_price_end_timestamp.serialize(ref output);
        self.reserve_price.serialize(ref output);
        self.twap_start_timestamp.serialize(ref output);
        self.twap_end_timestamp.serialize(ref output);
        self.twap_result.serialize(ref output);
        self.max_return_start_timestamp.serialize(ref output);
        self.max_return_end_timestamp.serialize(ref output);
        self.max_return.serialize(ref output);
    }

    fn deserialize(ref serialized: Span<felt252>) -> Option<VerifierData> {
        let reserve_price_start_timestamp: u64 = (*serialized.at(0))
            .try_into()
            .expect('failed to deser. start timestmp');
        let reserve_price_end_timestamp: u64 = (*serialized.at(1))
            .try_into()
            .expect('failed to deser. end timestamp');
        let reserve_price: felt252 = *serialized.at(2);

        let twap_start_timestamp: u64 = (*serialized.at(3))
            .try_into()
            .expect('failed to deser. start timestmp');
        let twap_end_timestamp: u64 = (*serialized.at(4))
            .try_into()
            .expect('failed to deser. end timestamp');
        let twap_result: felt252 = *serialized.at(5);

        let max_return_start_timestamp: u64 = (*serialized.at(6))
            .try_into()
            .expect('failed to deser. start timestmp');
        let max_return_end_timestamp: u64 = (*serialized.at(7))
            .try_into()
            .expect('failed to deser. end timestamp');
        let max_return: felt252 = *serialized.at(8);

        Option::Some(
            VerifierData {
                reserve_price_start_timestamp,
                reserve_price_end_timestamp,
                reserve_price,
                twap_start_timestamp,
                twap_end_timestamp,
                twap_result,
                max_return_start_timestamp,
                max_return_end_timestamp,
                max_return
            }
        )
    }
}

