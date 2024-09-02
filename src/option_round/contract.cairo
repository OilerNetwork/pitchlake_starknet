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
            Bid, Errors, OptionRoundConstructorParams, OptionRoundState, VaultType,
            Consts::BPS,
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
        ///
        vault_address: ContractAddress,
        state: OptionRoundState,
        round_id: u256,
        ///
        cap_level: u128,
        reserve_price: u256,
        strike_price: u256,
        ///
        starting_liquidity: u256,
        unsold_liquidity: u256,
        settlement_price: u256,
        payout_per_option: u256,
        ///
        auction_start_date: u64,
        auction_end_date: u64,
        option_settlement_date: u64,
        ///
        account_nonce: LegacyMap<ContractAddress, u64>,
        has_minted: LegacyMap<ContractAddress, bool>,
        has_refunded: LegacyMap<ContractAddress, bool>,
        ///
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
        // @dev Set round state to open
        self.state.write(OptionRoundState::Open);
        // @dev Set address of the vault that deployed this round
        self.vault_address.write(vault_address);
        // @dev Set the id for this round
        self.round_id.write(round_id);
        // @dev Set params of the round
        self.reserve_price.write(reserve_price);
        self.cap_level.write(cap_level);
        self.strike_price.write(strike_price);
        self.auction_start_date.write(auction_start_date);
        self.auction_end_date.write(auction_end_date);
        self.option_settlement_date.write(option_settlement_date);
        // @dev Set the name and symbol for the minted option (ERC-20) tokens
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
        BidPlaced: BidPlaced,
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

    // @dev Emitted when the auction starts
    // @member starting_liquidity: The liquidity locked at the start of the auction
    // @member options_available: The max number of options to sell in the auction
    #[derive(Drop, starknet::Event, PartialEq)]
    struct AuctionStarted {
        starting_liquidity: u256,
        options_available: u256,
    }

    // @dev Emitted when the auction ends
    // @member clearing_price: The calculated price per option after the auction
    // @member options_sold: The number of options that sold in the auction
    // @memeber unsold_liquidity: The amount of liquidity that was not sold in the auction
    #[derive(Drop, starknet::Event, PartialEq)]
    struct AuctionEnded {
        options_sold: u256,
        clearing_price: u256,
        unsold_liquidity: u256,
    }

    // @dev Emitted when the round settles
    // @member payout_per_option: The exercisable amount for 1 option
    // @member settlement_price: The basefee TWAP used to settle the round
    #[derive(Drop, starknet::Event, PartialEq)]
    struct OptionRoundSettled {
        settlement_price: u256,
        payout_per_option: u256,
    }

    // @dev Emitted when a bid is placed
    // @memeber account: The account that placed the bid
    // @member bid_id: The bid's identifier
    // @memeber amount: The max amount of options the account is bidding for
    // @member price: The max price per option the account is bidding for
    // @member account_bid_nonce_now: The amount of bids the account has placed now
    // @member tree_bid_nonce_now: The bid tree's nonce now
    #[derive(Drop, starknet::Event, PartialEq)]
    struct BidPlaced {
        #[key]
        account: ContractAddress,
        bid_id: felt252,
        amount: u256,
        price: u256,
        bid_tree_nonce_now: u64,
    }

    // @dev Emitted when a bid is updated
    // @member account: The account that updated the bid
    // @member bid_id: The bid's identifier
    // @member price_increase: The bid's price increase amount
    // @member tree_bid_nonce_now: The nonce of the bid tree now
    #[derive(Drop, starknet::Event, PartialEq)]
    struct BidUpdated {
        #[key]
        account: ContractAddress,
        bid_id: felt252,
        price_increase: u256,
        bid_tree_nonce_now: u64,
    }

    // @dev Emitted when an account mints option ERC-20 tokens
    // @member account: The account that minted the options
    // @member minted_amount: The amount of options minted
    #[derive(Drop, starknet::Event, PartialEq)]
    struct OptionsMinted {
        #[key]
        account: ContractAddress,
        minted_amount: u256,
    }

    // @dev Emitted when an accounts unused bids are refunded
    // @param account: The account that's bids were refuned
    // @param refunded_amount: The amount refunded
    #[derive(Drop, starknet::Event, PartialEq)]
    struct UnusedBidsRefunded {
        #[key]
        account: ContractAddress,
        refunded_amount: u256
    }

    // @dev Emitted when an account exercises their options
    // @param account: The account that exercised the options
    // @param number_of_options: The number of options exercised
    // @param exercised_amount: The amount transferred
    #[derive(Drop, starknet::Event, PartialEq)]
    struct OptionsExercised {
        #[key]
        account: ContractAddress,
        number_of_options: u256,
        exercised_amount: u256
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

        /// Round details

        fn get_vault_address(self: @ContractState) -> ContractAddress {
            self.vault_address.read()
        }

        fn get_round_id(self: @ContractState) -> u256 {
            self.round_id.read()
        }

        fn get_state(self: @ContractState) -> OptionRoundState {
            self.state.read()
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

        fn get_starting_liquidity(self: @ContractState) -> u256 {
            self.starting_liquidity.read()
        }

        fn get_unsold_liquidity(self: @ContractState) -> u256 {
            self.unsold_liquidity.read()
        }

        fn get_reserve_price(self: @ContractState) -> u256 {
            self.reserve_price.read()
        }

        fn get_strike_price(self: @ContractState) -> u256 {
            self.strike_price.read()
        }

        fn get_cap_level(self: @ContractState) -> u128 {
            self.cap_level.read()
        }

        fn get_options_available(self: @ContractState) -> u256 {
            self.bids_tree._get_total_options_available()
        }

        fn get_options_sold(self: @ContractState) -> u256 {
            self.bids_tree.total_options_sold.read()
        }

        fn get_clearing_price(self: @ContractState) -> u256 {
            self.bids_tree.clearing_price.read()
        }

        fn get_total_premium(self: @ContractState) -> u256 {
            self.bids_tree.clearing_price.read() * self.bids_tree.total_options_sold.read()
        }

        fn get_settlement_price(self: @ContractState) -> u256 {
            self.settlement_price.read()
        }

        fn get_total_payout(self: @ContractState) -> u256 {
            self.payout_per_option.read() * self.bids_tree.total_options_sold.read()
        }

        /// Bids

        fn get_bid_details(self: @ContractState, bid_id: felt252) -> Bid {
            let bid: Bid = self.bids_tree._find(bid_id);
            bid
        }

        fn get_account_bids(self: @ContractState, account: ContractAddress) -> Array<Bid> {
            let nonce: u64 = self.account_nonce.read(account);
            let mut bids: Array<Bid> = array![];
            let mut i: u64 = 0;
            while i < nonce {
                let hash = self.create_bid_id(account, i);
                let bid: Bid = self.bids_tree._find(hash);
                bids.append(bid);
                i += 1;
            };
            bids
        }

        fn get_account_bid_nonce(self: @ContractState, account: ContractAddress) -> u64 {
            self.account_nonce.read(account)
        }

        fn get_bid_tree_nonce(self: @ContractState) -> u64 {
            self.bids_tree.tree_nonce.read()
        }

        fn get_account_refundable_balance(self: @ContractState, account: ContractAddress) -> u256 {
            // @dev Has the bidder refunded already ?
            let has_refunded = self.has_refunded.read(account);
            if has_refunded {
                return 0;
            }

            let (mut winning_bids, mut losing_bids, clearing_bid_maybe) = self
                .calculate_bid_outcome_for(account);

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
            let clearing_price = self.bids_tree.clearing_price.read();
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

        fn get_account_mintable_options(self: @ContractState, account: ContractAddress) -> u256 {
            // @dev Has the bidder tokenized already ?
            let has_minted = self.has_minted.read(account);
            if has_minted {
                return 0;
            }

            let (mut winning_bids, _, clearing_bid_maybe) = self.calculate_bid_outcome_for(account);

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

        fn get_account_total_options(self: @ContractState, account: ContractAddress) -> u256 {
            self.get_account_mintable_options(account) + self.erc20.ERC20_balances.read(account)
        }

        fn get_account_payout_balance(self: @ContractState, account: ContractAddress) -> u256 {
            let number_of_options = self.get_account_total_options(account);
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
            let options_available = self
                .calculate_total_options_available(starting_liquidity, strike_price, cap_level);

            // @dev Write auction params to storage & update state
            self.starting_liquidity.write(starting_liquidity);
            self.bids_tree.total_options_available.write(options_available);
            self.set_state(OptionRoundState::Auctioning);

            // @dev Emit auction start event
            self
                .emit(
                    Event::AuctionStarted(AuctionStarted { starting_liquidity, options_available })
                );

            options_available
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
            let options_available = self.bids_tree._get_total_options_available();
            let (clearing_price, options_sold) = self.update_clearing_price();

            // @dev Update unsold liquidity if some options do not sell
            let starting_liq = self.starting_liquidity.read();
            let sold_liq = (starting_liq * options_sold) / options_available;
            let unsold_liquidity = starting_liq - sold_liq;
            if unsold_liquidity.is_non_zero() {
                self.unsold_liquidity.write(unsold_liquidity);
            }

            // @dev Send premiums to Vault
            self.get_eth_dispatcher().transfer(self.vault_address.read(), self.get_total_premium());

            // @dev Update state to Running
            self.set_state(OptionRoundState::Running);

            // @dev Emit auction ended event
            self
                .emit(
                    Event::AuctionEnded(
                        AuctionEnded { options_sold, clearing_price, unsold_liquidity }
                    )
                );

            (clearing_price, options_sold)
        }

        fn settle_round(ref self: ContractState, settlement_price: u256) -> u256 {
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
                        OptionRoundSettled { settlement_price, payout_per_option, }
                    )
                );

            payout_per_option * self.bids_tree.total_options_sold.read()
        }

        /// Option bidder functions

        fn place_bid(ref self: ContractState, amount: u256, price: u256) -> Bid {
            self.assert_bidding_during_an_auction();

            // @dev Assert bid is for more than 0 options
            assert(amount.is_non_zero(), Errors::BidAmountZero);

            // @dev Assert bid price is at or above reserve price
            assert(price >= self.get_reserve_price(), Errors::BidBelowReservePrice);

            // @dev Insert bid into bids tree
            let account = get_caller_address();
            let account_bid_nonce = self.account_nonce.read(account);
            let bid_id = self.create_bid_id(account, account_bid_nonce);
            let tree_nonce = self.bids_tree.tree_nonce.read();
            let bid = Bid { bid_id, owner: account, amount, price, tree_nonce };
            self.bids_tree._insert(bid);

            // @dev Update bidder's nonce
            self.account_nonce.write(account, account_bid_nonce + 1);
            // @dev Transfer bid total from caller to this contract
            let transfer_amount = amount * price;
            self
                .get_eth_dispatcher()
                .transfer_from(account, get_contract_address(), transfer_amount);

            // @dev Emit bid accepted event
            self
                .emit(
                    Event::BidPlaced(
                        BidPlaced {
                            account, bid_id, amount, price, bid_tree_nonce_now: tree_nonce + 1
                        }
                    )
                );

            bid
        }

        fn update_bid(ref self: ContractState, bid_id: felt252, price_increase: u256) -> Bid {
            self.assert_bidding_during_an_auction();

            // @dev Assert caller owns the bid
            let account = get_caller_address();
            let old_node: Node = self.bids_tree.tree.read(bid_id);
            let mut edited_bid: Bid = old_node.value;
            assert(edited_bid.owner == account, Errors::CallerNotBidOwner);

            // @dev Assert caller is increasing the price of their bid
            assert(price_increase.is_non_zero(), Errors::BidMustBeIncreased);

            // @dev Update bid
            let tree_nonce = self.bids_tree.tree_nonce.read();
            edited_bid.tree_nonce = tree_nonce;
            edited_bid.price += price_increase;
            self.bids_tree._delete(bid_id);
            self.bids_tree._insert(edited_bid);

            // @dev Charge the difference
            let bid_amount = edited_bid.amount;
            let difference = bid_amount * price_increase;
            self.get_eth_dispatcher().transfer_from(account, get_contract_address(), difference);

            // @dev Emit bid updated event
            self
                .emit(
                    Event::BidUpdated(
                        BidUpdated {
                            account, bid_id, price_increase, bid_tree_nonce_now: tree_nonce + 1,
                        }
                    )
                );

            edited_bid
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
        fn refund_unused_bids(ref self: ContractState, account: ContractAddress) -> u256 {
            self.assert_auction_ended();

            // @dev Total refundable balance for the bidder
            let refunded_amount = self.get_account_refundable_balance(account);

            // @dev Update the account's has refunded status
            self.has_refunded.write(account, true);

            // @dev Transfer the refunded amount to the bidder
            if refunded_amount > 0 {
                self.get_eth_dispatcher().transfer(account, refunded_amount);
            }

            // @dev Emit bids refunded event
            self.emit(Event::UnusedBidsRefunded(UnusedBidsRefunded { account, refunded_amount }));

            refunded_amount
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

            // @dev Total mintable amount for the caller
            let account = get_caller_address();
            let minted_amount = self.get_account_mintable_options(account);

            // @dev Update has_minted flag
            self.has_minted.write(account, true);

            // @dev Mint the options to the bidder
            self.mint(account, minted_amount);

            // @dev Emit options minted event
            self.emit(Event::OptionsMinted(OptionsMinted { account, minted_amount }));

            minted_amount
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

            // @dev Total number of options to exercise is the caller's mintable balance + their
            // current option ERC-20 token balance
            let account = get_caller_address();
            let mut number_of_options = 0;
            let mintable_amount = self.get_account_mintable_options(account);
            let erc20_option_balance = self.erc20.ERC20_balances.read(account);

            // @dev Burn the ERC20 options
            if erc20_option_balance > 0 {
                number_of_options += erc20_option_balance;
                self.burn(account, erc20_option_balance);
            }

            // @dev Flag the mintable options to no longer be mintable
            number_of_options += mintable_amount;
            self.has_minted.write(account, true);

            // @dev Transfer the payout share to the bidder
            let exercised_amount = number_of_options * self.payout_per_option.read();
            self.get_eth_dispatcher().transfer(account, exercised_amount);

            // Emit options exercised event
            self
                .emit(
                    Event::OptionsExercised(
                        OptionsExercised { account, number_of_options, exercised_amount, }
                    )
                );

            exercised_amount
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
            assert(get_caller_address() == self.vault_address.read(), Errors::CallerIsNotVault);
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
                let nonce = self.account_nonce.read(bidder);
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
        fn create_bid_id(self: @ContractState, bidder: ContractAddress, nonce: u64) -> felt252 {
            poseidon::poseidon_hash_span(array![bidder.into(), nonce.try_into().unwrap()].span())
        }
    }
}
