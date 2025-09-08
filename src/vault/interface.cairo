use starknet::{ContractAddress, ClassHash};
use pitch_lake::option_round::interface::OptionRoundState;

use pitch_lake::fossil_client::interface::{JobRequest, L1Data};

// @dev An enum for each type of Vault
#[derive(starknet::Store, Copy, Drop, Serde, PartialEq)]
enum VaultType {
    InTheMoney,
    AtTheMoney,
    OutOfMoney,
}

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

    /// Fossil

    // @dev Get the request for Fossil to fulfill in order to settle the current round
    fn get_request_to_settle_round(self: @TContractState) -> Span<felt252>;

    // @dev When a round settles, the l1 data used to settle round i also deploys round i+1,
    // therefore this request is only needs to initialize the first round
    fn get_request_to_start_first_round(self: @TContractState) -> Span<felt252>;

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

    // @dev Set L1 data to settle the current round and start the next round
    // @dev Called by Pitchlake Verifier
    // @dev Used to initialize the first round and settle all subsequent rounds
    fn fossil_callback(ref self: TContractState, job_request: Span<felt252>, result: Span<felt252>);

    // @dev Start the current round's auction
    // @return The total options available in the auction
    fn start_auction(ref self: TContractState) -> u256;

    // @dev Ends the current round's auction
    // @return The clearing price and total options sold
    fn end_auction(ref self: TContractState) -> (u256, u256);

    // @dev Settle the current round
    // @return The total payout for the round
    fn settle_round(ref self: TContractState) -> u256;
}
