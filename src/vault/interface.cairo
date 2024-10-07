use starknet::{ContractAddress, ClassHash};
use pitch_lake::option_round::interface::OptionRoundState;

// @dev An enum for each type of Vault
#[derive(starknet::Store, Copy, Drop, Serde, PartialEq)]
enum VaultType {
    InTheMoney,
    AtTheMoney,
    OutOfMoney,
}

// @dev Data needed for a round's auction to start
#[derive(Default, PartialEq, Copy, Drop, Serde, starknet::Store)]
struct PricingData {
    strike_price: u256,
    cap_level: u128,
    reserve_price: u256,
}

// @dev Request to settle/start a round
#[derive(Copy, Drop, Serde)]
struct L1DataRequest {
    identifiers: Span<felt252>,
    timestamp: u64,
}

// @dev Data returned from request
#[derive(Default, PartialEq, Drop, Serde, starknet::Store)]
struct L1Data {
    twap: u256,
    volatility: u128,
    reserve_price: u256,
}

// @dev Struct to send result and proving data to `fulfill_request()`
#[derive(Drop, Serde)]
struct L1Result {
    data: L1Data,
    proof: Array<felt252>,
}

// @dev Constructor arguments
#[derive(Drop, Serde)]
struct ConstructorArgs {
    request_fulfiller: ContractAddress,
    eth_address: ContractAddress,
    option_round_class_hash: ClassHash,
    vault_type: VaultType, // replace with strike level and alpha
}

// The interface for the vault contract
#[starknet::interface]
trait IVault<TContractState> {
    /// Reads ///

    // @dev Get the type of vault (ITM | ATM | OTM)
    fn get_vault_type(self: @TContractState) -> VaultType;

    // @dev Get the ETH address
    fn get_eth_address(self: @TContractState) -> ContractAddress;

    //    // @dev Get the amount of time an auction runs for
    //    fn get_auction_run_time(self: @TContractState) -> u64;
    //
    //    // @dev Get the amount of time an option round runs for
    //    fn get_option_run_time(self: @TContractState) -> u64;
    //
    //    // Get the amount of time till starting the next round's auction
    //    fn get_round_transition_period(self: @TContractState) -> u64;

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

    // @dev Get the earliest Fossil request required to settle the current round
    fn get_request_to_settle_round(self: @TContractState) -> L1DataRequest;

    // @dev Get the earliest Fossil request required to start the current round's auction if not
    // already set or refreshing the data
    fn get_request_to_start_auction(self: @TContractState) -> L1DataRequest;

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

    // @dev Fulfill a pricing data request
    fn fulfill_request(ref self: TContractState, request: L1DataRequest, result: L1Result) -> bool;

    //    // @dev Sets pricing data for the current round to settle with. The pricing data must have
    //    a // timestamp that is equal to the currnet round's settlement date with
    //    TIMESTAMP_TOLERANCE fn fulfill_request_to_settle_round(
    //        ref self: TContractState, request: L1DataRequest, result: L1Result
    //    ) -> bool;
    //
    //    // @dev Sets pricing data for the current round to start with
    //    // @note When pricing data is set to settle a round, it is also used to deploy the next
    //    round.
    //    // This is fine for all rounds > 1, but in order for the first round to start, this
    //    function // must be used to set the pricing data, after this only
    //    `set_pricing_data_to_settle_round()`
    //    // needs to be used.
    //    // @note This function can also be used to refresh the pricing data for the current round
    //    if it // has not started yet. This is because all rounds > 1 will deploy with pricing data
    //    already // set, but they will not start until their auction start dates. This means a user
    //    could use // this function to update the pricing data as long as the timestamp is between
    //    the deployment // date and the auction start date
    //    fn fulfill_request_to_start_auction(
    //        ref self: TContractState, request: L1DataRequest, result: L1Result
    //    ) -> bool;

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
