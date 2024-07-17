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

mod Errors {
    // All state transitions
    const CallerIsNotVault: felt252 = 'Caller not the Vault';
    // Starting auction
    const AuctionAlreadyStarted: felt252 = 'Auction already started';
    const AuctionStartDateNotReached: felt252 = 'Auction start date not reached';
    // Ending auction
    const NoAuctionToEnd: felt252 = 'No auction to end';
    const AuctionEndDateNotReached: felt252 = 'Auction end date not reached';
    const AuctionNotEnded: felt252 = 'Auction has not ended yet';
    // Settling round
    const OptionRoundAlreadySettled: felt252 = 'Option round already settled';
    const OptionSettlementDateNotReached: felt252 = 'Settlement date not reached';
    const OptionRoundNotSettled: felt252 = 'Option round not settled yet';
    // Placing/editing bids
    const BidBelowReservePrice: felt252 = 'Bid price below reserve price';
    const BidAmountZero: felt252 = 'Bid amount cannot be 0';
    const BiddingWhileNotAuctioning: felt252 = 'Can only bid while auctioning';
    const CallerNotBidOwner: felt252 = 'Caller is not bid owner';
    const BidCannotBeDecreased: felt252 = 'A bid cannot decrease';
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
