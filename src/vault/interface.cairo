use starknet::{ContractAddress};
use pitch_lake_starknet::{
    vault::{contract::Vault},
    market_aggregator::interface::{IMarketAggregator, IMarketAggregatorDispatcher},
    types::{VaultType, OptionRoundState}
};

// The interface for the vault contract
#[starknet::interface]
trait IVault<TContractState> {
    /// Reads ///

    /// Other

    // Get the vault's  manaager address
    // @dev Better access control ? (oz permits ?)
    fn vault_manager(self: @TContractState) -> ContractAddress;

    // Get the type of vault (ITM | ATM | OTM)
    fn vault_type(self: @TContractState) -> VaultType;

    // Get the market aggregator address
    fn get_market_aggregator(self: @TContractState) -> ContractAddress;

    // Get the ETH address
    fn eth_address(self: @TContractState) -> ContractAddress;

    // Get the amount of time an auction runs for
    fn get_auction_run_time(self: @TContractState) -> u64;

    // Get the amount of time an option round runs for
    fn get_option_run_time(self: @TContractState) -> u64;

    // Get the amount of time till starting the next round's auction
    fn get_round_transition_period(self: @TContractState) -> u64;

    // @note Add getters for auction run time & option run time
    // - need to also add to facade, then use in tests for the (not yet created) setters (A1.1)

    /// Rounds

    // @return the current option round id
    fn current_round_id(self: @TContractState) -> u256;

    // @return the contract address of the option round
    fn get_round_address(self: @TContractState, option_round_id: u256) -> ContractAddress;

    /// Liquidity

    // For LPs //

    // Get the liquidity an lp had at the beginning of the current round
    fn get_lp_starting_balance(self: @TContractState, account: ContractAddress) -> u256;


    // Get the liquidity an lp has locked
    fn get_lp_locked_balance(self: @TContractState, account: ContractAddress) -> u256;

    // Get the liquidity an LP has unlocked
    fn get_lp_unlocked_balance(self: @TContractState, account: ContractAddress) -> u256;

    // Get the liquidity an LP queued for stashing in a round
    fn get_lp_queued_balance(
        self: @TContractState, account: ContractAddress, round_id: u256
    ) -> u256;

    // Get the liquidity an LP has stashed in the vault from withdrawal queues
    fn get_lp_stashed_balance(self: @TContractState, account: ContractAddress) -> u256;

    // Get the total liquidity an LP has in the protocol
    fn get_lp_total_balance(self: @TContractState, account: ContractAddress) -> u256;

    // For Vault //

    // Get the total liquidity locked
    fn get_total_locked_balance(self: @TContractState) -> u256;

    // Get the total liquidity unlocked
    fn get_total_unlocked_balance(self: @TContractState) -> u256;

    // Get the total liquidity queued for stashing in a round
    fn get_total_queued_balance(self: @TContractState, round_id: u256) -> u256;

    // Get the total liquidity stashed
    fn get_total_stashed_balance(self: @TContractState) -> u256;


    // Get the total liquidity in the protocol
    fn get_total_balance(self: @TContractState) -> u256;

    /// Writes ///

    /// State transition

    /// Update the params of the current round if there are newer data from Fossil
    fn update_round_params(ref self: TContractState);

    // Start the auction on the next round as long as the current round is Settled and the
    // round transition period has passed. Deploys the next next round and updates the current/next pointers.
    // @return the total options available in the auction
    fn start_auction(ref self: TContractState) -> u256;

    // End the auction in the current round as long as the current round is Auctioning and the auction
    // bidding period has ended.
    // @return the clearing price of the auction
    // @return the total options sold in the auction (@note keep or drop ?)
    fn end_auction(ref self: TContractState) -> (u256, u256);

    // Settle the current option round as long as the current round is Running and the option expiry time has passed.
    // @return The total payout of the option round
    fn settle_option_round(ref self: TContractState) -> (u256, u256);

    /// LP functions

    // Caller withdraws liquidity from their unlocked balance
    // @return The liquidity provider's updated unlocked position
    fn deposit_liquidity(ref self: TContractState, amount: u256, account: ContractAddress) -> u256;

    // Caller withdraws from the vault
    // @return The liquidity provider's updated unlocked position
    fn withdraw_liquidity(ref self: TContractState, amount: u256) -> u256;

    // Caller queues a portion of their currently locked liquidity to be stashed aside, to not roll over
    // into the next round
    fn queue_withdrawal(ref self: TContractState, amount: u256);

    // Liquidity provider withdraws their stashed (queued) withdrawals
    fn claim_queued_liquidity(ref self: TContractState, account: ContractAddress) -> u256;

    /// LP token related

    // LP converts their collateral into LP tokens
    // @note all at once or can LP convert a partial amount ?
    //  - logically i'm pretty sure they could do a partial amount (collecting all rewards in either case)
    fn convert_position_to_lp_tokens(ref self: TContractState, amount: u256);

    // LP converts their (source_round) LP tokens into a position in the current round
    // @dev Premiums/unsold from the source round are not counted
    fn convert_lp_tokens_to_position(ref self: TContractState, source_round: u256, amount: u256);

    // LP token owner converts an amount of source round tokens to target round tokens
    // @dev Rx tokens do not include premiums/unsold from rx (above)
    // This is not a problem for token -> position, but is a problem for
    // token -> token because when rx tokens convert to ry, the ry tokens should
    // be able to collect ry premiums but will not be able to (above)
    // @dev Ry must be running or settled. This way we can know the premiums that the rY tokens earned in the round, and collect them
    // as a deposit into the next round. We need to collect these rY premiums because the LP tokens need to represent the value of a
    // deposit in the round net any premiums from the round.
    // @dev If we do not collect the premiums for rY upon conversion, they would be lost.
    // @return the amount of target round tokens received
    // @dev move entry point to LPToken ?
    fn convert_lp_tokens_to_newer_lp_tokens(
        ref self: TContractState, source_round: u256, target_round: u256, amount: u256
    ) -> u256;
}
