use starknet::ContractAddress;
use core::fmt::{Formatter, Error, Display};


// The parameters needed to construct an option round
// @param vault_address: The address of the vault that deployed this round
// @param round_id: The id of the round (the first round in a vault is round 0)

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
struct OptionRoundConstructorParams {
    vault_address: ContractAddress,
    round_id: u256,
}

// The parameters sent from the vault (fossil) to start the auction
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
struct StartAuctionParams {
    total_options_available: u256,
    starting_liquidity: u256,
    reserve_price: u256,
    cap_level: u256,
    strike_price: u256,
}

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
struct SettleOptionRoundParams {
    settlement_price: u256
}


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


#[derive(Copy, Drop, starknet::Store, PartialEq)]
struct LinkedBids {
    bid: felt252,
    previous: felt252,
    next: felt252
}


// The states an option round can be in
// @note Should we move these into the contract or separate file ?
#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
enum OptionRoundState {
    Open, // Accepting deposits, waiting for auction to start
    Auctioning, // Auction is on going, accepting bids
    Running, // Auction has ended, waiting for option round expiry date to settle
    Settled, // Option round has settled, remaining liquidity has rolled over to the next round
}


#[derive(Copy, Drop, Serde, PartialEq)]
enum OptionRoundError {
    // All state transitions
    CallerIsNotVault,
    // Starting auction
    AuctionAlreadyStarted,
    AuctionStartDateNotReached,
    // Ending auction
    NoAuctionToEnd,
    AuctionEndDateNotReached,
    AuctionNotEnded,
    // Settling round
    OptionRoundAlreadySettled,
    OptionSettlementDateNotReached,
    OptionRoundNotSettled,
    // Placing bids
    BidBelowReservePrice,
    BidAmountZero,
    BiddingWhileNotAuctioning,
    CallerNotBidOwner,
    // Editing bids
    BidCannotBeDecreased,
}


//TRAITS

//Bid Traits
impl BidPartialOrdTrait of PartialOrd<Bid> {
    // @return if lhs < rhs
    fn lt(lhs: Bid, rhs: Bid) -> bool {
        if lhs.price < rhs.price {
            true
        } else if lhs.price > rhs.price {
            false
        } else {
            lhs.nonce > rhs.nonce
        }
    }


    // @return if lhs <= rhs
    fn le(lhs: Bid, rhs: Bid) -> bool {
        (lhs < rhs) || (lhs == rhs)
    }

    // @return if lhs > rhs
    fn gt(lhs: Bid, rhs: Bid) -> bool {
        if lhs.price > rhs.price {
            true
        } else if lhs.price < rhs.price {
            false
        } else {
            lhs.nonce < rhs.nonce
        }
    }

    // @return if lhs >= rhs
    fn ge(lhs: Bid, rhs: Bid) -> bool {
        (lhs > rhs) || (lhs == rhs)
    }
}


impl BidDisplay of Display<Bid> {
    fn fmt(self: @Bid, ref f: Formatter) -> Result<(), Error> {
        let owner: ContractAddress = *self.owner;
        let owner_felt: felt252 = owner.into();
        let str: ByteArray = format!(
            "ID:{}\nNonce:{}\nOwner:{}\nAmount:{}\n Price:{}\nTokenized:{}\nRefunded:{}",
            *self.id,
            *self.nonce,
            owner_felt,
            *self.amount,
            *self.price,
            *self.is_tokenized,
            *self.is_refunded,
        );
        f.buffer.append(@str);
        Result::Ok(())
    }
}

//OptionRoundStateTrait
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


//OptionRoundError Traits

impl OptionRoundErrorIntoFelt252 of Into<OptionRoundError, felt252> {
    fn into(self: OptionRoundError) -> felt252 {
        match self {
            OptionRoundError::CallerIsNotVault => 'OptionRound: Caller not Vault',
            OptionRoundError::AuctionStartDateNotReached => 'OptionRound: Auction start fail',
            OptionRoundError::AuctionAlreadyStarted => 'OptionRound: Auction start fail',
            OptionRoundError::AuctionEndDateNotReached => 'OptionRound: Auction end fail',
            OptionRoundError::AuctionNotEnded => 'Auction has not ended',
            OptionRoundError::NoAuctionToEnd => 'OptionRound: No auction to end',
            OptionRoundError::OptionSettlementDateNotReached => 'OptionRound: Option settle fail',
            OptionRoundError::OptionRoundNotSettled => 'OptionRound:Round not settled',
            OptionRoundError::OptionRoundAlreadySettled => 'OptionRound: Option settle fail',
            OptionRoundError::BidBelowReservePrice => 'OptionRound: Bid below reserve',
            OptionRoundError::BidAmountZero => 'OptionRound: Bid amount zero',
            OptionRoundError::BiddingWhileNotAuctioning => 'OptionRound: No auction running',
            OptionRoundError::BidCannotBeDecreased => 'OptionRound: New bid too low',
            OptionRoundError::CallerNotBidOwner => 'OptionROund: Caller not owner',
        }
    }
}
