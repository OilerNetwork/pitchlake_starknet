use starknet::{ContractAddress, StorePacking};
use openzeppelin::token::erc20::interface::ERC20ABIDispatcher;
use pitch_lake_starknet::{
    option_round::{contract::OptionRound,},
    market_aggregator::interface::{IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait},
    types::{OptionRoundState, OptionRoundConstructorParams, Bid,}
};

// The option round contract interface
#[starknet::interface]
trait IOptionRound<TContractState> {
    /// Reads ///

    /// Round details

    // @dev The address of the vault that deployed this round
    fn get_vault_address(self: @TContractState) -> ContractAddress;

    // @dev This round's id
    fn get_round_id(self: @TContractState) -> u256;

    // @dev The state of this round
    fn get_state(self: @TContractState) -> OptionRoundState;

    // @dev Get the date the auction can start
    fn get_auction_start_date(self: @TContractState) -> u64;

    // @dev Get the date the auction can end
    fn get_auction_end_date(self: @TContractState) -> u64;

    // @dev Get the date the round can settle
    fn get_option_settlement_date(self: @TContractState) -> u64;

    // @dev The total ETH locked at the start of the auction
    fn get_starting_liquidity(self: @TContractState) -> u256;

    // @dev The total ETH not sold in the auction
    fn get_unsold_liquidity(self: @TContractState) -> u256;

    // @dev The minimum price per option
    fn get_reserve_price(self: @TContractState) -> u256;

    // @dev The strike price for this round in wei
    fn get_strike_price(self: @TContractState) -> u256;

    // @dev The % points (BPS) above the TWAP to cap the payout per option
    fn get_cap_level(self: @TContractState) -> u128;

    // @dev The total number of options available in the auction
    fn get_options_available(self: @TContractState) -> u256;

    // @dev The total options sold after in the auction
    fn get_options_sold(self: @TContractState) -> u256;

    // @dev The price paid for each option after the auction ends
    fn get_clearing_price(self: @TContractState) -> u256;

    // @dev The number of options sold * the price paid for each option
    fn get_total_premium(self: @TContractState) -> u256;

    // @dev The price used to settle the option round
    fn get_settlement_price(self: @TContractState) -> u256;

    // @dev The total amount of ETH paid out to option buyersr
    fn get_total_payout(self: @TContractState) -> u256;

    /// Bids

    // @dev The details of a bid
    // @param bid_id: The id of the bid
    fn get_bid_details(self: @TContractState, bid_id: felt252) -> Bid;

    // @dev The bid ids for an account
    // @param account: The account to get bid ids for
    fn get_account_bids(self: @TContractState, account: ContractAddress) -> Array<Bid>;

    // @dev The number of bids an account has placed
    // @param account: The account to get the number of bids for
    fn get_account_bid_nonce(self: @TContractState, account: ContractAddress) -> u64;

    // @dev The nonce of the entire bid tree
    fn get_bid_tree_nonce(self: @TContractState) -> u64;

    /// Accounts

    // @dev The amount of ETH an account can refund after the auction ends
    // @param account: The account to get the refundable balance for
    fn get_account_refundable_balance(self: @TContractState, account: ContractAddress) -> u256;

    // @dev The amount of options that can be minted for an account after the auction ends,
    // 0 if the account already minted
    // @param account: The account to get the mintable options for
    fn get_account_mintable_options(self: @TContractState, account: ContractAddress) -> u256;

    // @dev The amount of options an account can still mint, plus the amount of option
    // ERC-20 tokens they already own
    // @param account: The account to get the options balance for
    fn get_account_total_options(self: @TContractState, account: ContractAddress) -> u256;

    // @dev The total payout an account can receive from exercising their options
    // @dev account: The account to get the payout for
    fn get_account_payout_balance(self: @TContractState, account: ContractAddress) -> u256;

    /// Writes ///

    /// State transitions

    // @dev Start the round's auction, return the options available in the auction
    // @param starting_liquidity: The total amount of ETH being locked in the auction
    fn start_auction(ref self: TContractState, starting_liquidity: u256) -> u256;

    // @dev End the round's auction, return the price paid for each option and number
    // of options sold
    fn end_auction(ref self: TContractState) -> (u256, u256);

    // @dev Settle the round, return the total payout for all of the (sold) options
    fn settle_round(ref self: TContractState, settlement_price: u256) -> u256;

    // @note Probably removing this
    fn update_round_params(
        ref self: TContractState, reserve_price: u256, cap_level: u128, strike_price: u256
    );

    /// Account functions

    // @dev The caller places a bid in the auction
    // @param amount: The max amount of options being bid for
    // @param price: The max price per option being bid
    // @return The bid struct just created
    fn place_bid(ref self: TContractState, amount: u256, price: u256) -> Bid;

    // @dev The caller increases one of their bids in the auction
    // @param bid_id: The id of the bid to update
    // @param price_increase: The amount to increase the bid's price by
    // @return The updated bid struct
    fn update_bid(ref self: TContractState, bid_id: felt252, price_increase: u256) -> Bid;

    // @dev Refund the account's unused bids from the auction
    // @param account: The account to refund the unused bids for
    // @return The amount of refundable ETH transferred
    fn refund_unused_bids(ref self: TContractState, account: ContractAddress) -> u256;

    // @dev The caller exercises all of their options (mintable and already minted)
    // @param account: The account to exercise the options for
    // @return The amount of exerciseable ETH transferred
    fn exercise_options(ref self: TContractState) -> u256;

    // Convert options won from auction into erc20 tokens
    fn mint_options(ref self: TContractState) -> u256;
}
