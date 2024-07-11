use starknet::ContractAddress;
// Emitted when the auction starts
// @param total_options_available Max number of options that can be sold in the auction
// @note Discuss if any other params should be emitted
#[derive(Drop, starknet::Event, PartialEq)]
struct AuctionStarted {
    total_options_available: u256,
//...
}

// Emitted when a bid is accepted
// @param account The account that placed the bid
// @param amount The amount of options the bidder want in total
// @param price The price per option that was bid (max price the bidder is willing to spend per option)
#[derive(Drop, starknet::Event, PartialEq)]
struct BidAccepted {
    #[key]
    account: ContractAddress,
    nonce: u32,
    amount: u256,
    price: u256
}

// Emitted when a bid is rejected
// @param account The account that placed the bid
// @param amount The amount of options the bidder is willing to buy in total
// @param price The price per option that was bid (max price the bidder is willing to spend per option)
#[derive(Drop, starknet::Event, PartialEq)]
struct BidRejected {
    #[key]
    account: ContractAddress,
    amount: u256,
    price: u256
}

#[derive(Drop, starknet::Event, PartialEq)]
struct BidUpdated {
    #[key]
    account: ContractAddress,
    id: felt252,
    old_amount: u256,
    old_price: u256,
    new_amount: u256,
    new_price: u256
}

#[derive(Drop, starknet::Event, PartialEq)]
struct OptionsTokenized {
    #[key]
    account: ContractAddress,
    amount: u256,
//...
}

// Emitted when the auction ends
// @param clearing_price The resulting price per each option of the batch auction
// @note Discuss if any other params should be emitted (options sold ?)
#[derive(Drop, starknet::Event, PartialEq)]
struct AuctionEnded {
    clearing_price: u256
}

// Emitted when the option round settles
// @param settlement_price The TWAP of basefee for the option round period, used to calculate the payout
// @note Discuss if any other params should be emitted (total payout ?)
#[derive(Drop, starknet::Event, PartialEq)]
struct OptionRoundSettled {
    settlement_price: u256
}

// Emitted when a bidder refunds their unused bids
// @param account The account that's bids were refuned
// @param amount The amount transferred
#[derive(Drop, starknet::Event, PartialEq)]
struct UnusedBidsRefunded {
    #[key]
    account: ContractAddress,
    amount: u256
}

// Emitted when an option holder exercises their options
// @param account The account: that exercised the options
// @param num_options: The number of options exercised
// @param amount: The amount transferred
#[derive(Drop, starknet::Event, PartialEq)]
struct OptionsExercised {
    #[key]
    account: ContractAddress,
    num_options: u256,
    amount: u256
}
