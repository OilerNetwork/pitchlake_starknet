use starknet::{ContractAddress, ClassHash};
use pitch_lake::option_round::interface::OptionRoundState;
use pitch_lake::fact_registry::interface::JobRequest;


// @dev An enum for each type of Vault
#[derive(starknet::Store, Copy, Drop, Serde, PartialEq)]
enum VaultType {
    InTheMoney,
    AtTheMoney,
    OutOfMoney,
}

#[derive(PartialEq, Default, Copy, Drop, Serde, starknet::Store)]
struct PricingDataPoints {
    twap: u256,
    volatility: u128,
    reserve_price: u256,
    cap_level: u128,
    strike_price: u256,
}

#[derive(Drop, Serde)]
struct FossilDataPoints {
    twap: u256,
    volatility: u128,
    reserve_price: u256,
}

#[derive(Drop, Serde)]
struct Callback {
    address: ContractAddress,
    selector: felt252,
}

#[derive(Drop, Serde)]
struct PricingDataRequest {
    identifiers: Array<felt252>,
    timestamp: u64,
    callback: Callback,
}

#[derive(Drop, Serde)]
struct ConstructorArgs {
    round_transition_period: u64,
    auction_run_time: u64,
    option_run_time: u64,
    eth_address: ContractAddress,
    vault_type: VaultType,
    fact_registry_address: ContractAddress,
    option_round_class_hash: ClassHash,
}

// The interface for the vault contract
#[starknet::interface]
trait IVault<TContractState> {
    /// Reads ///

    // @dev Get the type of vault (ITM | ATM | OTM)
    fn get_vault_type(self: @TContractState) -> VaultType;

    // @dev Get the market aggregator's address
    fn get_fact_registry_address(self: @TContractState) -> ContractAddress;

    // @dev Get the ETH address
    fn get_eth_address(self: @TContractState) -> ContractAddress;

    // @dev Get the amount of time an auction runs for
    fn get_auction_run_time(self: @TContractState) -> u64;

    // @dev Get the amount of time an option round runs for
    fn get_option_run_time(self: @TContractState) -> u64;

    // Get the amount of time till starting the next round's auction
    fn get_round_transition_period(self: @TContractState) -> u64;

    // @return the current option round id
    fn get_current_round_id(self: @TContractState) -> u256;

    // @return the contract address of the option round
    fn get_round_address(self: @TContractState, option_round_id: u256) -> ContractAddress;

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
    fn get_vault_queued_bps(self: @TContractState) -> u16;

    // @dev The total liquidity for an account
    fn get_account_total_balance(self: @TContractState, account: ContractAddress) -> u256;

    // @dev The liquidity locked for an account
    fn get_account_locked_balance(self: @TContractState, account: ContractAddress) -> u256;

    // @dev The liquidity unlocked for an account
    fn get_account_unlocked_balance(self: @TContractState, account: ContractAddress) -> u256;

    // @dev The liquidity stashed for an account
    fn get_account_stashed_balance(self: @TContractState, account: ContractAddress) -> u256;

    // @dev The account's % (bps) queued for withdrawal once the current round settles
    fn get_account_queued_bps(self: @TContractState, account: ContractAddress) -> u16;

    /// Fossil

    // @dev Get the (minimum) Fossil request needed to settle the current round
    fn get_pricing_data_request(self: @TContractState) -> PricingDataRequest;


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
    fn queue_withdrawal(ref self: TContractState, bps: u16);

    // @dev The caller withdraws all of an account's stashed liquidity for the account
    // @param account: The account to withdraw stashed liquidity for
    // @return The amount withdrawn
    fn withdraw_stash(ref self: TContractState, account: ContractAddress) -> u256;

    /// State transitions

    // @dev Update the pricing data points for the current round
    fn refresh_round_pricing_data(ref self: TContractState, job_request: JobRequest);

    // @dev Start the current round's auction
    // @return The total options available in the auction
    fn start_auction(ref self: TContractState) -> u256;

    // @dev Ends the current round's auction
    // @return The clearing price and total options sold
    fn end_auction(ref self: TContractState) -> (u256, u256);

    // @dev Settle the current round
    // @return The total payout for the round
    fn settle_round(ref self: TContractState, job_request: JobRequest) -> u256;
}
