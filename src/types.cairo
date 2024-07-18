use starknet::{ContractAddress, Event};
use core::fmt::{Formatter, Error, Display};
use pitch_lake_starknet::option_round::contract::OptionRound;

/// Contract errors
mod Errors {
    /// Vault Errors ///
    const InsufficientBalance: felt252 = 'Insufficient unlocked balance';
    /// OptionRound Errors ///
    const CallerIsNotVault: felt252 = 'Caller not the Vault';
    const AuctionAlreadyStarted: felt252 = 'Auction already started';
    const AuctionStartDateNotReached: felt252 = 'Auction start date not reached';
    const NoAuctionToEnd: felt252 = 'No auction to end';
    const AuctionEndDateNotReached: felt252 = 'Auction end date not reached';
    const AuctionNotEnded: felt252 = 'Auction has not ended yet';
    const OptionRoundAlreadySettled: felt252 = 'Option round already settled';
    const OptionSettlementDateNotReached: felt252 = 'Settlement date not reached';
    const OptionRoundNotSettled: felt252 = 'Option round not settled yet';
    const BidBelowReservePrice: felt252 = 'Bid price below reserve price';
    const BidAmountZero: felt252 = 'Bid amount cannot be 0';
    const BiddingWhileNotAuctioning: felt252 = 'Can only bid while auctioning';
    const CallerNotBidOwner: felt252 = 'Caller is not bid owner';
    const BidCannotBeDecreased: felt252 = 'A bid cannot decrease';
}

/// An enum for each type of Vault
#[derive(starknet::Store, Copy, Drop, Serde, PartialEq)]
enum VaultType {
    InTheMoney,
    AtTheMoney,
    OutOfMoney,
}

// An enum for each state an option round can be in
#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
enum OptionRoundState {
    Open, // Accepting deposits, waiting for auction to start
    Auctioning, // Auction is on going, accepting bids
    Running, // Auction has ended, waiting for option round expiry date to settle
    Settled, // Option round has settled, remaining liquidity has rolled over to the next round
}


/// OptionRound structs

// The parameters needed to construct an option round
// @param vault_address: The address of the vault that deployed this round
// @param round_id: The id of the round (the first round in a vault is round 0)
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
struct OptionRoundConstructorParams {
    vault_address: ContractAddress,
    round_id: u256,
}

// The parameters sent from a Vault to start a round's auction
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
struct StartAuctionParams {
    total_options_available: u256,
    starting_liquidity: u256,
    reserve_price: u256,
    cap_level: u256,
    strike_price: u256,
}

// The parameters sent from a Vault to settle a round
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
struct SettleOptionRoundParams {
    settlement_price: u256
}


// The struct for a bid placed in a round's auction
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq, Display)]
struct Bid {
    id: felt252,
    nonce: u64,
    owner: ContractAddress,
    amount: u256,
    price: u256,
    is_tokenized: bool,
    is_refunded: bool,
}

// Allows Bids to be sorted using >, >=, <, <=
// Bids with higher prices are ranked higher, if prices are equal, bids with a lower nonce are ranked higher
// Meaning if two bids have the same price, the one that was placed first is ranked higher than the later one
impl BidPartialOrdTrait of PartialOrd<Bid> {
    /// <
    fn lt(lhs: Bid, rhs: Bid) -> bool {
        if lhs.price < rhs.price {
            true
        } else if lhs.price > rhs.price {
            false
        } else {
            lhs.nonce > rhs.nonce
        }
    }

    /// >
    fn gt(lhs: Bid, rhs: Bid) -> bool {
        if lhs.price > rhs.price {
            true
        } else if lhs.price < rhs.price {
            false
        } else {
            lhs.nonce < rhs.nonce
        }
    }

    /// <=
    fn le(lhs: Bid, rhs: Bid) -> bool {
        (lhs < rhs) || (lhs == rhs)
    }


    /// >=
    fn ge(lhs: Bid, rhs: Bid) -> bool {
        (lhs > rhs) || (lhs == rhs)
    }
}


// Allows Bids to be printed using println!
impl BidDisplay of Display<Bid> {
    fn fmt(self: @Bid, ref f: Formatter) -> Result<(), Error> {
        let str: ByteArray = format!(
            "ID:{}\nNonce:{}\nOwner:{}\nAmount:{}\n Price:{}\nTokenized:{}\nRefunded:{}",
            *self.id,
            *self.nonce,
            Into::<ContractAddress, felt252>::into(*self.owner),
            *self.amount,
            *self.price,
            *self.is_tokenized,
            *self.is_refunded,
        );
        f.buffer.append(@str);
        Result::Ok(())
    }
}

// Allows OptionRoundStates to be printed using println!
impl OptionRoundStateDisplay of Display<OptionRoundState> {
    fn fmt(self: @OptionRoundState, ref f: Formatter) -> Result<(), Error> {
        let str: ByteArray = match self {
            OptionRoundState::Open => { format!("Open") },
            OptionRoundState::Auctioning => { format!("Auctioning") },
            OptionRoundState::Running => { format!("Running") },
            OptionRoundState::Settled => { format!("Settled") }
        };
        f.buffer.append(@str);
        Result::Ok(())
    }
}
