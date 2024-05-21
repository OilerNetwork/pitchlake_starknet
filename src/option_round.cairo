use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};
use openzeppelin::token::erc20::interface::IERC20Dispatcher;
use pitch_lake_starknet::market_aggregator::{
    IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait
};

// The parameters needed to construct an option round
// @param vault_address: The address of the vault that deployed this round
// @param round_id: The id of the round (the first round in a vault is round 0)
// @note Move into separate file or within contract
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
struct OptionRoundConstructorParams {
    vault_address: ContractAddress,
    round_id: u256,
}

// The parameters of the option round
// @note Discuss setting some values upon deployment, some when the previous settles, and when this round's auction starts
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
struct OptionRoundParams {
    // @note Discuss if we should set these when previous round settles, or shortly after when this round's auction starts
    current_average_basefee: u256, // average basefee the last few months, used to calculate the strike
    standard_deviation: u256, // used to calculate k (-σ or 0 or σ if vault is: ITM | ATM | OTM)
    strike_price: u256, // K = current_average_basefee * (1 + k)
    cap_level: u256, // cl, percentage points of K that the options will pay out at most. Payout = min(cl*K, BF-K). Might not be set until auction settles if we use alternate cap design (see DOCUMENTATION.md)
    collateral_level: u256, // total deposits now locked in the round
    reserve_price: u256, // minimum price per option in the auction
    total_options_available: u256,
    minimum_collateral_required: u256, // the auction will not start unless this much collateral is deposited, needed ?
    // @dev should we consider setting this upon auction start ?
    // that way if the round's auction start is delayed (due to collateral requirements), we can set a proper auction end time
    // when it eventually starts ?
    auction_end_time: u64, // when an auction can end
    // @dev same as auction end time, wait to set when round acutally starts ?
    option_expiry_time: u64, // when the options can be settled
}

// The states an option round can be in
// @note Should we move these into the contract or separate file ?
#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
enum OptionRoundState {
    Open, // Accepting deposits, waiting for auction to start
    Auctioning, // Auction is on going, accepting bids
    Running, // Auction has ended, waiting for option round expiry date to settle
    Settled, // Option round has settled, remaining liquidity has rolled over to the next round
//Initialized, // add between Open and Auctioning (round transition period) ?
}

// The option round contract interface
// @note Should we move this into a separate file ?
#[starknet::interface]
trait IOptionRound<TContractState> {
    // @note This function is being used for testing (event testers)
    fn rm_me(ref self: TContractState, x: u256);
    /// Reads ///

    // The address of vault that deployed this round
    fn vault_address(self: @TContractState) -> ContractAddress;

    // The state of the option round
    fn get_state(self: @TContractState) -> OptionRoundState;

    // The paramters of the option round
    fn get_params(self: @TContractState) -> OptionRoundParams;

    // The total liquidity at the start of the round's auction
    // @dev Redundant with total_collateral/unallocated?
    fn total_liquidity(self: @TContractState) -> u256;

    // The amount of liqudity that is locked for the potential payout. May shrink
    // if the auction does not sell all options (moving some collateral to unallocated).
    // @dev For now this value is being tested as if it remains a fixed value after the auction.
    // We may need to mark the starting liquidity/collateral using another variable for conversions if we
    // think total collateral should be 0 after the round settles and another variable should be used for starting liquidity
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

    // @note Should migrate back to returning success or not (instead of txn failing). For tests and UX.

    // Try to start the option round's auction
    // @return true if the auction was started, false if the auction was already started/cannot start yet
    fn start_auction(ref self: TContractState, option_params: OptionRoundParams);

    // Settle the auction if the auction time has passed
    // @return if the auction was settled or not (0 mean no, > 0 is clearing price ?, we already have get clearing price, so just bool instead)
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

    fn is_premium_collected(self: @TContractState, lp: ContractAddress) -> bool;
}

#[starknet::contract]
mod OptionRound {
    use openzeppelin::token::erc20::{ERC20Component};
    use openzeppelin::token::erc20::interface::IERC20;
    use starknet::ContractAddress;
    use pitch_lake_starknet::vault::VaultType;
    use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultDispatcherTrait};
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use super::{OptionRoundConstructorParams, OptionRoundParams, OptionRoundState,};
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
        premiums_collected: LegacyMap<ContractAddress, bool>,
    }

    // Option round events
    #[event]
    #[derive(Drop, starknet::Event, PartialEq)]
    enum Event {
        AuctionStart: AuctionStart,
        AuctionAcceptedBid: AuctionBid,
        AuctionRejectedBid: AuctionBid,
        AuctionEnd: AuctionEnd,
        OptionSettle: OptionSettle,
        DepositLiquidity: OptionTransferEvent,
        WithdrawPremium: OptionTransferEvent,
        WithdrawPayout: OptionTransferEvent,
        WithdrawLiquidity: OptionTransferEvent,
        WithdrawUnusedBids: OptionTransferEvent,
    }

    // Emitted when the auction starts
    // @param total_options_available Max number of options that can be sold in the auction
    // @note Discuss if any other params should be emitted
    #[derive(Drop, starknet::Event, PartialEq,)]
    struct AuctionStart {
        total_options_available: u256,
    }

    // Emitted when a bid is accepted or rejected
    // @param bidder The account that placed the bid
    // @param amount The amount of liquidity that was bid (max amount of funds the bidder is willing to spend in total)
    // @param price The price per option that was bid (max price the bidder is willing to spend per option)
    #[derive(Drop, starknet::Event, PartialEq)]
    struct AuctionBid {
        #[key]
        bidder: ContractAddress,
        amount: u256,
        price: u256
    }

    // Emiited when the auction ends
    // @param clearing_price The resulting price per each option of the batch auction
    // @note Discuss if any other params should be emitted (options sold ?)
    #[derive(Drop, starknet::Event, PartialEq)]
    struct AuctionEnd {
        clearing_price: u256
    }

    // Emitted when the option round settles
    // @param settlement_price The TWAP of basefee for the option round period, used to calculate the payout
    // @note Discuss if any other params should be emitted (total payout ?)
    #[derive(Drop, starknet::Event, PartialEq)]
    struct OptionSettle {
        settlement_price: u256
    }

    // Emitted when eth leaves/enters the round
    // @param user The user that depositted/withdrew the liquidity
    // @param amount The amount of liquidity that was depositted/withdrawn
    #[derive(Drop, starknet::Event, PartialEq)]
    struct OptionTransferEvent {
        #[key]
        user: ContractAddress,
        amount: u256
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
        self
            .state
            .write(
                match constructor_params.round_id == 0_u256 {
                    true => OptionRoundState::Settled,
                    false => OptionRoundState::Open,
                }
            );
    }

    #[abi(embed_v0)]
    impl OptionRoundImpl of super::IOptionRound<ContractState> {
        // @note This function is being used for to check event testers are working correctly
        // @note Should be renamed, and moved (look if possible to make a contract emit event from our tests instead of through a dispatcher/call)
        fn rm_me(ref self: ContractState, x: u256) {
            self.emit(Event::AuctionStart(AuctionStart { total_options_available: x }));
            self
                .emit(
                    Event::AuctionAcceptedBid(
                        AuctionBid { bidder: starknet::get_contract_address(), amount: x, price: x }
                    )
                );
            self
                .emit(
                    Event::AuctionRejectedBid(
                        AuctionBid { bidder: starknet::get_contract_address(), amount: x, price: x }
                    )
                );
            self.emit(Event::AuctionEnd(AuctionEnd { clearing_price: x }));
            self.emit(Event::OptionSettle(OptionSettle { settlement_price: x }));
            IVaultDispatcher { contract_address: self.vault_address.read() }.rm_me2();
            self
                .emit(
                    Event::DepositLiquidity(
                        OptionTransferEvent { user: starknet::get_contract_address(), amount: x }
                    )
                );
            self
                .emit(
                    Event::WithdrawPremium(
                        OptionTransferEvent { user: starknet::get_contract_address(), amount: x }
                    )
                );
            self
                .emit(
                    Event::WithdrawPayout(
                        OptionTransferEvent { user: starknet::get_contract_address(), amount: x }
                    )
                );
            self
                .emit(
                    Event::WithdrawLiquidity(
                        OptionTransferEvent { user: starknet::get_contract_address(), amount: x }
                    )
                );
            self
                .emit(
                    Event::WithdrawUnusedBids(
                        OptionTransferEvent { user: starknet::get_contract_address(), amount: x }
                    )
                );
        }

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

        fn is_premium_collected(self: @ContractState, lp: ContractAddress) -> bool {
            self.premiums_collected.read(lp)
        }

        /// Writes ///

        fn start_auction(ref self: ContractState, option_params: OptionRoundParams) {
            self.state.write(OptionRoundState::Auctioning);
        }

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
