//Helper functions for posterity
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use pitch_lake_starknet::contracts::vault::{
    interface::{
        IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, IVaultSafeDispatcherTrait,
    },
    contract::Vault,
};
use starknet::{ContractAddress, testing::{set_contract_address}};
use pitch_lake_starknet::{
    contracts::option_round::{
        interface::{
            IOptionRoundDispatcher, IOptionRoundDispatcherTrait, OptionRoundState,
            StartAuctionParams, SettleOptionRoundParams, OptionRoundConstructorParams, Bid,
            IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait,
        }
    },
    tests::{
        utils::{
            helpers::{
                setup::eth_supply_and_approve_all_bidders,
                general_helpers::{assert_two_arrays_equal_length, get_erc20_balance}
            },
            lib::{test_accounts::{vault_manager, bystander}, structs::{OptionRoundParams}},
            facades::sanity_checks,
        }
    },
    types::{VaultType, Errors}
};

#[derive(Drop)]
struct OptionRoundFacade {
    option_round_dispatcher: IOptionRoundDispatcher,
}

#[generate_trait]
impl OptionRoundFacadeImpl of OptionRoundFacadeTrait {
    fn get_safe_dispatcher(ref self: OptionRoundFacade) -> IOptionRoundSafeDispatcher {
        IOptionRoundSafeDispatcher { contract_address: self.contract_address() }
    }

    /// Writes ///

    /// State transition

    // Start the next option round's auction
    fn start_auction(ref self: OptionRoundFacade, params: StartAuctionParams,) -> u256 {
        let total_options_available = self.option_round_dispatcher.start_auction(params);
        sanity_checks::start_auction(ref self, total_options_available)
    }

    // End the current option round's auction
    fn end_auction(ref self: OptionRoundFacade) -> (u256, u256) {
        let (clearing_price, total_options_sold) = self.option_round_dispatcher.end_auction();
        sanity_checks::end_auction(ref self, clearing_price, total_options_sold)
    }

    // Settle the current option round
    fn settle_option_round(ref self: OptionRoundFacade, settlement_price: u256) -> u256 {
        let total_payout = self
            .option_round_dispatcher
            .settle_option_round(SettleOptionRoundParams { settlement_price });

        // Set ETH approvals for next round
        let vault_dispatcher = IVaultDispatcher { contract_address: self.vault_address() };
        let next_round_address = vault_dispatcher.get_option_round_address(self.get_round_id() + 1);
        eth_supply_and_approve_all_bidders(next_round_address, vault_dispatcher.eth_address());

        sanity_checks::settle_option_round(ref self, total_payout)
    }

    #[feature("safe_dispatcher")]
    fn start_auction_expect_error(
        ref self: OptionRoundFacade, params: StartAuctionParams, error: felt252,
    ) {
        let safe_option_round = self.get_safe_dispatcher();
        safe_option_round.start_auction(params).expect_err(error);
    }

    #[feature("safe_dispatcher")]
    fn end_auction_expect_error(ref self: OptionRoundFacade, error: felt252) {
        let safe_option_round = self.get_safe_dispatcher();
        safe_option_round.end_auction().expect_err(error);
    }


    #[feature("safe_dispatcher")]
    fn settle_option_round_expect_error(
        ref self: OptionRoundFacade, settlement_price: u256, error: felt252,
    ) {
        let safe_option_round = self.get_safe_dispatcher();
        safe_option_round
            .settle_option_round(SettleOptionRoundParams { settlement_price })
            .expect_err(error);
    }


    /// OB functions

    // Place a bid for an option bidder
    // @return: The bid id
    fn place_bid(
        ref self: OptionRoundFacade, amount: u256, price: u256, bidder: ContractAddress,
    ) -> felt252 {
        set_contract_address(bidder);
        let bid: Bid = self.option_round_dispatcher.place_bid(amount, price);
        sanity_checks::place_bid(ref self, bidder, bid.id)
    }

    // Place multiple bids for multiple option bidders
    // @return: Array of bid ids
    fn place_bids(
        ref self: OptionRoundFacade,
        mut amounts: Span<u256>,
        mut prices: Span<u256>,
        mut bidders: Span<ContractAddress>,
    ) -> Array<felt252> {
        assert_two_arrays_equal_length(bidders, amounts);
        assert_two_arrays_equal_length(bidders, prices);
        let mut results = array![];
        loop {
            match bidders.pop_front() {
                Option::Some(bidder) => {
                    let bid_amount = amounts.pop_front().unwrap();
                    let bid_price = prices.pop_front().unwrap();
                    // Make bid
                    let bid_id = self.place_bid(*bid_amount, *bid_price, *bidder);
                    // Append result
                    results.append(bid_id);
                },
                Option::None => { break (); }
            }
        };
        results
    }

    // Place a bid for an option bidder
    // @return: An result for whether the bid was accepted or rejected
    #[feature("safe_dispatcher")]
    fn place_bid_expect_error(
        ref self: OptionRoundFacade,
        amount: u256,
        price: u256,
        option_bidder_buyer: ContractAddress,
        error: felt252,
    ) {
        set_contract_address(option_bidder_buyer);
        let safe_option_round = self.get_safe_dispatcher();
        safe_option_round.place_bid(amount, price).expect_err(error);
    }


    // Place multiple bids for multiple option bidders
    // @return: An result for whether the bids were accepted or rejected
    #[feature("safe_dispatcher")]
    fn place_bids_expect_error(
        ref self: OptionRoundFacade,
        mut amounts: Span<u256>,
        mut prices: Span<u256>,
        mut bidders: Span<ContractAddress>,
        mut errors: Span<felt252>,
    ) {
        assert_two_arrays_equal_length(bidders, amounts);
        assert_two_arrays_equal_length(bidders, prices);
        let safe_option_round = self.get_safe_dispatcher();
        loop {
            match bidders.pop_front() {
                Option::Some(bidder) => {
                    set_contract_address(*bidder);
                    let bid_amount = amounts.pop_front().unwrap();
                    let bid_price = prices.pop_front().unwrap();
                    let error = errors.pop_front().unwrap();
                    // Make bid
                    safe_option_round.place_bid(*bid_amount, *bid_price).expect_err(*error);
                },
                Option::None => { break (); }
            }
        };
    }

    // Update a bid for an option bidder
    // @return: The updated bid
    fn update_bid(ref self: OptionRoundFacade, id: felt252, amount: u256, price: u256) -> Bid {
        let bid = self.get_bid_details(id);
        let bidder = bid.owner;
        set_contract_address(bidder);
        let updated_bid = self.option_round_dispatcher.update_bid(id, amount, price);
        sanity_checks::update_bid(ref self, id, updated_bid)
    }

    // @note add bidder as param for testing
    #[feature("safe_dispatcher")]
    fn update_bid_expect_error(
        ref self: OptionRoundFacade,
        id: felt252,
        amount: u256,
        price: u256,
        bidder: ContractAddress,
        error: felt252,
    ) {
        let safe_option_round = self.get_safe_dispatcher();
        safe_option_round.update_bid(id, amount, price).expect_err(error);
    }

    // Refunds all unused bids of an option bidder
    // @return: The amount refunded
    fn refund_bid(ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress) -> u256 {
        set_contract_address(option_bidder_buyer);
        let refundable_balance = self.get_refundable_bids_for(option_bidder_buyer);
        let refunded_amount = self.option_round_dispatcher.refund_unused_bids(option_bidder_buyer);
        sanity_checks::refund_bid(ref self, refunded_amount, refundable_balance)
    }

    #[feature("safe_dispatcher")]
    fn refund_bid_expect_error(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress, error: felt252,
    ) {
        let safe_option_round = self.get_safe_dispatcher();
        safe_option_round.refund_unused_bids(option_bidder_buyer).expect_err(error);
    }
    // Refunds all unused bids of multiple option bidders
    // @return: The amounts refunded
    fn refund_bids(ref self: OptionRoundFacade, mut bidders: Span<ContractAddress>) -> Array<u256> {
        let mut refund_amounts = array![];
        loop {
            match bidders.pop_front() {
                Option::Some(bidder) => {
                    let refund_amount = self.refund_bid(*bidder);
                    refund_amounts.append(refund_amount)
                },
                Option::None => { break (); }
            }
        };
        refund_amounts
    }

    // Exercise options for an option buyer
    // @return: The payout amount
    // @note: Call using bystander ?
    fn exercise_options(ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress) -> u256 {
        set_contract_address(option_bidder_buyer);
        let individual_payout = self.get_payout_balance_for(option_bidder_buyer);
        let exercised_amount = self.option_round_dispatcher.exercise_options();
        sanity_checks::exercise_options(ref self, exercised_amount, individual_payout)
    }

    #[feature("safe_dispatcher")]
    fn exercise_options_expect_error(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress, error: felt252,
    ) {
        set_contract_address(option_bidder_buyer);
        let safe_option_round = self.get_safe_dispatcher();
        safe_option_round.exercise_options().expect_err(error);
    }

    // Exercise options for multiple option buyers
    // @return: The payout amounts
    fn exercise_options_multiple(
        ref self: OptionRoundFacade, mut bidders: Span<ContractAddress>
    ) -> Array<u256> {
        let mut payouts = array![];
        loop {
            match bidders.pop_front() {
                Option::Some(bidder) => { payouts.append(self.exercise_options(*bidder)); },
                Option::None => { break (); }
            }
        };
        payouts
    }

    // Tokenize options for an option buyer
    // @return: The amount of options minted
    fn tokenize_options(ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress) -> u256 {
        set_contract_address(option_bidder_buyer);
        let option_erc20_balance_before = get_erc20_balance(
            self.contract_address(), option_bidder_buyer
        );
        let options_minted = self.option_round_dispatcher.tokenize_options();
        sanity_checks::tokenize_options(
            ref self, option_bidder_buyer, option_erc20_balance_before, options_minted,
        )
    }

    #[feature("safe_dispatcher")]
    fn tokenize_options_expect_error(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress, error: felt252,
    ) {
        set_contract_address(option_bidder_buyer);
        let safe_option_round = self.get_safe_dispatcher();
        safe_option_round.tokenize_options().expect_err(error);
    }

    /// Reads ///

    /// Dates

    fn get_auction_start_date(ref self: OptionRoundFacade) -> u64 {
        self.option_round_dispatcher.get_auction_start_date()
    }

    fn get_auction_end_date(ref self: OptionRoundFacade) -> u64 {
        self.option_round_dispatcher.get_auction_end_date()
    }

    fn get_option_settlement_date(ref self: OptionRoundFacade) -> u64 {
        self.option_round_dispatcher.get_option_settlement_date()
    }

    /// $

    fn starting_liquidity(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.starting_liquidity()
    }

    fn total_premiums(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.total_premiums()
    }

    fn total_payout(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.total_payout()
    }

    fn get_auction_clearing_price(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_auction_clearing_price()
    }

    fn total_options_sold(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.total_options_sold()
    }

    fn get_bid_details(ref self: OptionRoundFacade, bid_id: felt252) -> Bid {
        self.option_round_dispatcher.get_bid_details(bid_id)
    }

    fn get_bidding_nonce_for(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress
    ) -> u32 {
        self.option_round_dispatcher.get_bidding_nonce_for(option_bidder_buyer)
    }


    fn get_bids_for(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress
    ) -> Array<Bid> {
        self.option_round_dispatcher.get_bids_for(option_bidder_buyer)
    }

    fn get_refundable_bids_for(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress
    ) -> u256 {
        self.option_round_dispatcher.get_refundable_bids_for(option_bidder_buyer)
    }

    fn get_payout_balance_for(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress
    ) -> u256 {
        self.option_round_dispatcher.get_payout_balance_for(option_bidder_buyer)
    }

    fn get_option_balance_for(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress
    ) -> u256 {
        self.option_round_dispatcher.get_tokenizable_options_for(option_bidder_buyer)
    }

    /// Other
    fn get_constructor_params(ref self: OptionRoundFacade) -> OptionRoundConstructorParams {
        self.option_round_dispatcher.get_constructor_params()
    }

    fn get_state(ref self: OptionRoundFacade) -> OptionRoundState {
        self.option_round_dispatcher.get_state()
    }

    fn vault_address(ref self: OptionRoundFacade) -> ContractAddress {
        self.option_round_dispatcher.vault_address()
    }

    fn contract_address(ref self: OptionRoundFacade) -> ContractAddress {
        self.option_round_dispatcher.contract_address
    }

    fn get_round_id(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_round_id()
    }

    /// Previously OptionRoundParms

    fn get_current_average_basefee(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_current_average_basefee()
    }

    fn get_standard_deviation(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_standard_deviation()
    }

    fn get_strike_price(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_strike_price()
    }

    fn get_cap_level(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_cap_level()
    }

    fn get_reserve_price(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_reserve_price()
    }

    fn get_total_options_available(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_total_options_available()
    }

    /// ERC20 functions
    fn to_erc20(ref self: OptionRoundFacade) -> ERC20ABIDispatcher {
        ERC20ABIDispatcher { contract_address: self.contract_address() }
    }

    fn name(ref self: OptionRoundFacade) -> ByteArray {
        self.to_erc20().name()
    }

    fn symbol(ref self: OptionRoundFacade) -> ByteArray {
        self.to_erc20().symbol()
    }

    fn decimals(ref self: OptionRoundFacade) -> u8 {
        self.to_erc20().decimals()
    }

    fn balance_of(ref self: OptionRoundFacade, owner: ContractAddress) -> u256 {
        self.to_erc20().balance_of(owner)
    }
}
