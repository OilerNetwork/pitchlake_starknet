use starknet::{ContractAddress, StorePacking};
use openzeppelin::token::erc20::interface::ERC20ABIDispatcher;
use pitch_lake_starknet::{
    option_round::{contract::OptionRound,},
    market_aggregator::interface::{IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait},
    types::{
        OptionRoundState, StartAuctionParams, SettleOptionRoundParams, OptionRoundConstructorParams,
        Bid,
    }
};

// The option round contract interface
#[starknet::interface]
trait IOptionRound<TContractState> {
    // @note This function is being used for testing (event testers)
    fn rm_me(ref self: TContractState, x: u256);
    /// Reads ///

    /// Dates

    // The auction start date
    fn get_auction_start_date(self: @TContractState) -> u64;

    // The auction end date
    fn get_auction_end_date(self: @TContractState) -> u64;


    // The option settlement date
    fn get_option_settlement_date(self: @TContractState) -> u64;


    /// $

    // The total liquidity at the start of the round's auction
    fn starting_liquidity(self: @TContractState) -> u256;

    // The total premium collected from the auction
    fn total_premiums(self: @TContractState) -> u256;

    // The total payouts of the option round
    // @dev OB can collect their share of this total
    fn total_payout(self: @TContractState) -> u256;

    // Gets the clearing price of the auction
    fn get_auction_clearing_price(self: @TContractState) -> u256;

    // The total number of options sold in the option round
    fn total_options_sold(self: @TContractState) -> u256;

    // Get the details of a bid
    fn get_bid_details(self: @TContractState, bid_id: felt252) -> Bid;


    /// Address functions

    // Get the bid nonce for an account
    // @note change this to get_bid_nonce_for
    fn get_bidding_nonce_for(self: @TContractState, option_buyer: ContractAddress) -> u32;

    // Get the bid ids for an account
    fn get_bids_for(self: @TContractState, option_buyer: ContractAddress) -> Array<Bid>;

    // Previously this was the amount of eth locked in the auction
    // @note Consider changing this to returning an array of bid ids

    // Get the refundable bid amount for an account
    // @dev During the auction this value is 0 and after
    // the auction is the amount refundable to the bidder
    // @note This should sum all refundable bid amounts and return the total
    // - i.e if a bidder places 4 bids, 2 fully used, 1 partially used, and 1 fully refundable, the
    // refundable amount should be the value of the last bid + the remaining amount of the partial bid
    fn get_refundable_bids_for(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // Get the total amount of options the option buyer owns, includes the tokenizable amount and the
    // already tokenized (ERC20) amount
    fn get_total_options_balance_for(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // Gets the amount that an option buyer can exercise with their option balance
    fn get_payout_balance_for(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // Get the amount of options that can be tokenized for the option buyer
    fn get_tokenizable_options_for(self: @TContractState, option_buyer: ContractAddress) -> u256;


    /// Other

    // The address of vault that deployed this round
    fn vault_address(self: @TContractState) -> ContractAddress;

    // The constructor parmaeters of the option round
    fn get_constructor_params(self: @TContractState) -> OptionRoundConstructorParams;

    // The state of the option round
    fn get_state(self: @TContractState) -> OptionRoundState;

    // Average base fee over last few months, used to calculate strike price
    fn get_current_average_basefee(self: @TContractState) -> u256;

    // Standard deviation of base fee over last few months, used to calculate strike price
    fn get_standard_deviation(self: @TContractState) -> u256;

    // The strike price of the options
    fn get_strike_price(self: @TContractState) -> u256;

    // The cap level of the options
    fn get_cap_level(self: @TContractState) -> u16;

    // Minimum price per option in the auction
    fn get_reserve_price(self: @TContractState) -> u256;

    // The total number of options available in the auction
    fn get_total_options_available(self: @TContractState) -> u256;

    // Get option round id
    // @note add to facade and tests
    fn get_round_id(self: @TContractState) -> u256;

    /// Writes ///

    /// State transitions

    fn update_round_params(
        ref self: TContractState, reserve_price: u256, cap_level: u16, strike_price: u256
    );

    // Try to start the option round's auction
    // @return the total options available in the auction
    fn start_auction(ref self: TContractState, params: StartAuctionParams) -> u256;

    // Settle the auction if the auction time has passed
    // @return the clearing price of the auction
    // @return the total options sold in the auction (@note keep or drop ?)
    fn end_auction(ref self: TContractState) -> (u256, u256);

    // Settle the option round if past the expiry date and in state::Running
    // @return The total payout of the option round
    fn settle_option_round(
        ref self: TContractState, params: SettleOptionRoundParams
    ) -> (u256, u256);

    /// Option bidder functions

    // Place a bid in the auction
    // @param amount: The max amount of options being bid for
    // @param price: The max price per option being bid (if the clearing price is
    // higher than this, the entire bid is unused and can be claimed back by the bidder)
    // @return if the bid was accepted or rejected

    // @note check all tests match new format (option amount, option price)
    fn place_bid(ref self: TContractState, amount: u256, price: u256) -> Bid;

    fn update_bid(
        ref self: TContractState, bid_id: felt252, new_amount: u256, new_price: u256
    ) -> Bid;

    // Refund unused bids for an option bidder if the auction has ended
    // @param option_bidder: The bidder to refund the unused bid back to
    // @return the amount of the transfer
    fn refund_unused_bids(ref self: TContractState, option_bidder: ContractAddress) -> u256;

    // Claim the payout for an option buyer's options if the option round has settled
    // @note the value that each option pays out might be 0 if non-exercisable
    // @param option_buyer: The option buyer to claim the payout for
    // @return the amount of the transfer
    fn exercise_options(ref self: TContractState) -> u256;

    // Convert options won from auction into erc20 tokens
    fn tokenize_options(ref self: TContractState) -> u256;
}
