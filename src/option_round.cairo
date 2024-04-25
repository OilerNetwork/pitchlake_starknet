use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};
use openzeppelin::token::erc20::interface::IERC20Dispatcher;
use pitch_lake_starknet::market_aggregator::{
    IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait
};

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
struct OptionRoundConstructorParams {
    vault_address: ContractAddress,
    round_id: u256,
}

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
struct OptionRoundParams {
    current_average_basefee: u256, // average basefee the last few months, used to calculate the strike
    standard_deviation: u256, // used to calculate k (-σ or 0 or σ if vault is: ITM | ATM | OTM)
    strike_price: u256, // K = current_average_basefee * (1 + k)
    cap_level: u256, // cl, percentage points of K that the options will pay out at most. Payout = min(cl*K, BF-K). Might not be set until auction settles if we use alternate cap design (see DOCUMENTATION.md)
    collateral_level: u256, // total deposits now locked in the round 
    reserve_price: u256, // minimum price per option in the auction
    total_options_available: u256,
    minimum_collateral_required: u256, // the auction will not start unless this much collateral is deposited, needed ? 
    auction_end_time: u64, // when the auction can be ended
    option_expiry_time: u64, // when the options can be settled  
}

#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
enum OptionRoundState {
    Open,
    Auctioning,
    Running,
    Settled,
    // old
    Initialized, // add between Open and Auctioning (round transition period)
    AuctionStarted,
    AuctionSettled,
    OptionSettled,
}

#[event]
#[derive(Drop, starknet::Event)]
enum Event {
    AuctionStart: AuctionStart,
    AuctionAcceptedBid: AuctionBid,
    AuctionRejectedBid: AuctionBid,
    AuctionSettle: AuctionSettle,
    OptionSettle: OptionSettle,
    WithdrawPremium: OptionTransferEvent,
    WithdrawUnusedDeposit: OptionTransferEvent, // LP collects liquidity if not all options sell, or is this when OB collects unused bid deposit?
    WithdrawPayout: OptionTransferEvent, // OBs collect payouts
    WithdrawCollateral: OptionTransferEvent, // from option round back to vault
}

#[derive(Drop, starknet::Event)]
struct AuctionStart {
    total_options_available: u256 // total_deposits / max_payout
}

#[derive(Drop, starknet::Event)]
struct AuctionBid {
    bidder: ContractAddress,
    amount: u256,
    price: u256
}

#[derive(Drop, starknet::Event)]
struct AuctionSettle {
    clearing_price: u256
}

#[derive(Drop, starknet::Event)]
struct OptionSettle {
    settlement_price: u256
}

#[derive(Drop, starknet::Event)]
struct OptionTransferEvent {
    from: ContractAddress,
    to: ContractAddress,
    amount: u256
}

#[starknet::interface]
trait IOptionRound<TContractState> {
    /// Reads /// 

    // The address of vault that deployed this round
    fn vault_address(self: @TContractState) -> ContractAddress;

    // The state of the option round
    fn get_state(self: @TContractState) -> OptionRoundState;

    // The paramters of the option round
    fn get_params(self: @TContractState) -> OptionRoundParams;

    // The total liquidity at the start of the round's auction
    // @dev This values is fixed and is used for position caluclations
    fn total_liquidity(self: @TContractState) -> u256;

    // The amount of liqudity that is locked for the potential payout
    // @dev Decreases if the auction does not sell all of the options
    fn total_collateral(self: @TContractState) -> u256;

    // The the amount of liquidity that is not allocated for a payout and is withdrawable
    // @dev Pre-auction, this is the total amount deposited into the pending round
    // @dev Post-auction, this is the premiums + unsold liquidity
    // @dev Post-settlement, this is 0 (rolled over to the next round)
    fn total_unallocated_liquidity(self: @TContractState) -> u256;

    // The amount of unallocated liquidity collected from the contract
    // @dev This is the amount of liquidity LPs collect during the option round, and
    // is not rolled over upon settlement
    fn total_unallocated_liquidity_collected(self: @TContractState) -> u256;

    // The total premium collected from the auction
    fn total_premiums(self: @TContractState) -> u256;

    // The total payouts of the option round 
    // @dev OB can collect their share of this total
    fn total_payouts(self: @TContractState) -> u256;

    // The total number of options sold in the option round
    fn total_options_sold(self: @TContractState) -> u256;

    // Gets the clearing price of the auction
    fn get_auction_clearing_price(self: @TContractState) -> u256;

    // Pre-auction, this is the amount an OB locks for bidding,
    // Post-auction, this is the amount not used and is withdrawable by the OB
    fn get_unused_bids_for(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // Gets the amount that an option buyer can claim with their option balance
    fn get_payout_balance_for(self: @TContractState, option_buyer: ContractAddress) -> u256;

    /// Writes ///

    // @dev Anyone can call the 3 below functions using the wrapping entry point in the vault

    // Try to start the option round's auction
    // @return true if the auction was started, false if the auction was already started/cannot start yet
    fn start_auction(ref self: TContractState, option_params: OptionRoundParams);

    // Settle the auction if the auction time has passed 
    // @return if the auction was settled or not
    // @note there was a note in the previous version that this should return the clearing price,
    // not sure which makes more sense at this time.
    fn end_auction(ref self: TContractState) -> u256;

    // Settle the option round if past the expiry date and in state::Running
    // @note This function should probably me limited to a wrapper entry point
    // in the vault that will handle liquidity roll over
    // @return if the option round settles or not 
    fn settle_option_round(ref self: TContractState) -> bool;

    // Place a bid in the auction 
    // @param amount: The max amount in place_bid_token to be used for bidding in the auction
    // @param price: The max price in place_bid_token per option (if the clearing price is 
    // higher than this, the entire bid is unused and can be claimed back by the bidder)
    // @return if the bid was accepted or rejected
    fn place_bid(ref self: TContractState, amount: u256, price: u256) -> bool;

    // Refund unused bids for an option bidder if the auction has ended
    // @param option_bidder: The bidder to refund the unused bid back to
    // @return the amount of the transfer
    fn refund_unused_bids(ref self: TContractState, option_bidder: ContractAddress) -> u256;

    // Claim the payout for an option buyer's options if the option round has settled 
    // @note the value that each option pays out might be 0 if non-exercisable
    // @param option_buyer: The option buyer to claim the payout for
    // @return the amount of the transfer
    fn exercise_options(ref self: TContractState, option_buyer: ContractAddress) -> u256;

    fn get_market_aggregator(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
mod OptionRound {
    use openzeppelin::token::erc20::{ERC20Component};
    use openzeppelin::token::erc20::interface::IERC20;
    use starknet::ContractAddress;
    use pitch_lake_starknet::vault::VaultType;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use super::{OptionRoundConstructorParams, OptionRoundParams, OptionRoundState};
    use pitch_lake_starknet::market_aggregator::{
        IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait
    };

    #[storage]
    struct Storage {
        vault_address: ContractAddress,
        market_aggregator: ContractAddress,
        state: OptionRoundState,
        params: OptionRoundParams,
        constructor_params: OptionRoundConstructorParams,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        market_aggregator: ContractAddress,
        constructor_params: OptionRoundConstructorParams
    ) {
        // Set market aggregator's address 
        self.market_aggregator.write(market_aggregator);

        // Set the vault address 
        self.vault_address.write(constructor_params.vault_address);
        // Set round state to open unless this is round 0
        if (constructor_params.round_id == 0_u256) {
            self.state.write(OptionRoundState::Settled);
        } else {
            self.state.write(OptionRoundState::Open);
        }
    }

    #[abi(embed_v0)]
    impl OptionRoundImpl of super::IOptionRound<ContractState> {
        /// Reads /// 
        fn vault_address(self: @ContractState) -> ContractAddress {
            self.vault_address.read()
        }

        fn get_state(self: @ContractState) -> OptionRoundState {
            self.state.read()
        }

        fn get_params(self: @ContractState) -> OptionRoundParams {
            self.params.read()
        }

        fn total_liquidity(self: @ContractState) -> u256 {
            100
        }

        fn total_unallocated_liquidity(self: @ContractState) -> u256 {
            100
        }

        fn total_unallocated_liquidity_collected(self: @ContractState) -> u256 {
            100
        }

        fn total_collateral(self: @ContractState) -> u256 {
            100
        }

        fn total_premiums(self: @ContractState) -> u256 {
            100
        }

        fn total_payouts(self: @ContractState) -> u256 {
            100
        }

        fn total_options_sold(self: @ContractState) -> u256 {
            100
        }

        fn get_auction_clearing_price(self: @ContractState) -> u256 {
            100
        }

        fn get_unused_bids_for(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }

        fn get_payout_balance_for(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }

        fn get_market_aggregator(self: @ContractState) -> ContractAddress {
            self.market_aggregator.read()
        }

        /// Writes /// 

        fn start_auction(ref self: ContractState, option_params: OptionRoundParams) {}

        fn end_auction(ref self: ContractState) -> u256 {
            self.state.write(OptionRoundState::Running);
            100
        }

        fn settle_option_round(ref self: ContractState) -> bool {
            self.state.write(OptionRoundState::Settled);
            true
        }

        fn place_bid(ref self: ContractState, amount: u256, price: u256) -> bool {
            false
        }

        fn refund_unused_bids(ref self: ContractState, option_bidder: ContractAddress) -> u256 {
            100
        }

        fn exercise_options(ref self: ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }
    }
}

