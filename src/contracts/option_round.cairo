use starknet::{ContractAddress, StorePacking};
use openzeppelin::token::erc20::interface::IERC20Dispatcher;
use pitch_lake_starknet::contracts::{
    market_aggregator::{IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait},
    option_round::OptionRound::{OptionRoundState, StartAuctionParams, OptionRoundConstructorParams},
};

// The option round contract interface
#[starknet::interface]
trait IOptionRound<TContractState> {
    // @note This function is being used for testing (event testers)
    fn rm_me(ref self: TContractState, x: u256);
    /// Reads ///

    /// Dates

    // Auction start time
    fn get_auction_start_date(self: @TContractState) -> u64;

    // Auction end time
    fn get_auction_end_date(self: @TContractState) -> u64;

    // Option expiry time
    fn get_option_expiry_date(self: @TContractState) -> u64;


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

    // Get total amount of funds a bidder has locked in the auction
    // @dev During the auction this value is the bidder's total bid amount.
    // @dev After the auction this value is 0. All pending bids are either sent the vault
    // as premiums, or refundable to the bidder.
    fn get_pending_bids_for(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // Get the refundable bid amount for an account
    // @dev During the auction this value is 0 and after
    // the auction is the amount refundable to the bidder
    fn get_refundable_bids_for(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // Gets the amount that an option buyer can exercise with their option balance
    fn get_payout_balance_for(self: @TContractState, option_buyer: ContractAddress) -> u256;

    /// Other

    // The constructor parmaeters of the option round
    fn get_constructor_params(self: @TContractState) -> OptionRoundConstructorParams;

    // The state of the option round
    fn get_state(self: @TContractState) -> OptionRoundState;

    // The address of vault that deployed this round
    fn vault_address(self: @TContractState) -> ContractAddress;

    // @dev Previously OptionRoundParams

    // Average base fee over last few months, used to calculate strike price
    fn get_current_average_basefee(self: @TContractState) -> u256;

    // Standard deviation of base fee over last few months, used to calculate strike price
    fn get_standard_deviation(self: @TContractState) -> u256;

    // The strike price of the options
    fn get_strike_price(self: @TContractState) -> u256;

    // The cap level of the options
    fn get_cap_level(self: @TContractState) -> u256;

    // Minimum price per option in the auction
    fn get_reserve_price(self: @TContractState) -> u256;

    // The total number of options available in the auction
    fn get_total_options_available(self: @TContractState) -> u256;


    /// Writes ///

    /// State transitions

    // Try to start the option round's auction
    // @return the total options available in the auction
    fn start_auction(
        ref self: TContractState, start_auction_params: StartAuctionParams
    ) -> Result<u256, OptionRound::OptionRoundError>;

    // Settle the auction if the auction time has passed
    // @return the clearing price of the auction
    // @return the total options sold in the auction (@note keep or drop ?)
    fn end_auction(ref self: TContractState) -> Result<(u256, u256), OptionRound::OptionRoundError>;

    // Settle the option round if past the expiry date and in state::Running
    // @return The total payout of the option round
    fn settle_option_round(
        ref self: TContractState, avg_base_fee: u256
    ) -> Result<u256, OptionRound::OptionRoundError>;

    /// OB functions

    // Place a bid in the auction
    // @param amount: The max amount of options you want to buy in the auction
    // @param price: The max price in place_bid_token per option 
    // @note: using both the params provided above, we would be able to get the total 
    // amount that needs to be submitted.
    // @return if the bid was accepted or rejected
    fn place_bid(
        ref self: TContractState, amount: u256, price: u256
    ) -> Result<bool, OptionRound::OptionRoundError>;

    // Refund unused bids for an option bidder if the auction has ended
    // @param option_bidder: The bidder to refund the unused bid back to
    // @return the amount of the transfer
    fn refund_unused_bids(
        ref self: TContractState, option_bidder: ContractAddress
    ) -> Result<u256, OptionRound::OptionRoundError>;

    // Claim the payout for an option buyer's options if the option round has settled
    // @note the value that each option pays out might be 0 if non-exercisable
    // @param option_buyer: The option buyer to claim the payout for
    // @return the amount of the transfer
    fn exercise_options(
        ref self: TContractState, option_buyer: ContractAddress
    ) -> Result<u256, OptionRound::OptionRoundError>;
}

#[starknet::contract]
mod OptionRound {
    use openzeppelin::token::erc20::{ERC20Component, interface::{IERC20, IERC20Dispatcher}};
    use starknet::{ContractAddress};
    use pitch_lake_starknet::contracts::vault::{
        Vault::VaultType, IVaultDispatcher, IVaultDispatcherTrait
    };
    use pitch_lake_starknet::contracts::market_aggregator::{
        IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait
    };

    #[storage]
    struct Storage {
        vault_address: ContractAddress,
        market_aggregator: ContractAddress,
        state: OptionRoundState,
        constructor_params: OptionRoundConstructorParams,
    }

    // The parameters needed to construct an option round
    // @param vault_address: The address of the vault that deployed this round
    // @param round_id: The id of the round (the first round in a vault is round 0)
    // @note Move into separate file or within contract
    #[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
    struct OptionRoundConstructorParams {
        vault_address: ContractAddress,
        round_id: u256,
    }

    #[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
    struct StartAuctionParams {}

    // The states an option round can be in
    // @note Should we move these into the contract or separate file ?
    #[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
    enum OptionRoundState {
        Open, // Accepting deposits, waiting for auction to start
        //Initialized, set parameters for auction
        Auctioning, // Auction is on going, accepting bids
        Running, // Auction has ended, waiting for option round expiry date to settle
        Settled, // Option round has settled, remaining liquidity has rolled over to the next round
    }

    // Option round events
    #[event]
    #[derive(Drop, starknet::Event, PartialEq)]
    enum Event {
        AuctionStart: AuctionStart,
        AuctionAcceptedBid: AuctionAcceptedBid,
        AuctionRejectedBid: AuctionRejectedBid,
        AuctionEnd: AuctionEnd,
        OptionSettle: OptionSettle,
        UnusedBidsRefunded: UnusedBidsRefunded,
        OptionsExercised: OptionsExercised,
    }

    // Emitted when the auction starts
    // @param total_options_available Max number of options that can be sold in the auction
    // @note Discuss if any other params should be emitted
    #[derive(Drop, starknet::Event, PartialEq,)]
    struct AuctionStart {
        total_options_available: u256,
    //...
    }

    // Emitted when a bid is accepted
    // @param account The account that placed the bid
    // @param amount The amount of options the bidder want in total
    // @param price The price per option that was bid (max price the bidder is willing to spend per option)
    #[derive(Drop, starknet::Event, PartialEq)]
    struct AuctionAcceptedBid {
        #[key]
        account: ContractAddress,
        amount: u256,
        price: u256
    }

    // Emitted when a bid is rejected
    // @param account The account that placed the bid
    // @param amount The amount of options the bidder is willing to buy in total
    // @param price The price per option that was bid (max price the bidder is willing to spend per option)
    #[derive(Drop, starknet::Event, PartialEq)]
    struct AuctionRejectedBid {
        #[key]
        account: ContractAddress,
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

    #[derive(Copy, Drop, Serde)]
    enum OptionRoundError {
        // Starting auction
        AuctionStartDateNotReached,
        // Ending auction
        AuctionEndDateNotReached,
        // Settling round
        OptionSettlementDateNotReached,
        // Placing bids
        BidBelowReservePrice,
    // @note Add events for when bids are edited
    }

    impl OptionRoundErrorIntoFelt252 of Into<OptionRoundError, felt252> {
        fn into(self: OptionRoundError) -> felt252 {
            match self {
                OptionRoundError::AuctionStartDateNotReached => 'OptionRound: Auction start fail',
                OptionRoundError::AuctionEndDateNotReached => 'OptionRound: Auction end fail',
                OptionRoundError::OptionSettlementDateNotReached => 'OptionRound: Option settle fail',
                OptionRoundError::BidBelowReservePrice => 'OptionRound: Bid below reserve',
            }
        }
    }

    //    impl OptionRoundErrorIntoByteArray of Into<OptionRoundError, ByteArray> {
    //        fn into(self: OptionRoundError) -> ByteArray {
    //            match self {
    //                OptionRoundError::AuctionStartDateNotReached => "OptionRound: Auction start fail",
    //                OptionRoundError::AuctionEndDateNotReached => "OptionRound: Auction end fail",
    //                OptionRoundError::OptionSettlementDateNotReached => "OptionRound: Option settle fail",
    //                OptionRoundError::BidBelowReservePrice => "OptionRound: Bid below reserve",
    //            }
    //        }
    //    }

    #[abi(embed_v0)]
    impl OptionRoundImpl of super::IOptionRound<ContractState> {
        // @note This function is being used for to check event testers are working correctly
        // @note Should be renamed, and moved (look if possible to make a contract emit event from our tests instead of through a dispatcher/call)
        fn rm_me(ref self: ContractState, x: u256) {
            self.emit(Event::AuctionStart(AuctionStart { total_options_available: x }));
            self
                .emit(
                    Event::AuctionAcceptedBid(
                        AuctionAcceptedBid {
                            account: starknet::get_contract_address(), amount: x, price: x
                        }
                    )
                );
            self
                .emit(
                    Event::AuctionRejectedBid(
                        AuctionRejectedBid {
                            account: starknet::get_contract_address(), amount: x, price: x
                        }
                    )
                );
            self.emit(Event::AuctionEnd(AuctionEnd { clearing_price: x }));
            self.emit(Event::OptionSettle(OptionSettle { settlement_price: x }));
            self
                .emit(
                    Event::UnusedBidsRefunded(
                        UnusedBidsRefunded { account: starknet::get_contract_address(), amount: x }
                    )
                );
            self
                .emit(
                    Event::OptionsExercised(
                        OptionsExercised {
                            account: starknet::get_contract_address(), num_options: x, amount: x
                        }
                    )
                );

            IVaultDispatcher { contract_address: self.vault_address.read() }.rm_me2();
        }

        /// Reads ///

        /// Dates

        fn get_auction_start_date(self: @ContractState) -> u64 {
            100
        }

        fn get_auction_end_date(self: @ContractState) -> u64 {
            100
        }

        fn get_option_expiry_date(self: @ContractState) -> u64 {
            100
        }

        /// $

        fn starting_liquidity(self: @ContractState) -> u256 {
            100
        }

        fn total_premiums(self: @ContractState) -> u256 {
            100
        }

        fn total_payout(self: @ContractState) -> u256 {
            100
        }

        fn get_auction_clearing_price(self: @ContractState) -> u256 {
            100
        }

        fn total_options_sold(self: @ContractState) -> u256 {
            100
        }

        fn get_pending_bids_for(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }

        fn get_refundable_bids_for(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }

        fn get_payout_balance_for(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }

        /// Other

        fn get_constructor_params(self: @ContractState) -> OptionRoundConstructorParams {
            self.constructor_params.read()
        }

        fn get_state(self: @ContractState) -> OptionRoundState {
            self.state.read()
        }

        fn vault_address(self: @ContractState) -> ContractAddress {
            self.vault_address.read()
        }

        /// Previously OptionRoundParams

        fn get_current_average_basefee(self: @ContractState) -> u256 {
            100
        }

        fn get_standard_deviation(self: @ContractState) -> u256 {
            100
        }

        fn get_strike_price(self: @ContractState) -> u256 {
            100
        }

        fn get_cap_level(self: @ContractState) -> u256 {
            100
        }

        fn get_reserve_price(self: @ContractState) -> u256 {
            100
        }

        fn get_total_options_available(self: @ContractState) -> u256 {
            100
        }

        /// Writes ///

        /// State transition

        fn start_auction(
            ref self: ContractState, start_auction_params: StartAuctionParams
        ) -> Result<u256, OptionRoundError> {
            self.state.write(OptionRoundState::Auctioning);
            Result::Ok(100)
        }

        fn end_auction(ref self: ContractState) -> Result<(u256, u256), OptionRoundError> {
            self.state.write(OptionRoundState::Running);
            Result::Ok((100, 100))
        }

        fn settle_option_round(
            ref self: ContractState, avg_base_fee: u256
        ) -> Result<u256, OptionRoundError> {
            self.state.write(OptionRoundState::Settled);
            Result::Ok(100)
        }

        /// OB functions

        fn place_bid(
            ref self: ContractState, amount: u256, price: u256
        ) -> Result<bool, OptionRoundError> {
            Result::Ok(true)
        }

        fn refund_unused_bids(
            ref self: ContractState, option_bidder: ContractAddress
        ) -> Result<u256, OptionRoundError> {
            Result::Ok(100)
        }

        fn exercise_options(
            ref self: ContractState, option_buyer: ContractAddress
        ) -> Result<u256, OptionRoundError> {
            Result::Ok(100)
        }
    }
}
