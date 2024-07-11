use starknet::{ContractAddress};
/// This will be where we start implementation and eventually wrap as internal functions in the contracts

// Send erc20 tokens from one account to another
// @note Vault::deposit/withdraw, OptionRound::place_bid/refund_bid/exercise_options all will need this function
fn send_erc20(contract: ContractAddress, from: ContractAddress, to: ContractAddress, value: u256) {}

/// Vault

// Calculate the total value of a liquidity provider's locked and unlocked position
// @note Regardless of LP architecture, there will be some math needed to know an LP's value
// @note Either: calculating from storage positions/checkout, or calcualting from LP token balance(s)
fn calcualte_locked_and_unlocked_balance(liquidity_provider: ContractAddress) {}

/// OptionRound

// Calculate the clearing price of the auction
// Greedy algorithm, first optimizes for quantity of options sold (max is total_options_available),
// then it optimizes for price per option
// @note OptionRound::end_auction will use this function
fn calculate_clearing_price() {}

// Calculate how many options each bidder receives and refundable bids
// @note Unsure yet if all mint/refundable amounts need to be set during this time
// or if they can be calculated by knowing the clearing price during the mint/refund calls
// @note Sorted bids will already be in contract storage but is included now for clarity/if
// we want to work on this algorithm outside of the contract first
struct Bid {
    bidder: ContractAddress,
    max_options: u256,
    max_price: u256
}

fn calculate_option_distribution_and_refundable_bids(
    clearing_price: u256, sorted_bids: Span<Bid>
) {}

// Calcualte the payout of the option round
// @note When the option round settles this function will be called
// @note There is already an implementation of this in the code base, search calculate_expected_payout in tests
fn calculate_options_payout(strike_price: u256, cap_level: u256, twap: u256) {}

