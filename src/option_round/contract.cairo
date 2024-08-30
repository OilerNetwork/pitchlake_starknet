#[starknet::contract]
mod OptionRound {
    use openzeppelin::token::erc20::{
        ERC20Component, interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait, IERC20Metadata},
    };
    use pitch_lake_starknet::{
        library::{utils::{max, min}, red_black_tree::{RBTreeComponent, RBTreeComponent::Node}},
        option_round::interface::IOptionRound,
        vault::{interface::{IVaultDispatcher, IVaultDispatcherTrait},},
        types::{
            Bid, Errors, OptionRoundConstructorParams, OptionRoundState, VaultType, Consts::BPS,
        },
    };
    use starknet::{get_block_timestamp, get_caller_address, get_contract_address, ContractAddress,};

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

    impl RBTreeImpl = RBTreeComponent::RBTreeImpl<ContractState>;
    impl RBTreeOptionRoundImpl = RBTreeComponent::RBTreeOptionRoundImpl<ContractState>;

    // *************************************************************************
    //                              STORAGE
    // *************************************************************************
    // Note: Write description of any storage variable here->
    // @market_aggregator: The address of the contract to fetch fossil values from
    // @state: The state of the option round
    // @round_id: The round's id
    // @cap_level: The cap level of the potential payout
    // @reserve_price: The minimum bid price per option
    // @strike_price: The strike price of the options
    // @starting_liquidity: The amount of liquidity this round starts with (locked upon auction starting)
    // @payout_per_option: The amount the option round pays out per option upon settlement
    // @auction_start_date: The auction start date
    // @auction_end_date: The auction end date
    // @option_settlement_date: The option settlement date
    // @constructor:params: Params to pass at option round creation, to be set by fossil
    // @bidder_nonces: A mapping of address to u256, tells the current nonce for an address, allows tracking of bids for each user and used to create unique bid id's for each bid
    // @bids_tree: Storage for the bids tree, see rb-tree-component
    // @erc20: Storage for erc20 component of the round.
    #[storage]
    struct Storage {
        vault_address: ContractAddress,
        market_aggregator: ContractAddress,
        state: OptionRoundState,
        round_id: u256,
        cap_level: u128,
        reserve_price: u256,
        strike_price: u256,
        starting_liquidity: u256,
        unsold_liquidity: u256,
        payout_per_option: u256,
        settlement_price: u256,
        auction_start_date: u64,
        auction_end_date: u64,
        option_settlement_date: u64,
        constructor_params: OptionRoundConstructorParams,
        bidder_nonces: LegacyMap<ContractAddress, u32>,
        has_minted: LegacyMap<ContractAddress, bool>,
        has_refunded: LegacyMap<ContractAddress, bool>,
        #[substorage(v0)]
        bids_tree: RBTreeComponent::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    // *************************************************************************
    //                              Constructor
    // *************************************************************************
    #[constructor]
    fn constructor(
        ref self: ContractState,
        vault_address: ContractAddress,
        round_id: u256,
        auction_start_date: u64,
        auction_end_date: u64,
        option_settlement_date: u64,
        reserve_price: u256,
        cap_level: u128,
        strike_price: u256
    ) {
        // Set round state to open
        self.state.write(OptionRoundState::Open);
        // @dev Address of the vault that deploys this round
        self.vault_address.write(vault_address);
        // @dev Index of this round in the vault
        self.round_id.write(round_id);

        // @dev Params of the option round
        self.reserve_price.write(reserve_price);
        self.cap_level.write(cap_level);
        self.strike_price.write(strike_price);
        self.auction_start_date.write(auction_start_date);
        self.auction_end_date.write(auction_end_date);
        self.option_settlement_date.write(option_settlement_date);

        // @dev Name and symbol for the option (erc-20) tokens
        let (name, symbol) = self.generate_erc20_name_and_symbol(round_id);
        self.erc20.initializer(name, symbol);
    }


    // *************************************************************************
    //                              EVENTS
    // *************************************************************************
    #[event]
    #[derive(Drop, starknet::Event, PartialEq)]
    enum Event {
        AuctionStarted: AuctionStarted,
        BidAccepted: BidAccepted,
        BidUpdated: BidUpdated,
        AuctionEnded: AuctionEnded,
        OptionRoundSettled: OptionRoundSettled,
        OptionsExercised: OptionsExercised,
        UnusedBidsRefunded: UnusedBidsRefunded,
        #[flat]
        BidTreeEvent: RBTreeComponent::Event,
        OptionsMinted: OptionsMinted,
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

    // Emitted when the auction ends
    // @param clearing_price The resulting price per each option of the batch auction
    // @note Discuss if any other params should be emitted (options sold ?)
    #[derive(Drop, starknet::Event, PartialEq)]
    struct AuctionEnded {
        clearing_price: u256,
        total_options_sold: u256
    }

    // Emitted when the option round settles
    // @param settlement_price The TWAP of basefee for the option round period, used to calculate the payout
    // @note Discuss if any other params should be emitted (total payout ?)
    #[derive(Drop, starknet::Event, PartialEq)]
    struct OptionRoundSettled {
        total_payout: u256,
        payout_per_option: u256,
        settlement_price: u256
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
    struct OptionsMinted {
        #[key]
        account: ContractAddress,
        amount: u256,
    //...
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

    // *************************************************************************
    //                            IMPLEMENTATION
    // *************************************************************************
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
            0
        }
    }

    #[abi(embed_v0)]
    impl OptionRoundImpl of IOptionRound<ContractState> {
        // ***********************************
        //               READS
        // ***********************************

        fn vault_address(self: @ContractState) -> ContractAddress {
            self.vault_address.read()
        }

        fn get_round_id(self: @ContractState) -> u256 {
            self.round_id.read()
        }

        /// Round params

        fn get_state(self: @ContractState) -> OptionRoundState {
            self.state.read()
        }

        fn get_reserve_price(self: @ContractState) -> u256 {
            self.reserve_price.read()
        }

        fn get_cap_level(self: @ContractState) -> u128 {
            self.cap_level.read()
        }

        fn get_strike_price(self: @ContractState) -> u256 {
            self.strike_price.read()
        }

        fn get_auction_start_date(self: @ContractState) -> u64 {
            self.auction_start_date.read()
        }

        fn get_auction_end_date(self: @ContractState) -> u64 {
            self.auction_end_date.read()
        }

        fn get_option_settlement_date(self: @ContractState) -> u64 {
            self.option_settlement_date.read()
        }

        /// Round liquidity

        fn starting_liquidity(self: @ContractState) -> u256 {
            self.starting_liquidity.read()
        }

        fn unsold_liquidity(self: @ContractState) -> u256 {
            self.unsold_liquidity.read()
        }

        fn total_payout(self: @ContractState) -> u256 {
            self.payout_per_option.read() * self.bids_tree.total_options_sold.read()
        }

        fn settlement_price(self: @ContractState) -> u256 {
            self.settlement_price.read()
        }

        /// Auction

        fn total_options_available(self: @ContractState) -> u256 {
            self.bids_tree._get_total_options_available()
        }

        fn total_options_sold(self: @ContractState) -> u256 {
            self.bids_tree.total_options_sold.read()
        }

        fn clearing_price(self: @ContractState) -> u256 {
            self.bids_tree.clearing_price.read()
        }

        fn total_premiums(self: @ContractState) -> u256 {
            self.bids_tree.clearing_price.read() * self.bids_tree.total_options_sold.read()
        }

        /// Bids

        fn get_bid_details(self: @ContractState, bid_id: felt252) -> Bid {
            let bid: Bid = self.bids_tree._find(bid_id);
            bid
        }

        fn get_bidding_nonce_for(self: @ContractState, option_buyer: ContractAddress) -> u32 {
            self.bidder_nonces.read(option_buyer)
        }

        fn get_bids_for(self: @ContractState, option_buyer: ContractAddress) -> Array<Bid> {
            let nonce: u32 = self.bidder_nonces.read(option_buyer);
            let mut bids: Array<Bid> = array![];
            let mut i = 0;
            while i < nonce {
                let hash = self.create_bid_id(option_buyer, i);
                let bid: Bid = self.bids_tree._find(hash);
                bids.append(bid);
                i += 1;
            };
            bids
        }

        // #Params
        // @option_buyer:ContractAddress, target address
        // #Return
        // u256:total refundable balance for the option buyer
        // #Description
        // This function iterates through the list of bids and returns total refundable amount
        // From the partial bids, takes unsold value (total-sold)*price and adds to refundable_balance
        // From tokenizable bids, takes (clearing_price-bid_price)*amount and adds to refundable_balance
        // From refundable bids, adds the full amount*price to refundable_balance.
        // @note should be named `get_refundable_balance_for(...)`
        // @note Returns sum of refundable balances held by option_buyer if the round's auction has ended
        fn get_refundable_balance_for(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            // @dev Has the bidder refunded already ?
            let has_refunded = self.has_refunded.read(option_buyer);
            if has_refunded {
                return 0;
            }

            let (mut winning_bids, mut losing_bids, clearing_bid_maybe) = self
                .calculate_bid_outcome_for(option_buyer);

            // @dev Add refundable balance from the clearing bid
            let mut refundable_balance = 0;
            match clearing_bid_maybe {
                Option::Some(bid) => {
                    // @dev Only the clearing_bid can be partially sold, the clearing_bid_amount_sold is saved in the tree
                    let options_sold = self.bids_tree.clearing_bid_amount_sold.read();
                    let options_not_sold = bid.amount - options_sold;
                    refundable_balance += options_not_sold * bid.price;
                },
                Option::None => {}
            }

            // @dev Add refundable balances from all losing bids
            let clearing_price = self.clearing_price();
            loop {
                match losing_bids.pop_front() {
                    Option::Some(bid) => { refundable_balance += bid.amount * bid.price; },
                    Option::None => { break (); },
                }
            };

            // @dev Add refundable balance for over paid bids
            loop {
                match winning_bids.pop_front() {
                    Option::Some(bid) => {
                        if (bid.price > clearing_price) {
                            let price_difference = bid.price - clearing_price;
                            refundable_balance += bid.amount * price_difference;
                        }
                    },
                    Option::None => { break (); },
                }
            };

            refundable_balance
        }

        // #Params
        //  @option_buyer: target address
        // #Return
        // u256: total options_balance for the option buyer
        // #Description
        // iterates through the list of bids and returns total tokenizable options
        // From the partial bids, takes the amount that was sold and adds to options_balance,
        // From tokenizable bids, if not tokenized yet, adds to options_balance, updates flag

        /// Returns sum of tokenizable options held by option_buyer
        /// Iterates through the list of bids and returns total tokenizable options
        ///
        /// @note possible gas optimization: a user can only refund or tokenize once, so we don't need to store
        /// this flag on each bid, just per user instead
        ///
        /// # Arguments
        /// * option_buyer: target address
        ///
        /// # Returns
        /// * `u256`: number of tokenizable options held by option_buyer
        // @note should be named `get_mintable_options_for`
        fn get_mintable_options_for(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            // @dev Has the bidder tokenized already ?
            let has_minted = self.has_minted.read(option_buyer);
            if has_minted {
                return 0;
            }

            let (mut winning_bids, _, clearing_bid_maybe) = self
                .calculate_bid_outcome_for(option_buyer);

            // @dev Add mintable balance from the clearing bid
            let mut mintable_balance = 0;
            match clearing_bid_maybe {
                Option::Some(_) => {
                    // @dev The clearing bid potentially sells < the total options bid for, so it is stored separately
                    let options_sold = self.bids_tree.clearing_bid_amount_sold.read();
                    mintable_balance += options_sold;
                },
                Option::None => {}
            }

            // @dev Add mintable balance from all winning bids
            loop {
                match winning_bids.pop_front() {
                    Option::Some(bid) => { mintable_balance += bid.amount; },
                    Option::None => { break (); },
                }
            };

            mintable_balance
        }

        fn get_total_options_balance_for(
            self: @ContractState, option_buyer: ContractAddress
        ) -> u256 {
            self.get_mintable_options_for(option_buyer)
                + self.erc20.ERC20_balances.read(option_buyer)
        }

        // Get the payout balance for the option buyer
        fn get_payout_balance_for(self: @ContractState, option_buyer: ContractAddress) -> u256 {
            let number_of_options = self.get_total_options_balance_for(option_buyer);
            let payout_per_option = self.payout_per_option.read();
            number_of_options * payout_per_option
        }


        // ***********************************
        //               WRITES
        // ***********************************

        /// State transition

        fn update_round_params(
            ref self: ContractState, reserve_price: u256, cap_level: u128, strike_price: u256
        ) {
            self.assert_caller_is_vault();
            self.assert_params_can_update();

            self.reserve_price.write(reserve_price);
            self.cap_level.write(cap_level);
            self.strike_price.write(strike_price);
        }

        // #Params
        // @total_options_available: u256 Number of options to be made available for bidding
        // @starting_liquidity: u256 Liquidity provided to be sold
        // @reserve_price: u256, Reserve price for the auction, this is the minimum price
        // @cap_level: u256, The payout cap for purchased options
        // @strike_price: u256, The settlement amount
        // #Return
        // u256: Total number of options available for auctioning
        // #Description
        // Starts the round's auction
        // Checks that the caller is the Vault, State of the round is Open, and the auction start time has crossed
        // Updates state to auctioning, writes auction parameters to storage, emits AuctionStart event
        // @dev Params are set in the constructor and in this function in case newer values from
        // Fossil are produced in during the round transition period
        fn start_auction(ref self: ContractState, starting_liquidity: u256) -> u256 {
            self.assert_caller_is_vault();
            self.assert_auction_can_start();
            // @dev Calculate total options available
            let strike_price = self.strike_price.read();
            let cap_level = self.cap_level.read();
            let total_options_available = self
                .calculate_total_options_available(starting_liquidity, strike_price, cap_level);

            // @dev Write auction params to storage & update state
            self.starting_liquidity.write(starting_liquidity);
            self.bids_tree.total_options_available.write(total_options_available);
            self.set_state(OptionRoundState::Auctioning);

            // @dev Emit auction start event
            self.emit(Event::AuctionStarted(AuctionStarted { total_options_available }));
            total_options_available
        }


        // fn end_auction
        // #Return
        // u256: Clearing price for the auction, the lowest amount at which options were sold
        // u256: Total options sold, the total number of options sold in the auction
        // #Description
        // End the round's auction
        // Check the caller is vault, state is 'Auctioning' and auction end time has passed
        // Updates state to 'Running', determines clearing price, sends premiums collected back to vault
        // and emits an AuctionEnded event
        fn end_auction(ref self: ContractState) -> (u256, u256) {
            self.assert_caller_is_vault();
            self.assert_auction_can_end();

            // @dev Calculate how many options sell and the price per each option
            let options_available = self.total_options_available();
            let (clearing_price, options_sold) = self.update_clearing_price();

            // @dev Update unsold liquidity if some options do not sell
            if options_sold < options_available {
                let starting_liq = self.starting_liquidity();
                let sold_liq = (starting_liq * options_sold) / options_available;
                let unsold_liq = starting_liq - sold_liq;
                self.unsold_liquidity.write(unsold_liq);
            }

            // @dev Send premiums to Vault
            self.get_eth_dispatcher().transfer(self.vault_address(), self.total_premiums());

            // @dev Update state to Running
            self.set_state(OptionRoundState::Running);

            // @dev Emit auction ended event
            self
                .emit(
                    Event::AuctionEnded(
                        AuctionEnded { clearing_price, total_options_sold: options_sold }
                    )
                );

            (clearing_price, options_sold)
        }

        // fn settle_option_round
        // #Params
        // @settlement_price:u256 The price at which the auction is settled (Use fossil)
        // #Return
        // u256: Total payout for the round that is made available to the options holders
        // #Description
        // Settle the option round
        // Checks caller is vault, state is 'Running' and settlement date is reached
        // Updates state to 'Settled',calculates payout, updates storage and emits 'OptionRoundSettled' event
        // Returns total payout and settlement price
        fn settle_option_round(ref self: ContractState, settlement_price: u256) -> (u256, u256) {
            self.assert_caller_is_vault();
            self.assert_round_can_settle();

            // @dev Calculate payout per option
            let strike_price = self.get_strike_price();
            let cap_level = self.get_cap_level().into();
            let payout_per_option = self
                .calculate_payout_per_option(strike_price, cap_level, settlement_price);

            // @dev Set payout per option and settlement price
            self.payout_per_option.write(payout_per_option);
            self.settlement_price.write(settlement_price);

            // @dev Update state to Settled
            self.set_state(OptionRoundState::Settled);

            // @dev Emit option settled event
            self
                .emit(
                    Event::OptionRoundSettled(
                        OptionRoundSettled {
                            total_payout: self.total_payout(), payout_per_option, settlement_price
                        }
                    )
                );

            let total_payout = self.total_payout();
            (total_payout, settlement_price)
        }

        /// Option bidder functions

        // fn place_bid
        // #params
        // @amount:u256, No. of options to bid for
        // @price:u256, Price per option to bid at
        // #Return
        // Bid: The bid data for the newly placed bid
        // #Description
        // Place a bid in the auction
        // Checks state is 'Auctioning', the auction end date is not reached, the amount is not 0
        // and the price is above reserve price
        // Gets bidder nonce for the caller, and the bids_tree nonce for the new bid, creates a new id: hash(nonce,address) for the bid
        // Inserts new bid into the tree, transfers eth, and emits BidAccepted event
        fn place_bid(ref self: ContractState, amount: u256, price: u256) -> Bid {
            self.assert_bidding_during_an_auction();

            // @dev Assert bid is for more than 0 options
            assert(amount.is_non_zero(), Errors::BidAmountZero);

            // @dev Assert bid price is at or above reserve price
            assert(price >= self.get_reserve_price(), Errors::BidBelowReservePrice);

            // @dev Insert bid into bids tree and update bidder's nonce
            let bidder = get_caller_address();
            let bidders_nonce = self.bidder_nonces.read(bidder);
            let bid = Bid {
                id: self.create_bid_id(bidder, bidders_nonce),
                nonce: self.get_bid_tree_nonce(),
                owner: bidder,
                amount: amount,
                price: price,
            };
            self.bids_tree._insert(bid);
            self.bidder_nonces.write(bidder, bidders_nonce + 1);

            // @dev Transfer bid total from caller to this contract
            let transfer_amount = amount * price;
            self
                .get_eth_dispatcher()
                .transfer_from(bidder, get_contract_address(), transfer_amount);

            // @dev Emit bid accepted event
            self
                .emit(
                    Event::BidAccepted(
                        BidAccepted { nonce: bidders_nonce, account: bidder, amount, price }
                    )
                );

            bid
        }

        // fn update_bid
        // #Params
        // @bid_id:felt252, The id of the bid to be updated
        // @new_amount:u256, new amount for the bid
        // @new_price:u256, new price for the bid
        // #Return
        // Bid: The updated bid data
        // #Description
        // Update a bid in the auction
        // Checks the round state is 'Auctioning', the new bid price and amount is greater than old bid
        // Deletes old bid from the tree, inserts updated bid to the tree with new nonce,
        // transfers difference in eth from bidder to contract and emits BidUpdated event
        // New nonce is necessary to avoid bidders coming in early with low bids and updating them later
        fn update_bid(
            ref self: ContractState, bid_id: felt252, new_amount: u256, new_price: u256
        ) -> Bid {
            self.assert_bidding_during_an_auction();

            // @dev Assert caller owns the bid
            let caller = get_caller_address();
            let old_node: Node = self.bids_tree.tree.read(bid_id);
            let mut old_bid: Bid = old_node.value;
            assert(old_bid.owner == caller, Errors::CallerNotBidOwner);

            // @dev Assert caller is increasing either the price or amount of their bid
            let old_price = old_bid.price;
            let old_amount = old_bid.amount;
            assert(
                new_amount >= old_amount && new_price >= old_price, Errors::BidCannotBeDecreased
            );

            // @dev Update bid
            old_bid.amount = new_amount;
            old_bid.price = new_price;
            // @note Vector is that a caller can jump to back if they increase amount not price
            // - make sure at least one is being increased ?
            old_bid.nonce = self.bids_tree.nonce.read();
            self.bids_tree._delete(bid_id);
            self.bids_tree._insert(old_bid);

            // @dev Charge the difference
            // Calculate the difference in ETH required for the new bid
            let old_total = old_amount * old_price;
            let new_total = new_amount * new_price;
            let difference = new_total - old_total;
            let eth_dispatcher = self.get_eth_dispatcher();
            eth_dispatcher.transfer_from(caller, get_contract_address(), difference);

            // @dev Emit bid updated event
            self
                .emit(
                    Event::BidUpdated(
                        BidUpdated {
                            id: bid_id,
                            account: caller,
                            old_amount: old_amount,
                            old_price: old_price,
                            new_amount: new_amount,
                            new_price: new_price
                        }
                    )
                );

            old_bid
        }

        // fn refund_unused_bids
        // #Params
        // @option_bidder:ContractAddress, target address
        // #Description
        // Refunds unused bids
        // #Return
        // Returns amount in eth refunded to the bidder
        // Check state is not Open or Auctioning
        // Uses internal helper to get list of refundable bids, checks for any partial refundable bids
        // Adds balances from all refundable bids and updates bids.is_refunded to true
        // Transfers total refundable_balance amount to the target address
        fn refund_unused_bids(ref self: ContractState, option_bidder: ContractAddress) -> u256 {
            self.assert_auction_ended();

            // @dev Total refundable balance for the bidder
            let refundable_balance = self.get_refundable_balance_for(option_bidder);

            // @dev Update has_refunded flag
            self.has_refunded.write(option_bidder, true);

            // @dev Transfer the refundable balance to the bidder
            if refundable_balance > 0 {
                self.get_eth_dispatcher().transfer(option_bidder, refundable_balance);
            }

            // @dev Emit bids refunded event
            self
                .emit(
                    Event::UnusedBidsRefunded(
                        UnusedBidsRefunded { account: option_bidder, amount: refundable_balance }
                    )
                );

            refundable_balance
        }

        // fn tokenize_options
        // #Params
        // @option_buyer:ContractAddress, target address
        // #Return
        // u256: Total number of options minted,
        // #Description
        // Mint ERC20 tokens for winning bids
        // Checks that state is 'Ended' or after
        // Gets tokenizable and partial tokenizable bids from internal helper,
        // Sums total number of tokenizable options from both,updates all tokenizable bids.is_tokenized to true,
        // Mints option round tokens to the bidder and emits OptionsTokenized event
        fn mint_options(ref self: ContractState) -> u256 {
            self.assert_auction_ended();

            // @dev Total mintable amount for the bidder
            let option_buyer = get_caller_address();
            let amount = self.get_mintable_options_for(option_buyer);

            // @dev Update has_minted flag
            self.has_minted.write(option_buyer, true);

            // @dev Mint the options to the bidder
            self.mint(option_buyer, amount);

            // @dev Emit options minted event
            self.emit(Event::OptionsMinted(OptionsMinted { account: option_buyer, amount }));

            amount
        }

        // fn exercise_options
        // #Params
        // @option_buyer:ContractAddress, target address
        // #Return
        // u256: Amount of eth sent to the exercising bidder
        // #Description
        // Exercise options
        // Checks round state is 'Settled', sums number of options from all tokenizable_bids(winning bids) and any partial bid
        // Updates all tokenizable and partial bids, bids.is_tokenized to true
        // Checks for any option_round tokens owned by option_buyer, burns the tokens
        // Transfers sum of eth_amount from bids + eth_amount from option round tokens to the bidder,
        // Emits OptionsExercised event
        fn exercise_options(ref self: ContractState) -> u256 {
            self.assert_round_settled();

            // @dev Total number of options to exercise is the caller's mintable balance + thier
            // current option ERC-20 token balance
            let option_buyer = get_caller_address();
            let mut options_to_exercise = 0;
            let mintable_amount = self.get_mintable_options_for(option_buyer);
            let erc20_option_balance = self.erc20.ERC20_balances.read(option_buyer);

            // @dev Burn the ERC20 options
            if erc20_option_balance > 0 {
                options_to_exercise += erc20_option_balance;
                self.burn(option_buyer, erc20_option_balance);
            }

            // @dev Flag the mintable options to no longer be mintable
            options_to_exercise += mintable_amount;
            self.has_minted.write(option_buyer, true);

            // @dev Transfer the payout share to the bidder
            let callers_payout = options_to_exercise * self.payout_per_option.read();
            let eth = self.get_eth_dispatcher();
            eth.transfer(option_buyer, callers_payout);

            // Emit options exercised event
            self
                .emit(
                    Event::OptionsExercised(
                        OptionsExercised {
                            account: option_buyer,
                            num_options: options_to_exercise,
                            amount: callers_payout
                        }
                    )
                );

            callers_payout
        }
    }

    // *************************************************************************
    //                          INTERNAL FUNCTIONS
    // *************************************************************************
    #[generate_trait]
    impl InternalImpl of OptionRoundInternalTrait {
        // Return if the caller is the Vault or not
        fn is_caller_the_vault(self: @ContractState) -> bool {
            get_caller_address() == self.vault_address.read()
        }

        // Assert if the round's params can be updated
        fn assert_params_can_update(ref self: ContractState) {
            let state = self.get_state();
            let now = get_block_timestamp();
            let auction_start_date = self.get_auction_start_date();

            assert(
                state == OptionRoundState::Open && now < auction_start_date,
                Errors::AuctionAlreadyStarted
            );
        }


        // Assert an auction can start
        fn assert_auction_can_start(self: @ContractState) {
            let state = self.get_state();
            let now = get_block_timestamp();
            let auction_start_date = self.get_auction_start_date();
            assert(now >= auction_start_date, Errors::AuctionStartDateNotReached);
            assert(state == OptionRoundState::Open, Errors::AuctionAlreadyStarted);
        }

        // Assert an auction can end
        fn assert_auction_can_end(self: @ContractState) {
            let state = self.get_state();
            let now = get_block_timestamp();
            let auction_end_date = self.get_auction_end_date();
            assert(now >= auction_end_date, Errors::AuctionEndDateNotReached);
            assert(state == OptionRoundState::Auctioning, Errors::AuctionAlreadyEnded);
        }

        // Assert the round can settle
        fn assert_round_can_settle(self: @ContractState) {
            let state = self.get_state();
            let now = get_block_timestamp();
            let settlement_date = self.get_option_settlement_date();
            assert(now >= settlement_date, Errors::OptionSettlementDateNotReached);
            assert(state == OptionRoundState::Running, Errors::OptionRoundNotSettled);
        }

        // Assert a bid is allowed to be placed
        fn assert_bidding_during_an_auction(self: @ContractState) {
            let now = get_block_timestamp();
            let auction_end_date = self.get_auction_end_date();
            let state = self.get_state();
            assert(now < auction_end_date, Errors::BiddingWhileNotAuctioning);
            assert(state == OptionRoundState::Auctioning, Errors::BiddingWhileNotAuctioning);
        }

        // Assert the auction has ended
        fn assert_auction_ended(self: @ContractState) {
            let state = self.get_state();
            assert(
                state == OptionRoundState::Running || state == OptionRoundState::Settled,
                Errors::AuctionNotEnded
            );
        }

        // Assert that the caller is the Vault
        fn assert_caller_is_vault(self: @ContractState) {
            assert(get_caller_address() == self.vault_address(), Errors::CallerIsNotVault);
        }

        // Assert the round has settled
        fn assert_round_settled(self: @ContractState) {
            assert(self.get_state() == OptionRoundState::Settled, Errors::OptionRoundNotSettled);
        }

        // Create the contract's ERC20 name and symbol
        fn generate_erc20_name_and_symbol(
            self: @ContractState, round_id: u256
        ) -> (ByteArray, ByteArray) {
            let name: ByteArray = format!("Pitch Lake Option Round {round_id}");
            let symbol: ByteArray = format!("PLOR{round_id}");
            (name, symbol)
        }

        // Update the state of the round
        fn set_state(ref self: ContractState, state: OptionRoundState) {
            self.state.write(state);
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
            let eth_address = vault.get_eth_address();
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

        // Get bid outcomes
        fn calculate_bid_outcome_for(
            self: @ContractState, bidder: ContractAddress
        ) -> (Array<Bid>, Array<Bid>, Option<Bid>) {
            let mut winning_bids: Array<Bid> = array![];
            let mut losing_bids: Array<Bid> = array![];

            // @dev If the auction has not ended yet, all bids are pending
            let state = self.state.read();
            if (state == OptionRoundState::Open || state == OptionRoundState::Auctioning) {
                return (winning_bids, losing_bids, Option::None(()));
            } // @dev Look at each bid of the bidder's bids compared to the clearing bid
            else {
                let nonce = self.get_bidding_nonce_for(bidder);
                let clearing_bid_id: felt252 = self.bids_tree.clearing_bid.read();
                let clearing_bid: Bid = self.bids_tree._find(clearing_bid_id);
                let mut clearing_bid_option: Option<Bid> = Option::None(());
                let mut i = 0;
                while i < nonce {
                    // @dev Is this bid the clearing bid
                    let bid_id: felt252 = self.create_bid_id(bidder, i);
                    let bid: Bid = self.bids_tree._find(bid_id);
                    if bid_id == clearing_bid_id {
                        clearing_bid_option = Option::Some(bid);
                    } // @dev Is this bid above or below the clearing bid
                    else {
                        if bid > clearing_bid {
                            winning_bids.append(bid);
                        } else {
                            losing_bids.append(bid);
                        }
                    }
                    i += 1;
                };

                (winning_bids, losing_bids, clearing_bid_option)
            }
        }

        // Calculate the maximum payout for a single option
        // @note, can return 0 if strike * cap < 10,000
        fn _max_payout_per_option(
            self: @ContractState, strike_price: u256, cap_level: u128
        ) -> u256 {
            (strike_price * cap_level.into()) / BPS
        }

        fn calculate_payout_per_option(
            self: @ContractState, strike_price: u256, cap_level: u128, settlement_price: u256
        ) -> u256 {
            if (settlement_price <= strike_price) {
                0
            } else {
                let uncapped = settlement_price - strike_price;
                let capped = self._max_payout_per_option(strike_price, cap_level);

                min(capped, uncapped)
            }
        }

        // Calculate the total number of options available to sell in the auction
        fn calculate_total_options_available(
            self: @ContractState, starting_liquidity: u256, strike_price: u256, cap_level: u128
        ) -> u256 {
            let capped = self._max_payout_per_option(strike_price, cap_level);
            match capped == 0 {
                // @dev If the max payout per option is 0, then there are 0 options to sell
                true => 0,
                // @dev Else the number of options available is the starting liquidity divided by the capped amount
                false => starting_liquidity / capped
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
