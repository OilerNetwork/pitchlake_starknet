#[starknet::contract]
mod OptionRound {
    use starknet::{get_block_timestamp, get_caller_address, get_contract_address, ContractAddress,};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess,};
    use starknet::storage::{Map};
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin_token::erc20::interface::{
        ERC20ABIDispatcher, ERC20ABIDispatcherTrait, IERC20Metadata
    };
    use pitch_lake::vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
    use pitch_lake::option_round::interface::{
        PricingData, ConstructorArgs, IOptionRound, OptionRoundState
    };
    use pitch_lake::types::{Bid};
    use pitch_lake::library::utils::{max, min};
    use pitch_lake::library::pricing_utils::{
        max_payout_per_option, calculate_total_options_available, calculate_payout_per_option,
    };
    use pitch_lake::library::red_black_tree::{RBTreeComponent, RBTreeComponent::Node};

    // *************************************************************************
    //                                COMPONENTS
    // *************************************************************************

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: RBTreeComponent, storage: bids_tree, event: BidTreeEvent);

    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;

    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl RBTreeOptionRoundImpl = RBTreeComponent::RBTreeOptionRoundImpl<ContractState>;
    impl RBTreeImpl = RBTreeComponent::RBTreeImpl<ContractState>;

    // *************************************************************************
    //                              STORAGE
    // *************************************************************************

    #[storage]
    struct Storage {
        ///
        vault_address: ContractAddress,
        state: OptionRoundState,
        round_id: u64,
        deployment_date: u64,
        auction_start_date: u64,
        auction_end_date: u64,
        option_settlement_date: u64,
        ///
        starting_liquidity: u256,
        settlement_price: u256,
        payout_per_option: u256,
        ///
        pricing_data: PricingData,
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
        const InvalidPricingData: felt252 = 'Invalid pricing data';
        const NotFirstRound: felt252 = 'Not first round';
        // Starting an auction
        const PricingDataNotSet: felt252 = 'Pricing data not set';
        const AuctionStartDateNotReached: felt252 = 'Auction start date not reached';
        const AuctionAlreadyStarted: felt252 = 'Auction already started';
        // Ending an auction
        const AuctionEndDateNotReached: felt252 = 'Auction end date not reached';
        const AuctionAlreadyEnded: felt252 = 'Auction has already ended';
        // Settling an option round
        const OptionSettlementDateNotReached: felt252 = 'Settlement date not reached';
        const OptionRoundAlreadySettled: felt252 = 'Option round already settled';
        // Bidding & upating bids
        const NoOptionsToBidFor: felt252 = 'No options to bid for';
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
        pricing_data,
        round_transition_duration,
        auction_duration,
        round_duration, } =
            args;

        // @dev Set the name and symbol for the minted option (ERC-20) tokens
        let (name, symbol) = self.generate_erc20_name_and_symbol(round_id);
        self.erc20.initializer(name, symbol);

        // @dev Set round's dates
        let deployment_date = get_block_timestamp();
        let auction_start_date = deployment_date + round_transition_duration;
        let auction_end_date = auction_start_date + auction_duration;
        let settlement_date = auction_end_date + round_duration;

        self.deployment_date.write(get_block_timestamp());
        self.auction_start_date.write(auction_start_date);
        self.auction_end_date.write(auction_end_date);
        self.option_settlement_date.write(settlement_date);

        // @dev Set rest of round params
        self.vault_address.write(vault_address);
        self.round_id.write(round_id);
        self.pricing_data.write(pricing_data);
    }

    // *************************************************************************
    //                              EVENTS
    // *************************************************************************

    #[event]
    #[derive(Drop, starknet::Event, PartialEq)]
    enum Event {
        #[flat]
        BidTreeEvent: RBTreeComponent::Event,
        #[flat]
        ERC20Event: ERC20Component::Event,
    }
    // *************************************************************************
    //                            IMPLEMENTATIONS
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

        fn get_round_id(self: @ContractState) -> u64 {
            self.round_id.read()
        }

        fn get_state(self: @ContractState) -> OptionRoundState {
            self.state.read()
        }

        fn get_deployment_date(self: @ContractState) -> u64 {
            self.deployment_date.read()
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

        fn get_sold_liquidity(self: @ContractState) -> u256 {
            let state = self.get_state();

            if state == OptionRoundState::Running || state == OptionRoundState::Settled {
                let max_payout_per_option = max_payout_per_option(
                    self.pricing_data.strike_price.read(), self.pricing_data.cap_level.read()
                );
                let options_sold = self.bids_tree.total_options_sold.read();

                max_payout_per_option * options_sold
            } else {
                0
            }
        }

        fn get_unsold_liquidity(self: @ContractState) -> u256 {
            let state = self.get_state();

            if state == OptionRoundState::Running || state == OptionRoundState::Settled {
                let starting_liq = self.starting_liquidity.read();
                let sold_liq = self.get_sold_liquidity();

                starting_liq - sold_liq
            } else {
                0
            }
        }

        fn get_reserve_price(self: @ContractState) -> u256 {
            self.pricing_data.reserve_price.read()
        }

        fn get_strike_price(self: @ContractState) -> u256 {
            self.pricing_data.strike_price.read()
        }

        fn get_cap_level(self: @ContractState) -> u128 {
            self.pricing_data.cap_level.read()
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

        fn set_pricing_data(ref self: ContractState, pricing_data: PricingData) {
            // @dev Assert the caller is the vault
            self.assert_caller_is_vault();

            // @dev This function can only be called on a vault's first round if the auction has not
            // started yet
            assert(self.round_id.read() == 1, Errors::NotFirstRound);
            assert(self.state.read() == OptionRoundState::Open, Errors::AuctionAlreadyStarted);

            // @dev Set the pricing data points
            self.pricing_data.write(pricing_data);
        }

        fn start_auction(ref self: ContractState, starting_liquidity: u256) -> u256 {
            // @dev Ensure pricing data is set
            // @note todo: handle null rounds
            let pricing_data = self.pricing_data.read();
            let PricingData { strike_price, cap_level, reserve_price } = pricing_data;
            assert(
                strike_price.is_non_zero()
                    && cap_level.is_non_zero()
                    && reserve_price.is_non_zero(),
                Errors::PricingDataNotSet
            );
            // @dev Calculate total options available
            let strike_price = pricing_data.strike_price;
            let cap_level = pricing_data.cap_level;
            let options_available = calculate_total_options_available(
                starting_liquidity, strike_price, cap_level
            );

            // @dev Write auction params to storage
            self.starting_liquidity.write(starting_liquidity);
            self.bids_tree.total_options_available.write(options_available);

            // @dev Transition state
            self.transition_state_to(OptionRoundState::Auctioning);

            // @dev Return total options available in the auction
            options_available
        }

        fn end_auction(ref self: ContractState) -> (u256, u256) {
            // @dev Calculate how many options were sold and the price per one
            let (clearing_price, options_sold, clearing_bid_tree_nonce) = self
                .bids_tree
                .find_clearing_price();

            // @dev Set unsold liquidity if some options do not sell
            let starting_liq = self.starting_liquidity.read();
            let sold_liquidity = options_sold
                * max_payout_per_option(
                    self.pricing_data.strike_price.read(), self.pricing_data.cap_level.read()
                );
            let unsold_liquidity = starting_liq - sold_liquidity;

            //let options_unsold = options_available - options_sold;
            //let unsold_liquidity = match options_available.is_zero() {
            //    true => 0,
            //    false => (starting_liq * options_unsold) / options_available
            //};

            // @dev Send premiums to Vault
            self
                .get_eth_dispatcher()
                .transfer(self.vault_address.read(), options_sold * clearing_price);

            // @dev Transition state
            self.transition_state_to(OptionRoundState::Running);

            // @dev Return clearing price and options sold
            (clearing_price, options_sold)
        }

        fn settle_round(ref self: ContractState, settlement_price: u256) -> (u256, u256) {
            // @dev Calculate payout per option
            let strike_price = self.pricing_data.strike_price.read();
            let cap_level = self.pricing_data.cap_level.read();
            let payout_per_option = calculate_payout_per_option(
                strike_price, cap_level, settlement_price
            );

            // @dev Set payout per option and settlement price
            self.payout_per_option.write(payout_per_option);
            self.settlement_price.write(settlement_price);

            // @dev Transition state 
            self.transition_state_to(OptionRoundState::Settled);

            // @dev Calculate and return total payout and payout per option
            let total_payout = payout_per_option * self.bids_tree.total_options_sold.read();
            (total_payout, payout_per_option)
        }

        /// Account functions

        fn place_bid(
            ref self: ContractState, 
            account: ContractAddress,
            amount: u256, 
            price: u256
        ) -> Bid {
            // @dev Assert the caller is the vault
            self.assert_caller_is_vault();

            // @dev Assert auction still on-going
            self.assert_bid_can_be_placed();

            // @dev Assert bid amount is for more than 0 options and the bid price is
            // at or above the reserve price
            assert(amount.is_non_zero(), Errors::BidAmountZero);
            assert(price >= self.get_reserve_price(), Errors::BidBelowReservePrice);
            // @note todo Do we need to restrict bid amount <= total available ?

            // @dev Create Bid struct
            let account_bid_nonce = self.account_bid_nonce.read(account);
            let bid_id = self.create_bid_id(account, account_bid_nonce);
            let tree_nonce = self.bids_tree.tree_nonce.read();
            let bid = Bid { bid_id, owner: account, amount, price, tree_nonce };

            // @dev Insert bid into bids tree
            self.bids_tree._insert(bid);

            // @dev Update bidder's nonce
            self.account_bid_nonce.write(account, account_bid_nonce + 1);

            // @dev Transfer bid total from account to this contract
            let transfer_amount = amount * price;
            self
                .get_eth_dispatcher()
                .transfer_from(account, get_contract_address(), transfer_amount);

            // @dev Return the created Bid struct
            bid
        }

        fn update_bid(
            ref self: ContractState,
            account: ContractAddress,
            bid_id: felt252,
            price_increase: u256
        ) -> Bid {
            // @dev Assert the caller is the vault
            self.assert_caller_is_vault();

            // @dev Assert auction still on-going
            self.assert_bid_can_be_placed();

            // @dev Assert caller owns the bid
            let old_node: Node = self.bids_tree.tree.read(bid_id);
            let mut edited_bid: Bid = old_node.value;
            let bid_tree_nonce_before = edited_bid.tree_nonce;
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
            let difference = edited_bid.amount * price_increase;
            self.get_eth_dispatcher().transfer_from(account, get_contract_address(), difference);

            // @dev Return the edited bid
            edited_bid
        }

        fn refund_unused_bids(ref self: ContractState, account: ContractAddress) -> u256 {
            // @dev Assert the caller is the vault
            self.assert_caller_is_vault();

            // @dev Assert the auction has ended
            self.assert_auction_over();

            // @dev Get the total refundable balance for the account
            let refunded_amount = self.get_account_refundable_balance(account);

            // @dev Update the account's has refunded status
            self.has_refunded.write(account, true);

            // @dev Transfer the refunded amount to the bidder
            self.get_eth_dispatcher().transfer(account, refunded_amount);

            // @dev Return the refunded amount
            refunded_amount
        }

        fn mint_options(ref self: ContractState, account: ContractAddress) -> u256 {
            // @dev Assert the caller is the vault
            self.assert_caller_is_vault();

            // @dev Assert the auction has ended
            self.assert_auction_over();

            // @dev Get the total mintable balance for the account
            let minted_amount = self.get_account_mintable_options(account);

            // @dev Update the account's has minted status
            self.has_minted.write(account, true);

            // @dev Mint option ERC-20 tokens to the account
            self.erc20.mint(account, minted_amount);

            // @dev Return the amount of option tokens minted
            minted_amount
        }

        fn exercise_options(ref self: ContractState, account: ContractAddress) -> (u256, u256, u256) {
            // @dev Assert the caller is the vault
            self.assert_caller_is_vault();

            // @dev Assert the round has settled
            self.assert_round_settled();

            // @dev Burn the ERC-20 options
            let erc20_option_balance = self.erc20.ERC20_balances.read(account);
            if erc20_option_balance > 0 {
                self.erc20.burn(account, erc20_option_balance);
            }

            // @dev Update the account's has minted status
            let mintable_options_exercised = self.get_account_mintable_options(account);
            self.has_minted.write(account, true);

            // @dev Transfer the payout share to the bidder
            let total_options_exercised = erc20_option_balance + mintable_options_exercised;
            let exercised_amount = total_options_exercised * self.payout_per_option.read();
            self.get_eth_dispatcher().transfer(account, exercised_amount);

            // @dev Return the exercised amount, total options exercised, and mintable options exercised
            (exercised_amount, total_options_exercised, mintable_options_exercised)
        }
    }

    // *************************************************************************
    //                          INTERNAL FUNCTIONS
    // *************************************************************************

    #[generate_trait]
    impl InternalImpl of OptionRoundInternalTrait {
        // @dev Transitions the round's state to `to_state` if the proper conditions are met
        fn transition_state_to(ref self: ContractState, to_state: OptionRoundState) {
            // @dev Assert the caller is the vault
            self.assert_caller_is_vault();

            // @dev Ensure target date has been reached and the current state aligns with
            // the state being transitioned to
            let now = get_block_timestamp();
            let current_state = self.get_state();
            match to_state {
                // @dev Transitioning from Open to Auctioning
                OptionRoundState::Auctioning => {
                    let target = self.get_auction_start_date();
                    assert(now >= target, Errors::AuctionStartDateNotReached);
                    assert(current_state == OptionRoundState::Open, Errors::AuctionAlreadyStarted);
                    self.state.write(to_state);
                },
                // @dev Transitioning from Auctioning to Running
                OptionRoundState::Running => {
                    let target = self.get_auction_end_date();
                    assert(now >= target, Errors::AuctionEndDateNotReached);
                    assert(
                        current_state == OptionRoundState::Auctioning, Errors::AuctionAlreadyEnded
                    );
                    self.state.write(to_state);
                },
                // @dev Transitioning from Running to Settled
                OptionRoundState::Settled => {
                    let target = self.get_option_settlement_date();
                    assert(now >= target, Errors::OptionSettlementDateNotReached);
                    assert(
                        current_state == OptionRoundState::Running,
                        Errors::OptionRoundAlreadySettled
                    );
                    self.state.write(to_state);
                },
                _ => {},
            };
        }

        /// Assertions ///

        // @dev Assert that the caller is the Vault
        fn assert_caller_is_vault(self: @ContractState) {
            assert(get_caller_address() == self.vault_address.read(), Errors::CallerIsNotVault);
        }

        // @dev Assert the auction has ended
        fn assert_auction_over(self: @ContractState) {
            let state = self.get_state();
            assert(
                state == OptionRoundState::Running || state == OptionRoundState::Settled,
                Errors::AuctionNotEnded
            );
        }

        // @dev Assert the round has settled
        fn assert_round_settled(self: @ContractState) {
            assert(self.get_state() == OptionRoundState::Settled, Errors::OptionRoundNotSettled);
        }

        // @dev Assert a bid is being placed during an auction
        fn assert_bid_can_be_placed(self: @ContractState) {
            let state = self.get_state();
            let now = get_block_timestamp();
            let target = self.get_auction_end_date();
            let options_available = self.bids_tree._get_total_options_available();
            assert(
                now < target && state == OptionRoundState::Auctioning,
                Errors::BiddingWhileNotAuctioning
            );
            assert(options_available.is_non_zero(), Errors::NoOptionsToBidFor);
        }

        /// ERC-20

        // @dev Create the contract's ERC20 name and symbol
        fn generate_erc20_name_and_symbol(
            self: @ContractState, round_id: u64
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
                // @dev Get the account's bid amount
                let bidder_nonce = self.account_bid_nonce.read(account);

                // @dev Get the clearing bid
                let clearing_bid_id: felt252 = self.bids_tree.clearing_bid.read();
                let clearing_bid: Bid = self.bids_tree._find(clearing_bid_id);
                let mut clearing_bid_option: Option<Bid> = Option::None(());

                // @dev Iterate over the account's bids and compare them to the clearing bid
                for i in 0
                    ..bidder_nonce {
                        // @dev Get the account's i-th bid
                        let bid_id = self.create_bid_id(account, i);
                        let bid = self.bids_tree._find(bid_id);

                        // @dev If this bid is the clearing bid it is special because it could be
                        // mintable & refundable
                        if bid_id == clearing_bid_id {
                            clearing_bid_option = Option::Some(bid);
                        } // @dev If this bid is not the clearing bid, check if this bid is above or below the clearing bid
                        else {
                            if bid > clearing_bid {
                                winning_bids.append(bid);
                            } else {
                                losing_bids.append(bid);
                            }
                        }
                    };

                // @dev Return the winning bids, losing bids, and the clearing bid if owned
                (winning_bids, losing_bids, clearing_bid_option)
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

