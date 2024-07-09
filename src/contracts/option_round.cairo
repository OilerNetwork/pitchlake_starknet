use starknet::{ContractAddress, StorePacking};
use openzeppelin::token::erc20::interface::IERC20Dispatcher;
use pitch_lake_starknet::contracts::{
    market_aggregator::{IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait},
    option_round::OptionRound::{
        OptionRoundState, StartAuctionParams, SettleOptionRoundParams, OptionRoundConstructorParams,
        Bid,
    },
};

// The option round contract interface
#[starknet::interface]
trait IOptionRound<TContractState> {
    // @note This function is being used for testing (event testers)
    fn rm_me(ref self: TContractState, x: u256);
    /// Reads ///

    /// Dates

    // The auction start date
    fn get_auction_start_date(self: @TContractState) -> u64;

    // The auction end date
    fn get_auction_end_date(self: @TContractState) -> u64;


    // The option settlement date
    fn get_option_settlement_date(self: @TContractState) -> u64;


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

    // Get the details of a bid
    fn get_bid_details(self: @TContractState, bid_id: felt252) -> Bid;


    /// Address functions

    // Get the bid nonce for an account
    // @note change this to get_bid_nonce_for
    fn get_bidding_nonce_for(self: @TContractState, option_buyer: ContractAddress) -> u32;

    // Get the bid ids for an account
    fn get_bids_for(self: @TContractState, option_buyer: ContractAddress) -> Array<Bid>;

    // Previously this was the amount of eth locked in the auction
    // @note Consider changing this to returning an array of bid ids
    fn get_pending_bids_for(self: @TContractState, option_buyer: ContractAddress) -> Array<felt252>;

    // Get the refundable bid amount for an account
    // @dev During the auction this value is 0 and after
    // the auction is the amount refundable to the bidder
    // @note This should sum all refundable bid amounts and return the total
    // - i.e if a bidder places 4 bids, 2 fully used, 1 partially used, and 1 fully refundable, the
    // refundable amount should be the value of the last bid + the remaining amount of the partial bid
    fn get_refundable_bids_for(self: @TContractState, option_buyer: ContractAddress) -> u256;

    fn get_total_options_balance_for(self: @TContractState, option_buyer: ContractAddress) -> u256;
    // Gets the amount that an option buyer can exercise with their option balance
    fn get_payout_balance_for(self: @TContractState, option_buyer: ContractAddress) -> u256;

    fn get_tokenizable_options_for(self: @TContractState, option_buyer: ContractAddress) -> u256;


    /// Other

    // The address of vault that deployed this round
    fn vault_address(self: @TContractState) -> ContractAddress;

    // The constructor parmaeters of the option round
    fn get_constructor_params(self: @TContractState) -> OptionRoundConstructorParams;

    // The state of the option round
    fn get_state(self: @TContractState) -> OptionRoundState;

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

    // Get option round id
    // @note add to facade and tests
    fn get_round_id(self: @TContractState) -> u256;

    /// Writes ///

    /// State transitions

    // Try to start the option round's auction
    // @return the total options available in the auction
    fn start_auction(
        ref self: TContractState, params: StartAuctionParams
    ) -> Result<u256, OptionRound::OptionRoundError>;

    // Settle the auction if the auction time has passed
    // @return the clearing price of the auction
    // @return the total options sold in the auction (@note keep or drop ?)
    fn end_auction(ref self: TContractState) -> Result<(u256, u256), OptionRound::OptionRoundError>;

    // Settle the option round if past the expiry date and in state::Running
    // @return The total payout of the option round
    fn settle_option_round(
        ref self: TContractState, params: SettleOptionRoundParams
    ) -> Result<u256, OptionRound::OptionRoundError>;

    /// Option bidder functions

    // Place a bid in the auction
    // @param amount: The max amount of options being bid for
    // @param price: The max price per option being bid (if the clearing price is
    // higher than this, the entire bid is unused and can be claimed back by the bidder)
    // @return if the bid was accepted or rejected

    // @note check all tests match new format (option amount, option price)
    fn place_bid(
        ref self: TContractState, amount: u256, price: u256
    ) -> Result<Bid, OptionRound::OptionRoundError>;

    fn update_bid(
        ref self: TContractState, bid_id: felt252, amount: u256, price: u256
    ) -> Result<Bid, OptionRound::OptionRoundError>;

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

    // Convert options won from auction into erc20 tokens
    fn tokenize_options(
        ref self: TContractState, option_buyer: ContractAddress
    ) -> Result<u256, OptionRound::OptionRoundError>;
}

#[starknet::contract]
mod OptionRound {
    use core::array::ArrayTrait;
    use core::starknet::event::EventEmitter;
    use core::option::OptionTrait;
    use core::fmt::{Display, Formatter, Error};
    use pitch_lake_starknet::contracts::utils::red_black_tree::IRBTree;
    use openzeppelin::token::erc20::{
        ERC20Component, interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait,}
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use pitch_lake_starknet::contracts::{
        market_aggregator::{IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait},
        utils::{red_black_tree::{RBTreeComponent, RBTreeComponent::Node}, utils::{min, max}},
        vault::{Vault::VaultType, IVaultDispatcher, IVaultDispatcherTrait},
        option_round::IOptionRound
    };


    component!(path: RBTreeComponent, storage: bids_tree, event: BidTreeEvent);

    #[abi(embed_v0)]
    impl RBTreeImpl = RBTreeComponent::RBTree<ContractState>;

    impl RBTreeInternalImpl = RBTreeComponent::InternalImpl<ContractState>;

    impl BidPartialOrdTrait of PartialOrd<Bid> {
        // @return if lhs < rhs
        fn lt(lhs: Bid, rhs: Bid) -> bool {
            if lhs.price < rhs.price {
                true
            } else if lhs.price > rhs.price {
                false
            } else {
                if lhs.amount < rhs.amount {
                    true
                } else {
                    if lhs.nonce > rhs.nonce {
                        true
                    } else {
                        false
                    }
                }
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
                if lhs.amount > rhs.amount {
                    true
                } else {
                    false
                }
            }
        }

        // @return if lhs >= rhs
        fn ge(lhs: Bid, rhs: Bid) -> bool {
            (lhs > rhs) || (lhs == rhs)
        }
    }


    // ERC20 Component
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    // Exposes snake_case & CamelCase entry points
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    // Allows the contract access to internal functions
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        vault_address: ContractAddress,
        // The address of the contract to fetch fossil values from
        market_aggregator: ContractAddress,
        // The state of the option round
        state: OptionRoundState,
        // The round's id
        round_id: u256,
        // Total number of options available to sell in the auction

        // The cap level of the potential payout
        cap_level: u256,
        // The minimum bid price per option
        reserve_price: u256,
        // The strike price of the options
        strike_price: u256,
        // The amount of liquidity this round starts with (locked upon auction starting)
        starting_liquidity: u256,
        // The amount the option round pays out upon settlemnt
        total_payout: u256,
        // The total number of options sold in the auction
        // The clearing price of the auction (the price each option sells for)
        // The auction start date
        auction_start_date: u64,
        // The auction end date
        auction_end_date: u64,
        // The option settlement date
        option_settlement_date: u64,
        ///////////
        ///////////
        constructor_params: OptionRoundConstructorParams,
        bidder_nonces: LegacyMap<ContractAddress, u32>,
        // bid_details: LegacyMap<felt252, Bid>,
        linked_list: LegacyMap<felt252, LinkedBids>,
        bids_head: felt252,
        bids_tail: felt252,
        #[substorage(v0)]
        bids_tree: RBTreeComponent::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

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

    // The states an option round can be in
    // @note Should we move these into the contract or separate file ?
    #[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
    enum OptionRoundState {
        Open, // Accepting deposits, waiting for auction to start
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
        AuctionUpdatedBid: AuctionUpdatedBid,
        AuctionEnd: AuctionEnd,
        OptionSettle: OptionSettle,
        UnusedBidsRefunded: UnusedBidsRefunded,
        OptionsExercised: OptionsExercised,
        BidTreeEvent: RBTreeComponent::Event,
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    // Emitted when the auction starts
    // @param total_options_available Max number of options that can be sold in the auction
    // @note Discuss if any other params should be emitted
    #[derive(Drop, starknet::Event, PartialEq)]
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
        nonce: u32,
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

    #[derive(Drop, starknet::Event, PartialEq)]
    struct AuctionUpdatedBid {
        #[key]
        account: ContractAddress,
        id: felt252,
        amount: u256,
        price: u256
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

    impl BidDisplay of Display<Bid> {
        fn fmt(self: @Bid, ref f: Formatter) -> Result<(), Error> {
            let owner: ContractAddress = *self.owner;
            let owner_felt: felt252 = owner.into();
            let str: ByteArray = format!(
                "ID:{}\nOwner:{}\nAmount:{}\n Price:{}\nTokenized:{}\nRefunded:{}",
                *self.id,
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

    #[derive(Copy, Drop, starknet::Store, PartialEq)]
    struct LinkedBids {
        bid: felt252,
        previous: felt252,
        next: felt252
    }

    // Emitted when the auction ends
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
        vault_address: ContractAddress,
        round_id: u256,
        auction_start_date: u64,
        auction_end_date: u64,
        option_settlement_date: u64,
        reserve_price: u256,
        cap_level: u256,
        strike_price: u256
    ) {
        let (name, symbol) = self.get_name_symbol(round_id);
        // Initialize the ERC20 component
        self.erc20.initializer(name, symbol);
        // Set the vault address and round id
        self.vault_address.write(vault_address);
        self.round_id.write(round_id);

        // Set dates
        self.auction_start_date.write(auction_start_date);
        self.auction_end_date.write(auction_end_date);
        self.option_settlement_date.write(option_settlement_date);

        // Set round state to open
        self.state.write(OptionRoundState::Open);

        // Write option round params to storage now or once auction starts
        self.cap_level.write(cap_level);
        self.strike_price.write(strike_price);
    }

    #[derive(Copy, Drop, Serde)]
    enum OptionRoundError {
        // All state transitions
        CallerIsNotVault,
        // Starting auction
        AuctionAlreadyStarted,
        AuctionStartDateNotReached,
        // Ending auction
        NoAuctionToEnd,
        AuctionEndDateNotReached,
        // Settling round
        OptionRoundAlreadySettled,
        OptionSettlementDateNotReached,
        // Placing bids
        BidBelowReservePrice,
        BidAmountZero,
        BiddingWhileNotAuctioning,
        // Editing bids
        BidCannotBeDecreased: felt252,
    }

    impl OptionRoundErrorIntoFelt252 of Into<OptionRoundError, felt252> {
        fn into(self: OptionRoundError) -> felt252 {
            match self {
                OptionRoundError::CallerIsNotVault => 'OptionRound: Caller not Vault',
                OptionRoundError::AuctionStartDateNotReached => 'OptionRound: Auction start fail',
                OptionRoundError::AuctionAlreadyStarted => 'OptionRound: Auction start fail',
                OptionRoundError::AuctionEndDateNotReached => 'OptionRound: Auction end fail',
                OptionRoundError::NoAuctionToEnd => 'OptionRound: No auction to end',
                OptionRoundError::OptionSettlementDateNotReached => 'OptionRound: Option settle fail',
                OptionRoundError::OptionRoundAlreadySettled => 'OptionRound: Option settle fail',
                OptionRoundError::BidBelowReservePrice => 'OptionRound: Bid below reserve',
                OptionRoundError::BidAmountZero => 'OptionRound: Bid amount zero',
                OptionRoundError::BiddingWhileNotAuctioning => 'OptionRound: No auction running',
                OptionRoundError::BidCannotBeDecreased(input) => if input == 'amount' {
                    'OptionRound: Bid amount too low'
                } else if input == 'price' {
                    'OptionRound: Bid price too low'
                } else {
                    'OptionRound: Bid too low'
                }
            }
        }
    }

    // @dev Building this struct as a place holder for when we inject the RB tree into the contract

    //    #[derive(Copy, Drop, Serde, PartialEq, PartialOrd)]
    //    struct MockBid {
    //        amount: u256,
    //        price: u256,
    //    }
    //
    //    impl MockBidPartialOrdTrait of PartialOrd<MockBid> {
    //        // @return if lhs < rhs
    //        fn lt(lhs: MockBid, rhs: MockBid) -> bool {
    //            if lhs.price < rhs.price {
    //                true
    //            } else if lhs.price > rhs.price {
    //                false
    //            } else {
    //                if lhs.amount < rhs.amount {
    //                    true
    //                } else {
    //                    false
    //                }
    //            }
    //        }
    //
    //        // @return if lhs <= rhs
    //        fn le(lhs: MockBid, rhs: MockBid) -> bool {
    //            (lhs < rhs) || (lhs == rhs)
    //        }
    //
    //        // @return if lhs > rhs
    //        fn gt(lhs: MockBid, rhs: MockBid) -> bool {
    //            if lhs.price > rhs.price {
    //                true
    //            } else if lhs.price < rhs.price {
    //                false
    //            } else {
    //                if lhs.amount > rhs.amount {
    //                    true
    //                } else {
    //                    false
    //                }
    //            }
    //        }
    //
    //        // @return if lhs >= rhs
    //        fn ge(lhs: MockBid, rhs: MockBid) -> bool {
    //            (lhs > rhs) || (lhs == rhs)
    //        }
    //    }

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
                            nonce: 0, account: starknet::get_contract_address(), amount: x, price: x
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
            self.auction_start_date.read()
        }

        fn get_auction_end_date(self: @ContractState) -> u64 {
            self.auction_end_date.read()
        }

        fn get_option_settlement_date(self: @ContractState) -> u64 {
            self.option_settlement_date.read()
        }


        /// $

        fn starting_liquidity(self: @ContractState) -> u256 {
            self.starting_liquidity.read()
        }

        fn total_premiums(self: @ContractState) -> u256 {
            self.get_auction_clearing_price() * self.total_options_sold()
        }

        fn total_payout(self: @ContractState) -> u256 {
            self.total_payout.read()
        }

        fn get_auction_clearing_price(self: @ContractState) -> u256 {
            self.bids_tree.clearing_price.read()
        }

        fn total_options_sold(self: @ContractState) -> u256 {
            self.bids_tree.total_options_sold.read()
        }

        fn get_bid_details(self: @ContractState, bid_id: felt252) -> Bid {
            let node: Node = self.bids_tree.tree.read(bid_id);
            node.value
        }


        fn get_bidding_nonce_for(self: @ContractState, option_buyer: ContractAddress) -> u32 {
            self.bidder_nonces.read(option_buyer)
        }


        // @note, not needed, can just use get_bids_for, the state of the round will determine if
        // these bids are pending or not
        fn get_pending_bids_for(
            self: @ContractState, option_buyer: ContractAddress
        ) -> Array<felt252> {
            array!['asdf']
        }

        // Get the bid ids for all of the bids the option buyer has placed
        fn get_bids_for(self: @ContractState, option_buyer: ContractAddress) -> Array<Bid> {
            let mut i: u32 = self.bidder_nonces.read(option_buyer);
            let mut bids: Array<Bid> = array![];
            while i >= 0 {
                let hash = poseidon::poseidon_hash_span(
                    array![i.try_into().unwrap(), option_buyer.into()].span()
                );
                let node: Node = self.bids_tree.tree.read(hash);
                bids.append(node.value);
                i -= 1;
            };
            bids
        }

        // Return the total refundable balance for the option buyer
        fn get_refundable_bids_for(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            // Get the refundable, tokenizable, and partially sold bid ids
            let (mut tokenizable_bids, mut refundable_bids, partial_bid) = self
                .inspect_options_for(option_buyer);

            // Check and sum bids that are not refunded yet
            let mut refundable_balance = 0;
            let clearing_price = self.get_auction_clearing_price();
            // Add refundable balance from Partial Bid if it's there
            if (partial_bid != 0) {
                let partial_node: Node = self.bids_tree.tree.read(partial_bid);

                //Since only clearing_bid can be partially sold, the clearing_bid_amount_sold is saved on the tree
                let options_sold = self.bids_tree.clearing_bid_amount_sold.read();
                if (!partial_node.value.is_refunded) {
                    refundable_balance += (partial_node.value.amount - options_sold)
                        * partial_node.value.price;
                }
            }
            // Add refundable balance from all (not already refunded) refundable bids
            loop {
                match refundable_bids.pop_front() {
                    Option::Some(bid) => {
                        if (!bid.is_refunded) {
                            refundable_balance += bid.amount * bid.price;
                        }
                    },
                    Option::None => { break; }
                }
            };
            // Add refundable balance from all (not already refunded) over bids
            // @dev An over bid in this context is when a bid's price is > the clearing price
            loop {
                match tokenizable_bids.pop_front() {
                    Option::Some(bid) => {
                        if (!bid.is_refunded) {
                            refundable_balance += bid.amount * (bid.price - clearing_price)
                        }
                    },
                    Option::None => { break; }
                }
            };

            refundable_balance
        }

        // Get the amount of options that can be tokenized for the option buyer
        fn get_tokenizable_options_for(
            self: @ContractState, option_buyer: ContractAddress
        ) -> u256 {
            //self.bids_tree.find_options_for(option_buyer);
            let (mut tokenizable_bids, _, partial_bid) = self.inspect_options_for(option_buyer);
            let mut options_balance: u256 = 0;
            //Check and sum bids that are not tokenized yet
            //Add options balance from Partial Bid if it's there
            if (partial_bid.is_non_zero()) {
                let partial_node: Node = self.bids_tree.tree.read(partial_bid);

                //Since only clearing_bid can be partially sold, the clearing_bid_amount_sold is saved on the tree
                let options_sold = self.bids_tree.clearing_bid_amount_sold.read();
                if (!partial_node.value.is_tokenized) {
                    options_balance += options_sold;
                }
            }
            loop {
                match tokenizable_bids.pop_front() {
                    Option::Some(bid) => {
                        if (!bid.is_tokenized) {
                            options_balance += bid.amount;
                        }
                    },
                    Option::None => { break; }
                }
            };
            options_balance
        }

        // Get the total amount of options the option buyer owns, includes the tokenizable amount and the
        // already tokenized (ERC20) amount
        fn get_total_options_balance_for(
            self: @ContractState, option_buyer: ContractAddress
        ) -> u256 {
            self.get_tokenizable_options_for(option_buyer)
                + self.erc20.ERC20_balances.read(option_buyer)
        }

        // Get the payout balance for the option buyer
        fn get_payout_balance_for(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            (self.total_payout() * self.get_total_options_balance_for(option_buyer))
                / self.get_total_options_sold()
        }

        // Get the round's id
        fn get_round_id(self: @ContractState) -> u256 {
            self.round_id.read()
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
            self.strike_price.read()
        }

        fn get_cap_level(self: @ContractState) -> u256 {
            self.cap_level.read()
        }

        fn get_reserve_price(self: @ContractState) -> u256 {
            self.reserve_price.read()
        }

        fn get_total_options_available(self: @ContractState) -> u256 {
            self.bids_tree.total_options_available.read()
        }

        /// Writes ///

        /// State transition

        // @note Do we need to set cap level/reserve price/strike price here, or is during deployment fine ? (~1-8 hours earlier)
        fn start_auction(
            ref self: ContractState, params: StartAuctionParams
        ) -> Result<u256, OptionRoundError> {
            // Assert caller is Vault
            if (!self.is_caller_the_vault()) {
                return Result::Err(OptionRoundError::CallerIsNotVault);
            }

            // Assert state is Open
            if (self.get_state() != OptionRoundState::Open) {
                return Result::Err(OptionRoundError::AuctionAlreadyStarted);
            }

            let StartAuctionParams { total_options_available: _,
            starting_liquidity,
            reserve_price: _,
            cap_level,
            strike_price } =
                params;

            // Assert now is >= auction start date
            let now = get_block_timestamp();
            let start_date = self.get_auction_start_date();
            if (now < start_date) {
                return Result::Err(OptionRoundError::AuctionStartDateNotReached);
            }

            // Set auction params
            self.reserve_price.write(1); //HardCoded for tests
            self.cap_level.write(cap_level);
            self.strike_price.write(strike_price);
            // Set starting liquidity & total options available
            self.starting_liquidity.write(starting_liquidity);
            self.bids_tree.total_options_available.write(30); //HardCoded for tests

            // Update state to Auctioning
            self.state.write(OptionRoundState::Auctioning);

            // Update auction end date if the auction starts later than expected
            self.auction_end_date.write(self.get_auction_end_date() + now - start_date);

            // Emit auction start event
            self
                .emit(
                    Event::AuctionStart(
                        AuctionStart { total_options_available: params.total_options_available }
                    )
                );

            // Return the total options available
            Result::Ok(30) //HardCoded for tests
        }

        fn end_auction(ref self: ContractState) -> Result<(u256, u256), OptionRoundError> {
            // Assert caller is Vault
            if (!self.is_caller_the_vault()) {
                return Result::Err(OptionRoundError::CallerIsNotVault);
            }

            // Assert state is Auctioning
            if (self.get_state() != OptionRoundState::Auctioning) {
                return Result::Err(OptionRoundError::NoAuctionToEnd);
            }

            // Assert now is >= auction end date
            let now = get_block_timestamp();
            let end_date = self.get_auction_end_date();
            if (now < end_date) {
                return Result::Err(OptionRoundError::AuctionEndDateNotReached);
            }

            // Update state to Running
            self.state.write(OptionRoundState::Running);

            // Update option settlement date if the auction ends later than expected
            self.option_settlement_date.write(self.get_option_settlement_date() + now - end_date);

            // Calculate clearing price & total options sold
            //  - An empty helper function is fine for now, we will discuss the
            //  implementation of this function later
            let (clearing_price, total_options_sold) = self.update_clearing_price();
            // Set clearing price & total options sold
            // Send premiums earned from the auction to Vault
            let eth = self.get_eth_dispatcher();
            eth.transfer(self.vault_address(), self.total_premiums());

            // Emit auction ended event
            // @note Should we emit total options sold ?
            self.emit(Event::AuctionEnd(AuctionEnd { clearing_price }));

            // Return clearing price & total options sold
            Result::Ok((clearing_price, total_options_sold))
        }

        fn settle_option_round(
            ref self: ContractState, params: SettleOptionRoundParams
        ) -> Result<u256, OptionRoundError> {
            // Assert caller is Vault
            if (!self.is_caller_the_vault()) {
                return Result::Err(OptionRoundError::CallerIsNotVault);
            }

            // Assert now is >= option settlement date
            let now = get_block_timestamp();
            if (now < self.get_option_settlement_date()) {
                return Result::Err(OptionRoundError::OptionSettlementDateNotReached);
            }

            // Assert state is Running
            if (self.get_state() != OptionRoundState::Running) {
                return Result::Err(OptionRoundError::OptionRoundAlreadySettled);
            }

            // Update state to Settled
            self.state.write(OptionRoundState::Settled);

            // Calculate and set total payout
            let SettleOptionRoundParams { settlement_price } = params;
            let total_payout = self.calculate_expected_payout(settlement_price);
            self.total_payout.write(total_payout);

            // Emit option settled event
            self.emit(Event::OptionSettle(OptionSettle { settlement_price }));

            // Return total payout
            Result::Ok(total_payout)
        }

        /// Option bidder functions

        fn place_bid(
            ref self: ContractState, amount: u256, price: u256
        ) -> Result<Bid, OptionRoundError> {
            //Check state of the OptionRound
            let bidder = get_caller_address();
            let eth_dispatcher = self.get_eth_dispatcher();

            if (self.get_state() != OptionRoundState::Auctioning
                || self.get_auction_end_date() < get_block_timestamp()) {
                self
                    .emit(
                        Event::AuctionRejectedBid(
                            AuctionRejectedBid { account: bidder, amount, price }
                        )
                    );
                return Result::Err(OptionRoundError::BiddingWhileNotAuctioning);
            }

            //Bid amount zero
            if (amount == 0) {
                self
                    .emit(
                        Event::AuctionRejectedBid(
                            AuctionRejectedBid { account: bidder, amount, price }
                        )
                    );
                return Result::Err(OptionRoundError::BidAmountZero);
            }
            //Bid below reserve price

            if (price < self.get_reserve_price()) {
                self
                    .emit(
                        Event::AuctionRejectedBid(
                            AuctionRejectedBid { account: bidder, amount, price }
                        )
                    );
                return Result::Err(OptionRoundError::BidBelowReservePrice);
            }

            let nonce = self.bidder_nonces.read(bidder);

            let bid = Bid {
                id: poseidon::poseidon_hash_span(
                    array![bidder.into(), nonce.try_into().unwrap()].span()
                ),
                nonce: self.get_bid_tree_nonce(),
                owner: bidder,
                amount: amount,
                price: price,
                is_tokenized: false,
                is_refunded: false
            };
            self.bids_tree.insert(bid);
            self.bidder_nonces.write(bidder, nonce + 1);

            //Update Clearing Price

            //Transfer Eth
            eth_dispatcher.transfer_from(bidder, get_contract_address(), amount * price);
            self
                .emit(
                    Event::AuctionAcceptedBid(
                        AuctionAcceptedBid { nonce, account: bidder, amount, price }
                    )
                );
            Result::Ok(bid)
        }

        fn update_bid(
            ref self: ContractState, bid_id: felt252, amount: u256, price: u256
        ) -> Result<Bid, OptionRoundError> {
            //Check if state is still auctioning
            if (self.get_state() != OptionRoundState::Auctioning) {
                return Result::Err(OptionRoundError::BiddingWhileNotAuctioning);
            }

            let old_node: Node = self.bids_tree.tree.read(bid_id);
            let mut old_bid: Bid = old_node.value;
            let mut new_bid: Bid = old_bid;
            //Check if amount is decreased
            if (amount < old_bid.amount) {
                if (price < old_bid.price) {
                    return Result::Err(OptionRoundError::BidCannotBeDecreased(''));
                }
                return Result::Err(OptionRoundError::BidCannotBeDecreased('amount'));
            }

            if (price < old_bid.price) {
                return Result::Err(OptionRoundError::BidCannotBeDecreased('price'));
            }
            new_bid.amount = amount;
            new_bid.price = price;
            let difference = new_bid.amount * new_bid.price - old_bid.amount * old_bid.price;

            self.bids_tree.delete(old_bid);

            self.bids_tree.insert(new_bid);

            let eth_dispatcher = self.get_eth_dispatcher();
            eth_dispatcher.transfer_from(get_caller_address(), get_contract_address(), difference);
            self
                .emit(
                    Event::AuctionUpdatedBid(
                        AuctionUpdatedBid {
                            id: bid_id,
                            account: get_caller_address(),
                            amount: new_bid.amount,
                            price: new_bid.price
                        }
                    )
                );
            Result::Ok(new_bid)
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

        fn tokenize_options(
            ref self: ContractState, option_buyer: ContractAddress
        ) -> Result<u256, OptionRoundError> {
            Result::Ok(100)
        }
    }


    // Internal Functions
    #[generate_trait]
    impl InternalImpl of OptionRoundInternalTrait {
        // Return if the caller is the Vault or not
        fn is_caller_the_vault(self: @ContractState) -> bool {
            get_caller_address() == self.vault_address.read()
        }

        fn get_name_symbol(self: @ContractState, round_id: u256) -> (ByteArray, ByteArray) {
            let name: ByteArray = format!("Pitch Lake Option Round {round_id}");
            let symbol: ByteArray = format!("PLOR{round_id}");
            return (name, symbol);
        }

        fn update_clearing_price(ref self: ContractState) -> (u256, u256) {
            self.bids_tree.find_clearing_price()
        }

        // End the auction and calculate the clearing price and total options sold
        fn end_auction_internal(ref self: ContractState) -> (u256, u256) {
            (0, 0)
        }

        //Get bid tree nonce
        fn get_bid_tree_nonce(self: @ContractState) -> u64 {
            self.bids_tree.nonce.read()
        }
        // Get a dispatcher for the ETH contract
        fn get_eth_dispatcher(self: @ContractState) -> IERC20Dispatcher {
            let vault = self.get_vault_dispatcher();
            let eth_address = vault.eth_address();
            IERC20Dispatcher { contract_address: eth_address }
        }

        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.erc20._mint(to, amount);
        }

        fn burn(ref self: ContractState, owner: ContractAddress, amount: u256) {
            self.erc20._burn(owner, amount);
        }

        fn inspect_options_for(
            self: @ContractState, bidder: ContractAddress
        ) -> (Array<Bid>, Array<Bid>, felt252) {
            let mut refundable_bids: Array<Bid> = array![];
            let mut tokenizable_bids: Array<Bid> = array![];
            let mut partial_bid: felt252 = 0;
            let nonce = self.get_bidding_nonce_for(bidder);
            let mut i = 0;
            while i < nonce {
                let bid_id = poseidon::poseidon_hash_span(
                    array![bidder.into(), nonce.into()].span()
                );
                let clearing_bid_id: felt252 = self.bids_tree.clearing_bid.read();
                // If bidder's bid is the clearing bid, it could be partially sold
                if (bid_id == clearing_bid_id) {
                    partial_bid = bid_id;
                } else {
                    let bid_node: Node = self.bids_tree.tree.read(bid_id);
                    let clearing_node: Node = self.bids_tree.tree.read(clearing_bid_id);
                    if (bid_node.value < clearing_node.value) {
                        refundable_bids.append(bid_node.value);
                    } else {
                        tokenizable_bids.append(bid_node.value);
                    }
                }
                i += 1;
            };

            (tokenizable_bids, refundable_bids, partial_bid)
        }
        fn calculate_options(ref self: ContractState, starting_liquidity: u256) -> u256 {
            //Calculate total options accordingly
            0
        }

        fn calculate_expected_payout(ref self: ContractState, settlement_price: u256,) -> u256 {
            let k = self.get_strike_price();
            let cl = self.get_cap_level();
            //max(0, min((1 + cl) * k, settlement_price) - k)
            // @dev This removes sub overflow possibility
            let min = min((1 + cl) * k, settlement_price);
            if min > k {
                min - k
            } else {
                0
            }
        }

        // Get a dispatcher for the Vault
        fn get_vault_dispatcher(self: @ContractState) -> IVaultDispatcher {
            IVaultDispatcher { contract_address: self.vault_address.read() }
        }
    }
}
