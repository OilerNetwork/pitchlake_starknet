#[starknet::contract]
mod OptionRound {
    use core::array::ArrayTrait;
    use core::starknet::event::EventEmitter;
    use core::option::OptionTrait;
    use core::fmt::{Display, Formatter, Error};
    use pitch_lake_starknet::contracts::utils::red_black_tree::IRBTree;
    use openzeppelin::token::erc20::{
        ERC20Component, interface::{IERC20Metadata, ERC20ABIDispatcher, ERC20ABIDispatcherTrait,}
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use pitch_lake_starknet::contracts::{
        market_aggregator::{IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait},
        utils::{red_black_tree::{RBTreeComponent, RBTreeComponent::Node}, utils::{min, max}},
        vault::{interface::{IVaultDispatcher, IVaultDispatcherTrait}, types::VaultType},
        option_round::{
            interface::IOptionRound,
            types::{
                Bid, OptionRoundState, OptionRoundConstructorParams, StartAuctionParams,
                SettleOptionRoundParams, OptionRoundError
            }
        }
    };

    // ERC20 Component
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    // Exposes snake_case & CamelCase entry points
    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;
    // Allows the contract access to internal functions
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    // RedBlackTree component
    component!(path: RBTreeComponent, storage: bids_tree, event: BidTreeEvent);
    #[abi(embed_v0)]
    impl RBTreeImpl = RBTreeComponent::RBTree<ContractState>;
    impl RBTreeInternalImpl = RBTreeComponent::InternalImpl<ContractState>;


    // *************************************************************************
    //                              STORAGE
    // *************************************************************************
    // Note: Write description of any storage variable here->
    // @market_aggregator:The address of the contract to fetch fossil values from
    // @state: The state of the option round
    // @round_id: The round's id
    // @cap_level: The cap level of the potential payout
    // @reserve_price: The minimum bid price per option
    // @strike_price: The strike price of the options
    // @starting_liquidity: The amount of liquidity this round starts with (locked upon auction starting)
    // @total_payout: The amount the option round pays out upon settlemnt
    // @auction_start_date: The auction start date
    // @auction_end_date: The auction end date
    // @option_settlement_date: The option settlement date
    // @constructor:params: Params to pass at option round creation, to be set by fossil
    // @bidder_nonces: A mapping of address to u256, tells the current nonce for an address
    // @bids_tree: Storage for the bids tree, see rb-tree-component
    // @erc20: Storage for erc20 component of the round.
    #[storage]
    struct Storage {
        vault_address: ContractAddress,
        market_aggregator: ContractAddress,
        state: OptionRoundState,
        round_id: u256,
        cap_level: u256,
        reserve_price: u256,
        strike_price: u256,
        starting_liquidity: u256,
        total_payout: u256,
        auction_start_date: u64,
        auction_end_date: u64,
        option_settlement_date: u64,
        constructor_params: OptionRoundConstructorParams,
        bidder_nonces: LegacyMap<ContractAddress, u32>,
        #[substorage(v0)]
        bids_tree: RBTreeComponent::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    // The parameters needed to construct an option round
    // @param vault_address: The address of the vault that deployed this round
    // @param round_id: The id of the round (the first round in a vault is round 0)

    //Refactor into a Display impl file, impl display for various types

    // Option round events
    #[event]
    #[derive(Drop, starknet::Event, PartialEq)]
    enum Event {
        AuctionStarted: AuctionStarted,
        BidAccepted: BidAccepted,
        BidRejected: BidRejected,
        BidUpdated: BidUpdated,
        AuctionEnded: AuctionEnded,
        OptionRoundSettled: OptionRoundSettled,
        OptionsExercised: OptionsExercised,
        UnusedBidsRefunded: UnusedBidsRefunded,
        #[flat]
        BidTreeEvent: RBTreeComponent::Event,
        OptionsTokenized: OptionsTokenized,
        #[flat]
        ERC20Event: ERC20Component::Event,
    }
    // Emitted when the auction starts
// @param total_options_available Max number of options that can be sold in the auction
// @note Discuss if any other params should be emitted
#[derive(Drop, starknet::Event, PartialEq)]
struct AuctionStarted {
    total_options_available: u256,
//...
}

// Emitted when a bid is accepted
// @param account The account that placed the bid
// @param amount The amount of options the bidder want in total
// @param price The price per option that was bid (max price the bidder is willing to spend per option)
#[derive(Drop, starknet::Event, PartialEq)]
struct BidAccepted {
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
struct BidRejected {
    #[key]
    account: ContractAddress,
    amount: u256,
    price: u256
}

#[derive(Drop, starknet::Event, PartialEq)]
struct BidUpdated {
    #[key]
    account: ContractAddress,
    id: felt252,
    old_amount: u256,
    old_price: u256,
    new_amount: u256,
    new_price: u256
}

#[derive(Drop, starknet::Event, PartialEq)]
struct OptionsTokenized {
    #[key]
    account: ContractAddress,
    amount: u256,
//...
}

// Emitted when the auction ends
// @param clearing_price The resulting price per each option of the batch auction
// @note Discuss if any other params should be emitted (options sold ?)
#[derive(Drop, starknet::Event, PartialEq)]
struct AuctionEnded {
    clearing_price: u256
}

// Emitted when the option round settles
// @param settlement_price The TWAP of basefee for the option round period, used to calculate the payout
// @note Discuss if any other params should be emitted (total payout ?)
#[derive(Drop, starknet::Event, PartialEq)]
struct OptionRoundSettled {
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
        self.reserve_price.write(reserve_price);
        self.cap_level.write(cap_level);
        self.strike_price.write(strike_price);
    }


    #[abi(embed_v0)]
    impl ERC20MetadataImpl of IERC20Metadata<ContractState> {
        fn name(self: @ContractState) -> ByteArray {
            self.erc20.name()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.erc20.symbol()
        }

        // @note add to constructor
        fn decimals(self: @ContractState) -> u8 {
            6
        }
    }


    

    #[abi(embed_v0)]
    impl OptionRoundImpl of IOptionRound<ContractState> {
        // @note This function is being used for to check event testers are working correctly
        // @note Should be renamed, and moved (look if possible to make a contract emit event from our tests instead of through a dispatcher/call)
        fn rm_me(ref self: ContractState, x: u256) {
            self.emit(Event::AuctionStarted(AuctionStarted { total_options_available: x }));
            self
                .emit(
                    Event::BidAccepted(
                        BidAccepted {
                            nonce: 0, account: starknet::get_contract_address(), amount: x, price: x
                        }
                    )
                );
            self
                .emit(
                    Event::BidRejected(
                        BidRejected {
                            account: starknet::get_contract_address(), amount: x, price: x
                        }
                    )
                );
            self.emit(Event::AuctionEnded(AuctionEnded { clearing_price: x }));
            self.emit(Event::OptionRoundSettled(OptionRoundSettled { settlement_price: x }));
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

        // Get the amount of liquidity that the round started with
        fn starting_liquidity(self: @ContractState) -> u256 {
            self.starting_liquidity.read()
        }

        // Get the total amount of premiums collected from the auction
        fn total_premiums(self: @ContractState) -> u256 {
            self.get_auction_clearing_price() * self.total_options_sold()
        }

        // Get the total payout of the round
        fn total_payout(self: @ContractState) -> u256 {
            self.total_payout.read()
        }

        // Get the clearing price of the auction
        fn get_auction_clearing_price(self: @ContractState) -> u256 {
            self.bids_tree.clearing_price.read()
        }

        // Get the total number of options sold
        fn total_options_sold(self: @ContractState) -> u256 {
            self.bids_tree.total_options_sold.read()
        }

        // Get the details of a bid
        fn get_bid_details(self: @ContractState, bid_id: felt252) -> Bid {
            let node: Node = self.bids_tree.tree.read(bid_id);
            node.value
        }


        // Get the amount of bids the option buyer has placed
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
            while i
                .is_non_zero() {
                    let hash = self.create_bid_id(option_buyer, i);
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

            //Add difference from tokenizable bids only if the state is not open or auctioning

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

        // Get the id of the round
        fn get_round_id(self: @ContractState) -> u256 {
            self.round_id.read()
        }

        /// Other

        // Get the constructor params of the round
        fn get_constructor_params(self: @ContractState) -> OptionRoundConstructorParams {
            self.constructor_params.read()
        }

        // Get the state of the round
        fn get_state(self: @ContractState) -> OptionRoundState {
            self.state.read()
        }

        // Get the address of the vault that deployed this round
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

        // Get the strike price for the round
        fn get_strike_price(self: @ContractState) -> u256 {
            self.strike_price.read()
        }

        // Get the cap level for the round
        fn get_cap_level(self: @ContractState) -> u256 {
            self.cap_level.read()
        }

        // Get the mimium bid price per option
        fn get_reserve_price(self: @ContractState) -> u256 {
            self.reserve_price.read()
        }

        // Get the total options available to sell in the auction
        fn get_total_options_available(self: @ContractState) -> u256 {
            self.bids_tree._get_total_options_available()
        }

        /// Writes ///

        /// State transition

        // Start the round's auction
        // @dev Params are set in the constructor and in this function in case newer values from
        // Fossil are produced in during the round transition period
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

            let StartAuctionParams { total_options_available,
            starting_liquidity,
            reserve_price,
            cap_level,
            strike_price } =
                params;

            // Assert now is >= auction start date
            let now = get_block_timestamp();
            let start_date = self.get_auction_start_date();
            if (now < start_date) {
                return Result::Err(OptionRoundError::AuctionStartDateNotReached);
            }

            // Set starting liquidity & total options available
            self.starting_liquidity.write(starting_liquidity);
            self.bids_tree.total_options_available.write(total_options_available);

            // Set auction params
            self.reserve_price.write(reserve_price);
            self.cap_level.write(cap_level);
            self.strike_price.write(strike_price);

            // Update state to Auctioning
            self.state.write(OptionRoundState::Auctioning);

            // Update auction end date if the auction starts later than expected
            self.auction_end_date.write(self.get_auction_end_date() + now - start_date);

            // Emit auction start event
            self
                .emit(
                    Event::AuctionStarted(
                        AuctionStarted { total_options_available: params.total_options_available }
                    )
                );

            // Return the total options available
            Result::Ok(total_options_available)
        }

        // End the round's auction
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
            let (clearing_price, total_options_sold) = self.update_clearing_price();

            // Send premiums earned from the auction to Vault
            let eth = self.get_eth_dispatcher();
            eth.transfer(self.vault_address(), self.total_premiums());

            // Emit auction ended event
            // @note Should we emit total options sold ?
            self.emit(Event::AuctionEnded(AuctionEnded { clearing_price }));

            // Return clearing price & total options sold
            Result::Ok((clearing_price, total_options_sold))
        }

        // Settle the option round
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
            let total_payout = self.calculate_payout(settlement_price);
            self.total_payout.write(total_payout);

            // Emit option settled event
            self.emit(Event::OptionRoundSettled(OptionRoundSettled { settlement_price }));

            // Return total payout
            Result::Ok(total_payout)
        }

        /// Option bidder functions

        // Place a bid in the auction
        fn place_bid(
            ref self: ContractState, amount: u256, price: u256
        ) -> Result<Bid, OptionRoundError> {
            //Assert round is auctioning
            let bidder = get_caller_address();
            let eth_dispatcher = self.get_eth_dispatcher();
            if (self.get_state() != OptionRoundState::Auctioning
                || self.get_auction_end_date() < get_block_timestamp()) {
                self.emit(Event::BidRejected(BidRejected { account: bidder, amount, price }));
                return Result::Err(OptionRoundError::BiddingWhileNotAuctioning);
            }

            //Assert bid if for more than 0 options
            if (amount.is_zero()) {
                self.emit(Event::BidRejected(BidRejected { account: bidder, amount, price }));
                return Result::Err(OptionRoundError::BidAmountZero);
            }
            //Assert bid price is above reserve price
            if (price < self.get_reserve_price()) {
                self.emit(Event::BidRejected(BidRejected { account: bidder, amount, price }));
                return Result::Err(OptionRoundError::BidBelowReservePrice);
            }

            //Create and store bid, then update bidder nonce
            let nonce = self.bidder_nonces.read(bidder);
            let bid = Bid {
                id: self.create_bid_id(bidder, nonce),
                nonce: self.get_bid_tree_nonce(),
                owner: bidder,
                amount: amount,
                price: price,
                is_tokenized: false,
                is_refunded: false
            };
            self.bids_tree.insert(bid);
            self.bidder_nonces.write(bidder, nonce + 1);

            //Transfer Eth
            eth_dispatcher.transfer_from(bidder, get_contract_address(), amount * price);
            self.emit(Event::BidAccepted(BidAccepted { nonce, account: bidder, amount, price }));
            Result::Ok(bid)
        }

        // Update a bid in the auction
        fn update_bid(
            ref self: ContractState, bid_id: felt252, new_amount: u256, new_price: u256
        ) -> Result<Bid, OptionRoundError> {
            //Assert round is still auctioning
            if (self.get_state() != OptionRoundState::Auctioning) {
                return Result::Err(OptionRoundError::BiddingWhileNotAuctioning);
            }

            //Assert new bid is > old bid
            let old_node: Node = self.bids_tree.tree.read(bid_id);
            let mut old_bid: Bid = old_node.value;
            if (new_amount < old_bid.amount || new_price < old_bid.price) {
                return Result::Err(OptionRoundError::BidCannotBeDecreased);
            }

            //Update bid
            let mut new_bid: Bid = old_bid;
            new_bid.amount = new_amount;
            new_bid.price = new_price;
            self.bids_tree.delete(bid_id);
            self.bids_tree.insert(new_bid);

            //Charge the difference
            let difference = (new_amount * new_price) - (old_bid.amount * old_bid.price);
            let eth_dispatcher = self.get_eth_dispatcher();
            eth_dispatcher.transfer_from(get_caller_address(), get_contract_address(), difference);

            // Emit bid updated event
            self
                .emit(
                    Event::BidUpdated(
                        BidUpdated {
                            id: bid_id,
                            account: get_caller_address(),
                            old_amount: old_bid.amount,
                            old_price: old_bid.price,
                            new_amount: new_bid.amount,
                            new_price: new_bid.price
                        }
                    )
                );

            Result::Ok(new_bid)
        }

        fn refund_unused_bids(
            ref self: ContractState, option_bidder: ContractAddress
        ) -> Result<u256, OptionRoundError> {
            let state = self.get_state();
            if (state == OptionRoundState::Auctioning || state == OptionRoundState::Open) {
                return Result::Err(OptionRoundError::AuctionNotEnded);
            }
            // Get the refundable, tokenizable, and partially sold bid ids
            let (mut tokenizable_bids, mut refundable_bids, partial_bid) = self
                .inspect_options_for(option_bidder);

            // Check and sum bids that are not refunded yet
            let mut refundable_balance = 0;
            let clearing_price = self.get_auction_clearing_price();
            // Add refundable balance from Partial Bid if it's there
            if (partial_bid != 0) {
                let mut partial_node: Node = self.bids_tree.tree.read(partial_bid);

                //Since only clearing_bid can be partially sold, the clearing_bid_amount_sold is saved on the tree
                let options_sold = self.bids_tree.clearing_bid_amount_sold.read();
                if (!partial_node.value.is_refunded) {
                    partial_node.value.is_refunded = true;
                    self.bids_tree.tree.write(partial_bid, partial_node);
                    refundable_balance += (partial_node.value.amount - options_sold)
                        * partial_node.value.price;
                }
            }
            // Add refundable balance from all (not already refunded) refundable bids
            loop {
                match refundable_bids.pop_front() {
                    Option::Some(bid) => {
                        if (!bid.is_refunded) {
                            let mut refundable_node: Node = self.bids_tree.tree.read(bid.id);
                            refundable_node.value.is_refunded = true;
                            self.bids_tree.tree.write(refundable_node.value.id, refundable_node);
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
                            let mut refundable_node: Node = self.bids_tree.tree.read(bid.id);
                            refundable_node.value.is_refunded = true;
                            self.bids_tree.tree.write(refundable_node.value.id, refundable_node);
                            refundable_balance += bid.amount * (bid.price - clearing_price)
                        }
                    },
                    Option::None => { break; }
                }
            };
            let eth_dispatcher = self.get_eth_dispatcher();
            eth_dispatcher.transfer(option_bidder, refundable_balance);

            self
                .emit(
                    Event::UnusedBidsRefunded(
                        UnusedBidsRefunded { account: option_bidder, amount: refundable_balance }
                    )
                );

            Result::Ok(refundable_balance)
        }

        fn exercise_options(
            ref self: ContractState, option_buyer: ContractAddress
        ) -> Result<u256, OptionRoundError> {
            if (self.get_state() != OptionRoundState::Settled) {
                return Result::Err(OptionRoundError::OptionRoundNotSettled);
            }
            let (mut tokenizable_bids, _, partial_bid) = self.inspect_options_for(option_buyer);
            let mut options_to_exercise = 0;
            //Check and sum bids that are not tokenized yet
            //Add options balance from Partial Bid if it's there
            if (partial_bid.is_non_zero()) {
                let mut partial_node: Node = self.bids_tree.tree.read(partial_bid);
                //Since only clearing_bid can be partially sold, the clearing_bid_amount_sold is saved on the tree

                if (!partial_node.value.is_tokenized) {
                    let options_sold = self.bids_tree.clearing_bid_amount_sold.read();
                    options_to_exercise += options_sold;
                    partial_node.value.is_tokenized = true;
                    self.bids_tree.tree.write(partial_bid, partial_node);
                }
            }
            loop {
                match tokenizable_bids.pop_front() {
                    Option::Some(mut bid) => {
                        if (!bid.is_tokenized) {
                            let mut bid_node: Node = self.bids_tree.tree.read(bid.id);
                            bid_node.value.is_tokenized = true;
                            self.bids_tree.tree.write(bid.id, bid_node);
                            options_to_exercise += bid.amount;
                        }
                    },
                    Option::None => { break; }
                }
            };
            let token_balance = self.erc20.ERC20_balances.read(option_buyer);
            self.burn(option_buyer, token_balance);
            options_to_exercise += token_balance;
            let eth_dispatcher = self.get_eth_dispatcher();
            let amount_eth = options_to_exercise
                * self.total_payout()
                / self.get_total_options_sold();
            eth_dispatcher.transfer(option_buyer, amount_eth);
            self
                .emit(
                    Event::OptionsExercised(
                        OptionsExercised {
                            account: option_buyer,
                            num_options: options_to_exercise,
                            amount: amount_eth
                        }
                    )
                );

            Result::Ok(amount_eth)
        }

        fn tokenize_options(
            ref self: ContractState, option_buyer: ContractAddress
        ) -> Result<u256, OptionRoundError> {
            //Check that the round is past auctioning state
            let state = self.get_state();
            if (state == OptionRoundState::Auctioning || state == OptionRoundState::Open) {
                return Result::Err(OptionRoundError::AuctionNotEnded);
            }
            let (mut tokenizable_bids, _, partial_bid) = self.inspect_options_for(option_buyer);
            let mut options_to_mint = 0;
            //Check and sum bids that are not tokenized yet
            //Add options balance from Partial Bid if it's there
            if (partial_bid.is_non_zero()) {
                let mut partial_node: Node = self.bids_tree.tree.read(partial_bid);
                //Since only clearing_bid can be partially sold, the clearing_bid_amount_sold is saved on the tree

                if (!partial_node.value.is_tokenized) {
                    let options_sold = self.bids_tree.clearing_bid_amount_sold.read();
                    options_to_mint += options_sold;
                    partial_node.value.is_tokenized = true;
                    self.bids_tree.tree.write(partial_bid, partial_node);
                }
            }
            loop {
                match tokenizable_bids.pop_front() {
                    Option::Some(mut bid) => {
                        if (!bid.is_tokenized) {
                            let mut bid_node: Node = self.bids_tree.tree.read(bid.id);
                            bid_node.value.is_tokenized = true;
                            self.bids_tree.tree.write(bid.id, bid_node);
                            options_to_mint += bid.amount;
                        }
                    },
                    Option::None => { break; }
                }
            };
            self.mint(option_buyer, options_to_mint);
            self
                .emit(
                    Event::OptionsTokenized(
                        OptionsTokenized { account: option_buyer, amount: options_to_mint }
                    )
                );
            Result::Ok(options_to_mint)
        }
    }


    // Internal Functions
    #[generate_trait]
    impl InternalImpl of OptionRoundInternalTrait {
        // Return if the caller is the Vault or not
        fn is_caller_the_vault(self: @ContractState) -> bool {
            get_caller_address() == self.vault_address.read()
        }

        // Create the contract's ERC20 name and symbol
        fn get_name_symbol(self: @ContractState, round_id: u256) -> (ByteArray, ByteArray) {
            let name: ByteArray = format!("Pitch Lake Option Round {round_id}");
            let symbol: ByteArray = format!("PLOR{round_id}");
            return (name, symbol);
        }

        // Calculate the clearing price and total options sold from the auction
        fn update_clearing_price(ref self: ContractState) -> (u256, u256) {
            self.bids_tree.find_clearing_price()
        }

        //Get bid tree nonce
        fn get_bid_tree_nonce(self: @ContractState) -> u64 {
            self.bids_tree.nonce.read()
        }

        // Get a dispatcher for the ETH contract
        fn get_eth_dispatcher(self: @ContractState) -> ERC20ABIDispatcher {
            let vault = self.get_vault_dispatcher();
            let eth_address = vault.eth_address();
            ERC20ABIDispatcher { contract_address: eth_address }
        }

        // Mint option ERC20 tokens
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.erc20._mint(to, amount);
        }

        // Burn option ERC20 tokens
        fn burn(ref self: ContractState, owner: ContractAddress, amount: u256) {
            self.erc20._burn(owner, amount);
        }

        fn inspect_options_for(
            self: @ContractState, bidder: ContractAddress
        ) -> (Array<Bid>, Array<Bid>, felt252) {
            let mut refundable_bids: Array<Bid> = array![];
            let mut tokenizable_bids: Array<Bid> = array![];
            let mut partial_bid: felt252 = 0;

            //If state is open or auctioning, return defaults

            let state = self.get_state();
            if (state == OptionRoundState::Open || state == OptionRoundState::Auctioning) {
                return (tokenizable_bids, refundable_bids, partial_bid);
            }
            let nonce = self.get_bidding_nonce_for(bidder);
            let mut i = 0;
            while i < nonce {
                let bid_id: felt252 = self.create_bid_id(bidder, i);
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

        fn calculate_payout(ref self: ContractState, settlement_price: u256,) -> u256 {
            let k = self.get_strike_price();
            let cl = self.get_cap_level();
            // @dev This is `min((1 + cl) * k, settlement_price) - k)`
            // without the possibility of a sub overflow error
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

        // Calculate a bid's id
        fn create_bid_id(self: @ContractState, bidder: ContractAddress, nonce: u32) -> felt252 {
            poseidon::poseidon_hash_span(array![bidder.into(), nonce.try_into().unwrap()].span())
        }
    }
}
