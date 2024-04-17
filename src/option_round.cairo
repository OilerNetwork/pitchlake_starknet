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

    // The total liquidity locked at the start of the option round (when the auction starts)
    fn total_deposits(self: @TContractState) -> u256;

    // The total liquidity that that is no longer collateralized if some options do not sell 
    fn total_unallocated_liquidity(self: @TContractState) -> u256;

    // The total premium collected from the option round's auction, 0 before auction end
    fn total_premiums(self: @TContractState) -> u256;

    // The total payouts of the option round, 0 before the option round is settled
    // @note If the options do not become exercisable, it remains 0
    fn total_payouts(self: @TContractState) -> u256;

    // The total amount of premium and unlocked liquidity that was collected by LPs
    fn total_premiums_collected(self: @TContractState) -> u256;

    // The total number of options sold in the option round, will be 0 until
    // the auction ends
    fn total_options_sold(self: @TContractState) -> u256;

    // Gets the clearing price of the auction
    fn get_auction_clearing_price(self: @TContractState) -> u256;

    // Before the auction ends, this is the amount an option buyer locks for bidding,
    // after the auction ends, this is the amount that was not used and is unlocked
    fn get_unused_bids_for(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // Gets how much premium and unlocked liquidity an LP claimed from the round
    fn get_premiums_collected_by(
        self: @TContractState, liquidity_provider: ContractAddress
    ) -> u256;

    // Gets the amount that an option buyer can claim with their option balance
    fn get_payout_balance_for(self: @TContractState, option_buyer: ContractAddress) -> u256;

    /// Writes ///

    // Start the option round's auction (-> state::Auctioning)
    // @return true if the auction was started, false if the auction was already started/cannot start yet
    fn start_auction(ref self: TContractState, option_params: OptionRoundParams) -> bool;

    // Place a bid in the auction 
    // @param amount: The max amount in place_bid_token to be used for bidding in the auction
    // @param price: The max price in place_bid_token per option (if the clearing price is 
    // higher than this, the entire bid is unused and can be claimed back by the bidder)
    // @return if the bid was accepted or rejected
    fn place_bid(ref self: TContractState, amount: u256, price: u256) -> bool;

    // Settle the auction if the auction time has passed 
    // @return if the auction was settled or not
    // @note there was a note in the previous version that this should return the clearing price,
    // not sure which makes more sense at this time.
    fn end_auction(ref self: TContractState) -> u256;

    // Refund unused bids for an option bidder if the auction has ended
    // @param option_bidder: The bidder to refund the unused bid back to
    // @return the amount of the transfer
    fn refund_unused_bids(ref self: TContractState, option_bidder: ContractAddress) -> u256;

    // Settle the option round if past the expiry date and in state::Running
    // @note This function should probably me limited to a wrapper entry point
    // in the vault that will handle liquidity roll over
    // @return if the option round settles or not 
    fn settle_option_round(ref self: TContractState) -> bool;

    // Claim the payout for an option buyer's options if the option round has settled 
    // @note the value that each option pays out might be 0 if non-exercisable
    // @param option_buyer: The option buyer to claim the payout for
    // @return the amount of the transfer
    fn exercise_options(ref self: TContractState, option_buyer: ContractAddress) -> u256;

    ////////// old (some were moved to above, if name is the same) //////////

    // locked collateral balance of liquidity_provider
    // moved to vault
    fn collateral_balance_of(self: @TContractState, liquidity_provider: ContractAddress) -> u256;

    // total collateral available in the round
    // moved to vault
    fn total_collateral(self: @TContractState) -> u256;

    fn bid_deposit_balance_of(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // @dev rm ? can just use address in vault::market_aggregator ? 
    // market aggregator is a sort of oracle and provides market data(both historic averages and current prices)
    fn get_market_aggregator(self: @TContractState) -> IMarketAggregatorDispatcher;
}

#[starknet::contract]
mod OptionRound {
    use openzeppelin::token::erc20::{ERC20Component};
    use openzeppelin::token::erc20::interface::IERC20;
    use starknet::ContractAddress;
    use pitch_lake_starknet::vault::VaultType;
    use pitch_lake_starknet::pool::IPoolDispatcher;
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

    // old
    //#[constructor]
    //fn constructor(
    //    ref self: ContractState,
    //    owner: ContractAddress,
    //    vault_address: ContractAddress,
    //    // collaterized_pool: ContractAddress, // old
    //    option_round_params: OptionRoundParams,
    //    market_aggregator: IMarketAggregatorDispatcher, // should change to just address and build dispatcher when needed ? 
    //) {
    //    self.state.write(OptionRoundState::Open);
    //    self.market_aggregator.write(market_aggregator);
    //}

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

        fn total_deposits(self: @ContractState) -> u256 {
            100
        }

        fn total_unallocated_liquidity(self: @ContractState) -> u256 {
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

        fn total_premiums_collected(self: @ContractState) -> u256 {
            100
        }

        fn get_auction_clearing_price(self: @ContractState) -> u256 {
            100
        }

        fn get_unused_bids_for(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }

        fn get_premiums_collected_by(
            self: @ContractState, liquidity_provider: ContractAddress
        ) -> u256 {
            100
        }

        fn get_payout_balance_for(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }

        /// Writes /// 
        fn start_auction(ref self: ContractState, option_params: OptionRoundParams) -> bool {
            self.state.write(OptionRoundState::Auctioning);
            true
        }

        fn place_bid(ref self: ContractState, amount: u256, price: u256) -> bool {
            false
        }

        fn end_auction(ref self: ContractState) -> u256 {
            self.state.write(OptionRoundState::Running);
            100
        }

        fn refund_unused_bids(ref self: ContractState, option_bidder: ContractAddress) -> u256 {
            100
        }

        fn settle_option_round(ref self: ContractState) -> bool {
            self.state.write(OptionRoundState::Settled);
            true
        }

        fn exercise_options(ref self: ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }


        /// old ///
        fn collateral_balance_of(
            self: @ContractState, liquidity_provider: ContractAddress
        ) -> u256 {
            100
        }

        fn total_collateral(self: @ContractState) -> u256 {
            100
        }

        fn bid_deposit_balance_of(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }

        fn get_market_aggregator(self: @ContractState) -> IMarketAggregatorDispatcher {
            IMarketAggregatorDispatcher { contract_address: self.market_aggregator.read() }
        }
    }
}

