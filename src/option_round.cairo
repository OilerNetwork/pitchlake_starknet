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

// old (all together)
// unit of account is in wei
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
struct OptionRoundParamsOld {
    current_average_basefee: u256, // wei
    standard_deviation: u256,
    strike_price: u256, // wei
    cap_level: u256, //wei 
    collateral_level: u256,
    reserve_price: u256, //wei
    total_options_available: u256,
    // start_time:u64,
    option_expiry_time: u64, // OptionRound cannot settle before this time
    auction_end_time: u64, // auction cannot settle before this time
    minimum_bid_amount: u256, // to prevent a dos vector
    minimum_collateral_required: u256 // the option round will not start until this much collateral is deposited
}


#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
enum OptionRoundState {
    Open,
    Auctioning,
    Running,
    Settled,
    // old
    Initialized,
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
// total options sold ? 
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
    // new, folling crash course
    /// Reads /// 

    // Get the address of round's deploying vault 
    fn get_vault_address(self: @TContractState) -> ContractAddress;

    // Gets the current state of the option round
    fn get_option_round_state(self: @TContractState) -> OptionRoundState;

    // Gets the parameters for the option round
    fn get_option_round_params(self: @TContractState) -> OptionRoundParams;

    // The total liquidity at the start of the option round
    fn total_deposits(self: @TContractState) -> u256;

    // Gets the total amount deposited by an option buyer. If the auction has not 
    // ended, this represents the total amount locked up for auction. If the auction has 
    // ended, this is the amount not converted into an option and can be claimed back.
    fn get_unused_bid_deposit_balance_of(
        self: @TContractState, option_bidder: ContractAddress
    ) -> u256;

    // Gets the clearing price for the auction
    fn get_auction_clearing_price(self: @TContractState) -> u256;

    // The total number of options sold in the option round
    // @note Will be 0 until the auction is settled
    // @dev Could we just use the ERC20::total_supply() ?
    fn total_options_sold(self: @TContractState) -> u256;

    // Gets the amount of an option buyer's bids that were not used in the auction 
    fn get_unused_bids_of(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // The total premium collected from the option round's auction
    fn total_premiums(self: @TContractState) -> u256;

    // Gets the amount that an option buyer can claim with their options balance
    fn get_payout_balance_of(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // The total payouts of the option round
    // @note Will be 0 until the option round is settled
    // @note Can be 0 depending on the market conditions (exerciseable vs non-exerciseable)
    fn total_payouts(self: @TContractState) -> u256;

    // @dev `option_balance_of` is not needed, it will be included in the ERC20 component as `balance_of`

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
    fn settle_auction(ref self: TContractState) -> u256;

    // Refund unused bids for an option bidder if the auction has ended
    // @param option_bidder: The bidder to refund the unused bid back to
    // @return the amount of the transfer
    fn refund_unused_bids(ref self: TContractState, option_bidder: ContractAddress) -> u256;

    // Settle the option round if past the expiry date and in state::Running
    // @note This function should probably me limited to just the vault, and be wrapped
    // in another entrypoint that will do the claim handling/transfer of funds
    // @return if the option round settles or not 
    fn settle_option_round(ref self: TContractState) -> bool;

    // Claim the payout for an option buyer's options if the option round has settled 
    // @note the value that each option pays out might be 0 if non-exercisable
    // @param option_buyer: The option buyer to claim the payout for
    // @return the amount of the transfer
    fn exercise_options(ref self: TContractState, option_buyer: ContractAddress) -> u256;


    ////////// old (some were moved to above, if name is the same) //////////

    // total amount deposited as part of bidding by an option buyer, if the auction has not ended this represents the total amount locked up for auction and cannot be claimed back,
    // if the auction has ended this the amount which was not converted into an option and can be claimed back.
    fn unused_bid_deposit_balance_of(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // payout due to an option buyer
    fn payout_balance_of(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // no of options bought by a user
    // can drop, erc20::balance_of will suffice
    fn option_balance_of(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // premium balance of liquidity_provider
    // moving this to vault
    fn premium_balance_of(self: @TContractState, liquidity_provider: ContractAddress) -> u256;

    // locked collateral balance of liquidity_provider
    // moved to vault
    fn collateral_balance_of(self: @TContractState, liquidity_provider: ContractAddress) -> u256;

    // total collateral available in the round
    // moved to vault
    fn total_collateral(self: @TContractState) -> u256;

    fn bid_deposit_balance_of(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // market aggregator is a sort of oracle and provides market data(both historic averages and current prices)
    fn get_market_aggregator(self: @TContractState) -> IMarketAggregatorDispatcher;

    // returns true if auction_place_bid if deposit has been locked up in the auction. false if auction not running or auction_place_bid below reserve price
    // amount: max amount in auction_place_bid token to be used for bidding in the auction
    // price: max price in auction_place_bid token(eth) per option. if the auction ends with a price higher than this then the auction_place_bid is not accepted
    fn auction_place_bid(ref self: TContractState, amount: u256, price: u256) -> bool;


    // moves/transfers the unused premium deposit back to the bidder, return value is the amount of the transfer
    // this is per option buyer. every option buyer will have to individually call refund_unused_bid_deposit to transfer any used deposits
    fn refund_unused_bid_deposit(ref self: TContractState, recipient: ContractAddress) -> u256;

    // transfers any payout due to the option buyer, return value is the amount of the transfer
    // this is per option buyer. every option buyer will have to individually call claim_option_payout.
    fn claim_option_payout(ref self: TContractState, for_option_buyer: ContractAddress) -> u256;

    // if the options are past the expiry date then we can move the collateral (after the payout) back to the vault(unallocated pool), returns the collateral moved
    // this is per liquidity provider, every option buyer will have to individually call transfer_collateral_to_vault
    fn transfer_collateral_to_vault(
        ref self: TContractState, for_liquidity_provider: ContractAddress
    ) -> u256;

    // after the auction ends, liquidity_providers can transfer the premiums paid to them back to the vault from where they can be immediately withdrawn.
    // this is per liquidity provider, every liquidity provider will have to individually call transfer_premium_collected_to_vault

    // matt: this is changing: the premium is not immediately available for withdrawal, it is locked until the option is settled ?
    // then the premium + LP is either rolled to next round or sent to the user. If claim submitted before options expire, premiums are returned
    fn transfer_premium_collected_to_vault(
        ref self: TContractState, for_liquidity_provider: ContractAddress
    ) -> u256;
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
        fn get_vault_address(self: @ContractState) -> ContractAddress {
            self.vault_address.read()
        }
        fn get_option_round_state(self: @ContractState) -> OptionRoundState {
            self.state.read()
        }

        fn get_option_round_params(self: @ContractState) -> OptionRoundParams {
            // dummy value
            OptionRoundParams {
                current_average_basefee: 100,
                standard_deviation: 100,
                strike_price: 100,
                cap_level: 100,
                collateral_level: 100,
                reserve_price: 100,
                total_options_available: 100,
                // start_time: 100,
                option_expiry_time: 100,
                auction_end_time: 100,
                minimum_collateral_required: 100,
            }
        }

        fn total_deposits(self: @ContractState) -> u256 {
            100
        }

        fn get_unused_bid_deposit_balance_of(
            self: @ContractState, option_bidder: ContractAddress
        ) -> u256 {
            100
        }

        fn get_auction_clearing_price(self: @ContractState) -> u256 {
            100
        }

        fn total_options_sold(self: @ContractState) -> u256 {
            100
        }

        fn get_unused_bids_of(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }

        fn total_premiums(self: @ContractState) -> u256 {
            100
        }

        fn get_payout_balance_of(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }

        fn total_payouts(self: @ContractState) -> u256 {
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

        fn settle_auction(ref self: ContractState) -> u256 {
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

        fn auction_place_bid(ref self: ContractState, amount: u256, price: u256) -> bool {
            true
        }


        fn refund_unused_bid_deposit(ref self: ContractState, recipient: ContractAddress) -> u256 {
            100
        }

        fn claim_option_payout(ref self: ContractState, for_option_buyer: ContractAddress) -> u256 {
            100
        }

        // rm?
        fn transfer_collateral_to_vault(
            ref self: ContractState, for_liquidity_provider: ContractAddress
        ) -> u256 {
            100
        }

        // rm ?
        fn transfer_premium_collected_to_vault(
            ref self: ContractState, for_liquidity_provider: ContractAddress
        ) -> u256 {
            100
        }

        fn unused_bid_deposit_balance_of(
            self: @ContractState, option_buyer: ContractAddress
        ) -> u256 {
            100
        }


        fn payout_balance_of(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }

        fn option_balance_of(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            100
        }

        fn premium_balance_of(self: @ContractState, liquidity_provider: ContractAddress) -> u256 {
            100
        }

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

