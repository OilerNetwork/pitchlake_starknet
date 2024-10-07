use starknet::{ContractAddress, Event};
use core::fmt::{Formatter, Error, Display};

/// Errors
pub mod Errors {
    pub const BidsShouldNotHaveSameTreeNonce: felt252 = 'Tree nonces should be unique';
}

pub mod Consts {
    pub const BPS: u256 = 10_000;
    pub const JOB_TIMESTAMP_TOLERANCE: u64 = 1800; // 30 minutes
}


// The struct for a bid placed in a round's auction
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
pub struct Bid {
    bid_id: felt252,
    owner: ContractAddress,
    amount: u256,
    price: u256,
    tree_nonce: u64,
}

// Allows Bids to be sorted using >, >=, <, <=
// Bids with higher prices are ranked higher, if prices are equal, bids with a lower nonce are
// ranked higher Meaning if two bids have the same price, the one that was placed first is ranked
// higher than the later one
pub impl BidPartialOrdTrait of PartialOrd<Bid> {
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
//pub impl BidDisplay of Display<Bid> {
//    fn fmt(self: @Bid, ref f: Formatter) -> Result<(), Error> {
//        let str: ByteArray = format!(
//            "Bid ID:{}\nOwner:{}\nAmount:{}\nPrice:{}\nTree Nonce:{}",
//            *self.bid_id,
//            Into::<ContractAddress, felt252>::into(*self.owner),
//            *self.amount,
//            *self.price,
//            *self.tree_nonce,
//        );
//        f.buffer.append(@str);
//        Result::Ok(())
//    }
//}

// Allows OptionRoundStates to be printed using println!
//pub impl OptionRoundStateDisplay of Display<OptionRoundState> {
//    fn fmt(self: @OptionRoundState, ref f: Formatter) -> Result<(), Error> {
//        let str: ByteArray = match self {
//            OptionRoundState::Open => { format!("Open") },
//            OptionRoundState::Auctioning => { format!("Auctioning") },
//            OptionRoundState::Running => { format!("Running") },
//            OptionRoundState::Settled => { format!("Settled") }
//        };
//        f.buffer.append(@str);
//        Result::Ok(())
//    }
//}


