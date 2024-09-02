use starknet::{ContractAddress, Event};
use core::fmt::{Formatter, Error, Display};
use pitch_lake_starknet::option_round::contract::OptionRound;

/// Contract errors
mod Errors {
    /// Vault Errors ///
    const InsufficientBalance: felt252 = 'Insufficient unlocked balance';
    const QueueingMoreThanPositionValue: felt252 = 'Insufficient balance to queue';
    const WithdrawalQueuedWhileUnlocked: felt252 = 'Can only queue while locked';
    /// OptionRound Errors ///
    const CallerIsNotVault: felt252 = 'Caller not the Vault';
    // Starting an auction
    const AuctionStartDateNotReached: felt252 = 'Auction start date not reached';
    const AuctionAlreadyStarted: felt252 = 'Auction already started';
    // Ending an auction
    const AuctionEndDateNotReached: felt252 = 'Auction end date not reached';
    const AuctionAlreadyEnded: felt252 = 'Auction has already ended';
    // Settling an option round
    const OptionSettlementDateNotReached: felt252 = 'Settlement date not reached';
    const OptionRoundAlreadySettled: felt252 = 'Option round already settled';
    // Bidding & upating bids
    const BiddingWhileNotAuctioning: felt252 = 'Can only bid while auctioning';
    const BidAmountZero: felt252 = 'Bid amount cannot be 0';
    const BidBelowReservePrice: felt252 = 'Bid price below reserve price';
    const CallerNotBidOwner: felt252 = 'Caller is not bid owner';
    const BidMustBeIncreased: felt252 = 'Bid updates must increase price';
    // Refunding bids & tokenizing options
    const AuctionNotEnded: felt252 = 'Auction has not ended yet';
    const OptionRoundNotSettled: felt252 = 'Option round not settled yet';
    /// Internal Errors ///
    const OptionRoundDeploymentFailed: felt252 = 'Option round deployment failed';
    const BidsShouldNotHaveSameTreeNonce: felt252 = 'Tree nonces should be unique';
}

mod Consts {
    const BPS: u256 = 10_000;
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

//// The parameters sent from a Vault to start a round's auction
//#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
//struct StartAuctionParams {
//    starting_liquidity: u256,
//}

//// The parameters sent from a Vault to settle a round
//#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
//struct SettleOptionRoundParams {
//    settlement_price: u256
//}

// The struct for a bid placed in a round's auction
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq, Display)]
struct Bid {
    bid_id: felt252,
    owner: ContractAddress,
    amount: u256,
    price: u256,
    tree_nonce: u64,
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
            assert(lhs.tree_nonce != rhs.tree_nonce, Errors::BidsShouldNotHaveSameTreeNonce);
            lhs.tree_nonce > rhs.tree_nonce
        }
    }

    /// >
    fn gt(lhs: Bid, rhs: Bid) -> bool {
        if lhs.price > rhs.price {
            true
        } else if lhs.price < rhs.price {
            false
        } else {
            assert(lhs.tree_nonce != rhs.tree_nonce, Errors::BidsShouldNotHaveSameTreeNonce);
            lhs.tree_nonce < rhs.tree_nonce
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
            "Bid ID:{}\nOwner:{}\nAmount:{}\nPrice:{}\nTree Nonce:{}",
            *self.bid_id,
            Into::<ContractAddress, felt252>::into(*self.owner),
            *self.amount,
            *self.price,
            *self.tree_nonce,
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
