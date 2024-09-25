#[starknet::contract]
mod OptionRound {
    use pitch_lake::library::utils::{max, min, calculate_payout_per_option, max_payout_per_option};
    use pitch_lake::vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
    use pitch_lake::option_round::interface::{ConstructorArgs, IOptionRound, OptionRoundState};
    use pitch_lake::library::red_black_tree::{RBTreeComponent, RBTreeComponent::Node};
    use pitch_lake::types::{Bid, Consts::BPS,};
    use starknet::{get_block_timestamp, get_caller_address, get_contract_address, ContractAddress,};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess,};
    use starknet::storage::{Map, StoragePathEntry};
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin_token::erc20::interface::{
        ERC20ABIDispatcher, ERC20ABIDispatcherTrait, IERC20Metadata
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
    // @starting_liquidity: The amount of liquidity this round starts with (locked upon auction
    // starting)
    // @payout_per_option: The amount the option round pays out per option upon settlement
    // @auction_start_date: The auction start date
    // @auction_end_date: The auction end date
    // @option_settlement_date: The option settlement date
    // @constructor:params: Params to pass at option round creation, to be set by fossil
    // @bidder_nonces: A mapping of address to u256, tells the current nonce for an address, allows
    // tracking of bids for each user and used to create unique bid id's for each bid @bids_tree:
    // Storage for the bids tree, see rb-tree-component @erc20: Storage for erc20 component of the
    // round.
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
        account_bid_nonce: Map<ContractAddress, u64>,
        has_minted: Map<ContractAddress, bool>,
        has_refunded: Map<ContractAddress, bool>,
        ///
        #[substorage(v0)]
        bids_tree: RBTreeComponent::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }
    // *************************************************************************
    //                                Errors
    // *************************************************************************
    mod Errors {
        const CallerIsNotVault: felt252 = 'Caller not the Vault';
        // Starting an auction
        const AuctionStartDateNotReached: felt252 = 'Auction start date not reached';
        const AuctionAlreadyStarted: felt252 = 'Auction already started';
        // Ending an auction
        const AuctionEndDateNotReached: felt252 = 'Auction end date not reached';
        const AuctionAlreadyEnded: felt252 = 'Auction has already ended';
        // Settling an option round
        const OptionSettlementDateNotReached: felt252 = 'Settlement date not reached';
        const OptionRoundAlreadySettled: felt252 = 'Option round already settled';
        // Bidding & upating bids
        const BiddingWhileNotAuctioning: felt252 = 'Can only bid while auctioning';
        const BidAmountZero: felt252 = 'Bid amount cannot be 0';
        const BidBelowReservePrice: felt252 = 'Bid price below reserve price';
        const CallerNotBidOwner: felt252 = 'Caller is not bid owner';
        const BidMustBeIncreased: felt252 = 'Bid updates must increase price';
        // Refunding bids & tokenizing options
        const AuctionNotEnded: felt252 = 'Auction has not ended yet';
        const OptionRoundNotSettled: felt252 = 'Option round not settled yet';
        /// Internal Errors ///
        const BidsShouldNotHaveSameTreeNonce: felt252 = 'Tree nonces should be unique';
    }


    // *************************************************************************
    //                              Constructor
    // *************************************************************************
    #[constructor]
    fn constructor(ref self: ContractState, args: ConstructorArgs) {
        // @dev Get the constructor arguments
        let ConstructorArgs { vault_address,
        round_id,
        auction_start_date,
        auction_end_date,
        option_settlement_date,
        reserve_price,
        cap_level,
        strike_price } =
            args;

        // @dev Set the name and symbol for the minted option (ERC-20) tokens
        let (name, symbol) = self.generate_erc20_name_and_symbol(round_id);
        self.erc20.initializer(name, symbol);

        // @dev Set OptionRound's params
        self.state.write(OptionRoundState::Open);
        self.vault_address.write(vault_address);
        self.round_id.write(round_id);
        self.reserve_price.write(reserve_price);
        self.cap_level.write(cap_level);
        self.strike_price.write(strike_price);
        self.auction_start_date.write(auction_start_date);
        self.auction_end_date.write(auction_end_date);
        self.option_settlement_date.write(option_settlement_date);
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
    // @member options_available: The max number of options that can sell in the auction
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

        fn get_account_bid_nonce(self: @ContractState, account: ContractAddress) -> u64 {
            self.account_bid_nonce.read(account)
        }

        fn get_bid_tree_nonce(self: @ContractState) -> u64 {
            self.bids_tree.tree_nonce.read()
        }

        fn get_bid_details(self: @ContractState, bid_id: felt252) -> Bid {
            let bid: Bid = self.bids_tree._find(bid_id);
            bid
        }

        fn get_account_bids(self: @ContractState, account: ContractAddress) -> Array<Bid> {
            // @dev Get the number of bids the account has placed
            let nonce: u64 = self.account_bid_nonce.read(account);
            let mut bids: Array<Bid> = array![];
            let mut i: u64 = 0;
            // @dev Re-create the account's bid ids and get the bid from the tree
            while i < nonce {
                let hash = self.create_bid_id(account, i);
                let bid: Bid = self.bids_tree._find(hash);
                bids.append(bid);
                i += 1;
            };
            bids
        }

        /// Accounts

        fn get_account_refundable_balance(self: @ContractState, account: ContractAddress) -> u256 {
            // @dev If the account has already refunded their bids, return 0
            let has_refunded = self.has_refunded.read(account);
            if has_refunded {
                return 0;
            }

            // @dev Get the account's winning bids, losing bids, and clearing bid if the account
            // owns it
            let (mut winning_bids, mut losing_bids, clearing_bid_maybe) = self
                .calculate_bid_outcome_for(account);

            // @dev Add refundable balance from the clearing bid
            let mut refundable_balance = 0;
            match clearing_bid_maybe {
                Option::None => {},
                Option::Some(bid) => {
                    // @dev Only the clearing_bid can be partially sold, the
                    // clearing_bid_amount_sold is saved in the tree
                    let options_sold = self.bids_tree.clearing_bid_amount_sold.read();
                    let options_not_sold = bid.amount - options_sold;
                    refundable_balance += options_not_sold * bid.price;
                },
            }

            // @dev Add refundable balances from all losing bids
            let clearing_price = self.bids_tree.clearing_price.read();
            loop {
                match losing_bids.pop_front() {
                    Option::None => { break (); },
                    Option::Some(bid) => { refundable_balance += bid.amount * bid.price; },
                }
            };

            // @dev Add refundable balance for over paid bids
            loop {
                match winning_bids.pop_front() {
                    Option::None => { break (); },
                    Option::Some(bid) => {
                        if (bid.price > clearing_price) {
                            let price_difference = bid.price - clearing_price;
                            refundable_balance += bid.amount * price_difference;
                        }
                    },
                }
            };

            refundable_balance
        }

        fn get_account_mintable_options(self: @ContractState, account: ContractAddress) -> u256 {
            // @dev If the account has already minted their options, return 0
            let has_minted = self.has_minted.read(account);
            if has_minted {
                return 0;
            }

            // @dev Get the account's winning bids, losing bids, and clearing bid if the account
            // owns it
            let (mut winning_bids, _, clearing_bid_maybe) = self.calculate_bid_outcome_for(account);

            // @dev Add mintable balance from the clearing bid
            let mut mintable_balance = 0;
            match clearing_bid_maybe {
                Option::Some(_) => {
                    // @dev The clearing bid potentially sells < the total options bid for, so it is
                    // stored separately
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
            // @dev An account's total options is their mintable balance plus any option ERC20
            // tokens the already own
            self.get_account_mintable_options(account) + self.erc20.balance_of(account)
        }

        fn get_account_payout_balance(self: @ContractState, account: ContractAddress) -> u256 {
            // @dev An account's payout balance is their total options multiplied by the payout per
            // option
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

            // @dev Emit auction started event
            self
                .emit(
                    Event::AuctionStarted(AuctionStarted { starting_liquidity, options_available })
                );

            // @dev Return total options available in the auction
            options_available
        }

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

            // @dev Send premiums to the vault
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

            // @dev Return clearing price and options sold
            (clearing_price, options_sold)
        }

        fn settle_round(ref self: ContractState, settlement_price: u256) -> u256 {
            self.assert_caller_is_vault();
            self.assert_round_can_settle();

            // @dev Calculate payout per option
            let strike_price = self.get_strike_price();
            let cap_level = self.get_cap_level().into();
            let payout_per_option = calculate_payout_per_option(
                strike_price, cap_level, settlement_price
            );

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

            // @dev Return total payout
            payout_per_option * self.bids_tree.total_options_sold.read()
        }

        /// Account functions

        fn place_bid(ref self: ContractState, amount: u256, price: u256) -> Bid {
            self.assert_bidding_during_an_auction();

            // @dev Assert bid is for more than 0 options
            assert(amount.is_non_zero(), Errors::BidAmountZero);

            // @dev Assert bid price is at or above reserve price
            assert(price >= self.get_reserve_price(), Errors::BidBelowReservePrice);

            // @dev Insert bid into bids tree
            let account = get_caller_address();
            let account_bid_nonce = self.account_bid_nonce.read(account);
            let bid_id = self.create_bid_id(account, account_bid_nonce);
            let tree_nonce = self.bids_tree.tree_nonce.read();
            let bid = Bid { bid_id, owner: account, amount, price, tree_nonce };
            self.bids_tree._insert(bid);

            // @dev Update bidder's nonce
            self.account_bid_nonce.write(account, account_bid_nonce + 1);

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

            // @return The created bid
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

            // @dev Update bid's price
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

            // @dev Return the edited bid
            edited_bid
        }

        fn refund_unused_bids(ref self: ContractState, account: ContractAddress) -> u256 {
            self.assert_auction_ended();

            // @dev Get the total refundable balance for the account
            let refunded_amount = self.get_account_refundable_balance(account);

            // @dev Update the account's has refunded status
            self.has_refunded.write(account, true);

            // @dev Transfer the refunded amount to the bidder
            self.get_eth_dispatcher().transfer(account, refunded_amount);

            // @dev Emit bids refunded event
            self.emit(Event::UnusedBidsRefunded(UnusedBidsRefunded { account, refunded_amount }));

            // @dev Return the refunded amount
            refunded_amount
        }

        fn mint_options(ref self: ContractState) -> u256 {
            self.assert_auction_ended();

            // @dev Get the total mintable balance for the account
            let account = get_caller_address();
            let minted_amount = self.get_account_mintable_options(account);

            // @dev Update the account's has minted status
            self.has_minted.write(account, true);

            // @dev Mint option ERC-20 tokens to the account
            self.erc20.mint(account, minted_amount);

            // @dev Emit options minted event
            self.emit(Event::OptionsMinted(OptionsMinted { account, minted_amount }));

            // @dev Return the amount of option tokens minted
            minted_amount
        }

        fn exercise_options(ref self: ContractState) -> u256 {
            self.assert_round_settled();

            // @dev Get the account's total option balance
            let account = get_caller_address();
            let mut number_of_options = 0;
            let mintable_amount = self.get_account_mintable_options(account);
            let erc20_option_balance = self.erc20.ERC20_balances.read(account);

            // @dev Burn the ERC-20 options
            if erc20_option_balance > 0 {
                number_of_options += erc20_option_balance;
                self.erc20.burn(account, erc20_option_balance);
            }

            // @dev Update the account's has minted status
            number_of_options += mintable_amount;
            self.has_minted.write(account, true);

            // @dev Transfer the payout share to the bidder
            let exercised_amount = number_of_options * self.payout_per_option.read();
            self.get_eth_dispatcher().transfer(account, exercised_amount);

            // @dev Emit options exercised event
            self
                .emit(
                    Event::OptionsExercised(
                        OptionsExercised { account, number_of_options, exercised_amount, }
                    )
                );

            // @dev Return the exercised amount
            exercised_amount
        }
    }

    // *************************************************************************
    //                          INTERNAL FUNCTIONS
    // *************************************************************************
    #[generate_trait]
    impl InternalImpl of OptionRoundInternalTrait {
        /// Assertions

        // @dev Assert that the caller is the Vault
        fn assert_caller_is_vault(self: @ContractState) {
            assert(get_caller_address() == self.vault_address.read(), Errors::CallerIsNotVault);
        }

        // @dev Assert if the round's params can be updated
        fn assert_params_can_update(ref self: ContractState) {
            let state = self.get_state();
            let now = get_block_timestamp();
            let auction_start_date = self.get_auction_start_date();

            assert(
                state == OptionRoundState::Open && now < auction_start_date,
                Errors::AuctionAlreadyStarted
            );
        }

        // @dev An auction can only start if the current time is greater than the auction start
        // date, and if the round is in the Open state
        fn assert_auction_can_start(self: @ContractState) {
            let state = self.get_state();
            let now = get_block_timestamp();
            let auction_start_date = self.get_auction_start_date();
            assert(now >= auction_start_date, Errors::AuctionStartDateNotReached);
            assert(state == OptionRoundState::Open, Errors::AuctionAlreadyStarted);
        }

        // @dev An auction can only end if the current time is greater than the auction end date,
        // and if the round is in the Auctioning state
        fn assert_auction_can_end(self: @ContractState) {
            let state = self.get_state();
            let now = get_block_timestamp();
            let auction_end_date = self.get_auction_end_date();
            assert(now >= auction_end_date, Errors::AuctionEndDateNotReached);
            assert(state == OptionRoundState::Auctioning, Errors::AuctionAlreadyEnded);
        }

        // @dev Assert the auction has ended
        fn assert_auction_ended(self: @ContractState) {
            let state = self.get_state();
            assert(
                state == OptionRoundState::Running || state == OptionRoundState::Settled,
                Errors::AuctionNotEnded
            );
        }

        // @dev A round can only settle if the current time is greater than the option settlement
        // date, and if the round is in the Running state
        fn assert_round_can_settle(self: @ContractState) {
            let state = self.get_state();
            let now = get_block_timestamp();
            let settlement_date = self.get_option_settlement_date();
            assert(now >= settlement_date, Errors::OptionSettlementDateNotReached);
            assert(state == OptionRoundState::Running, Errors::OptionRoundNotSettled);
        }

        // @dev Assert the round has settled
        fn assert_round_settled(self: @ContractState) {
            assert(self.get_state() == OptionRoundState::Settled, Errors::OptionRoundNotSettled);
        }

        // @dev A bid can only be placed during the auction
        fn assert_bidding_during_an_auction(self: @ContractState) {
            let now = get_block_timestamp();
            let auction_end_date = self.get_auction_end_date();
            let state = self.get_state();
            assert(now < auction_end_date, Errors::BiddingWhileNotAuctioning);
            assert(state == OptionRoundState::Auctioning, Errors::BiddingWhileNotAuctioning);
        }

        /// ERC-20

        // @dev Create the contract's ERC20 name and symbol
        fn generate_erc20_name_and_symbol(
            self: @ContractState, round_id: u256
        ) -> (ByteArray, ByteArray) {
            let name: ByteArray = format!("Pitch Lake Option Round {round_id}");
            let symbol: ByteArray = format!("PLOR{round_id}");
            (name, symbol)
        }

        // @dev Get a dispatcher for the ETH contract
        fn get_eth_dispatcher(self: @ContractState) -> ERC20ABIDispatcher {
            let vault = self.get_vault_dispatcher();
            let eth_address = vault.get_eth_address();
            ERC20ABIDispatcher { contract_address: eth_address }
        }

        /// Round helpers

        // @dev Update the state of the round
        fn set_state(ref self: ContractState, state: OptionRoundState) {
            self.state.write(state);
        }

        // @dev Calculate the clearing price and total options sold from the auction
        fn update_clearing_price(ref self: ContractState) -> (u256, u256) {
            self.bids_tree.find_clearing_price()
        }

        // @dev Get an account's winning bids, losing bids, and the clearing bid if the account owns
        // it
        fn calculate_bid_outcome_for(
            self: @ContractState, account: ContractAddress
        ) -> (Array<Bid>, Array<Bid>, Option<Bid>) {
            let mut winning_bids: Array<Bid> = array![];
            let mut losing_bids: Array<Bid> = array![];

            // @dev If the auction has not ended yet, all bids are pending
            let state = self.state.read();
            if (state == OptionRoundState::Open || state == OptionRoundState::Auctioning) {
                return (winning_bids, losing_bids, Option::None(()));
            } // @dev Look at each bid of the account's bids compared to the clearing bid
            else {
                let nonce = self.account_bid_nonce.read(account);
                let clearing_bid_id: felt252 = self.bids_tree.clearing_bid.read();
                let clearing_bid: Bid = self.bids_tree._find(clearing_bid_id);
                let mut clearing_bid_option: Option<Bid> = Option::None(());
                let mut i = 0;
                while i < nonce {
                    // @dev Check if this bid is the clearing bid
                    let bid_id: felt252 = self.create_bid_id(account, i);
                    let bid: Bid = self.bids_tree._find(bid_id);
                    if bid_id == clearing_bid_id {
                        clearing_bid_option = Option::Some(bid);
                    } // @dev Check if this bid is above or below the clearing bid
                    else {
                        if bid > clearing_bid {
                            winning_bids.append(bid);
                        } else {
                            losing_bids.append(bid);
                        }
                    }
                    i += 1;
                };

                // @dev Return the winning bids, losing bids, and the clearing bid if the account
                // owns it
                (winning_bids, losing_bids, clearing_bid_option)
            }
        }

        //// @dev Calculate the maximum payout for a single option
        //fn _max_payout_per_option(
        //    self: @ContractState, strike_price: u256, cap_level: u128
        //) -> u256 {
        //    (strike_price * cap_level.into()) / BPS
        //}

        //// @dev Calculate the actual payout for a single option
        //fn calculate_payout_per_option(
        //    self: @ContractState, strike_price: u256, cap_level: u128, settlement_price: u256
        //) -> u256 {
        //    if (settlement_price <= strike_price) {
        //        0
        //    } else {
        //        let uncapped = settlement_price - strike_price;
        //        let capped = self._max_payout_per_option(strike_price, cap_level);

        //        min(capped, uncapped)
        //    }
        //}

        // @dev Calculate the total number of options available to sell in the auction
        fn calculate_total_options_available(
            self: @ContractState, starting_liquidity: u256, strike_price: u256, cap_level: u128
        ) -> u256 {
            let capped = max_payout_per_option(strike_price, cap_level);
            match capped == 0 {
                // @dev If the max payout per option is 0, then there are 0 options to sell
                true => 0,
                // @dev Else the number of options available is the starting liquidity divided by
                // the capped amount
                false => starting_liquidity / capped
            }
        }

        // @dev Get a dispatcher for the vault
        fn get_vault_dispatcher(self: @ContractState) -> IVaultDispatcher {
            IVaultDispatcher { contract_address: self.vault_address.read() }
        }

        // @dev Calculate a bid's id
        fn create_bid_id(self: @ContractState, bidder: ContractAddress, nonce: u64) -> felt252 {
            poseidon::poseidon_hash_span(array![bidder.into(), nonce.try_into().unwrap()].span())
        }
    }
}
