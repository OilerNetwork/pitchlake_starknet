//Helper functions for posterity
use openzeppelin_token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use starknet::{ContractAddress, testing::{set_contract_address}};
use pitch_lake::{
    types::{Errors, Bid}, library::constants::BPS_u256,
    option_round::{
        interface::{
            OptionRoundState, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,
            IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, PricingData
        }
    },
    vault::{
        interface::{
            IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait,
            IVaultSafeDispatcherTrait,
        },
        contract::Vault,
    },
    tests::{
        utils::{
            helpers::{
                setup::eth_supply_and_approve_all_bidders,
                general_helpers::{to_gwei, assert_two_arrays_equal_length, get_erc20_balance},
                accelerators::{accelerate_to_auctioning_custom},
            },
            lib::{test_accounts::{vault_manager, bystander, liquidity_provider_1},},
            facades::{sanity_checks, vault_facade::{VaultFacade, VaultFacadeTrait},},
        }
    },
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

    fn get_vault_facade(ref self: OptionRoundFacade) -> VaultFacade {
        VaultFacade {
            vault_dispatcher: IVaultDispatcher { contract_address: self.vault_address() }
        }
    }

    /// Writes ///

    /// State transition

    // Update the params of the option round
    // @note this sets strike price as well, meaning this function is only to be used where the
    // the strike is irrelevant to the test (i.e only in option distribution tests)
    fn set_pricing_data(ref self: OptionRoundFacade, pricing_data: PricingData) {
        // Force update the params in the round
        self.option_round_dispatcher.set_pricing_data(pricing_data);
    }

    #[feature("safe_dispatcher")]
    fn set_pricing_data_expect_err(
        ref self: OptionRoundFacade, pricing_data: PricingData, error: felt252
    ) {
        let safe = self.get_safe_dispatcher();
        safe.set_pricing_data(pricing_data).expect_err(error);
    }


    // Mock values of the option round and start the auction
    fn setup_mock_auction(
        ref self: OptionRoundFacade,
        ref vault: VaultFacade,
        options_available: u256,
        reserve_price: u256,
    ) {
        // The number of options (M) that can be sold is the total liquidity (L) divided by the max
        // payout per option (Capped)
        // L / Capped = M
        // L = M * Capped
        let strike_price = to_gwei(10); // 10 gwei
        let cap_level: u128 = 5000; // Max payout is 50.00 % above strike
        let capped_payout_per_option = (strike_price * cap_level.into()) / BPS_u256;
        let starting_liquidity = (options_available * capped_payout_per_option);

        // Update the params of the option round
        let pricing_data = PricingData { strike_price, cap_level, reserve_price, };

        // Update the pricing data points as the Vault
        set_contract_address(vault.contract_address());
        self.set_pricing_data(pricing_data);

        let total_options_available = accelerate_to_auctioning_custom(
            ref vault, array![liquidity_provider_1()].span(), array![starting_liquidity].span()
        );

        assert(total_options_available == options_available, 'options available mismatch');
    }

    // Start the next option round's auction
    fn start_auction(ref self: OptionRoundFacade, starting_liquidity: u256) -> u256 {
        let total_options_available = self
            .option_round_dispatcher
            .start_auction(starting_liquidity);
        sanity_checks::start_auction(ref self, total_options_available)
    }

    // End the current option round's auction
    fn end_auction(ref self: OptionRoundFacade) -> (u256, u256) {
        let (clearing_price, total_options_sold, _) = self.option_round_dispatcher.end_auction();
        sanity_checks::end_auction(ref self, clearing_price, total_options_sold)
    }

    // Settle the current option round
    fn settle_option_round(ref self: OptionRoundFacade, settlement_price: u256) -> u256 {
        let (total_payout, _) = self.option_round_dispatcher.settle_round(settlement_price);

        // Set ETH approvals for next round
        let vault_dispatcher = IVaultDispatcher { contract_address: self.vault_address() };
        let next_round_address = vault_dispatcher.get_round_address(self.get_round_id() + 1);
        eth_supply_and_approve_all_bidders(next_round_address, vault_dispatcher.get_eth_address());

        sanity_checks::settle_option_round(ref self, total_payout)
    }

    #[feature("safe_dispatcher")]
    fn start_auction_expect_error(
        ref self: OptionRoundFacade, starting_liquidity: u256, error: felt252,
    ) {
        let safe_option_round = self.get_safe_dispatcher();
        safe_option_round.start_auction(starting_liquidity).expect_err(error);
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
        safe_option_round.settle_round(settlement_price).expect_err(error);
    }


    /// OB functions

    // Place a bid for an option bidder
    // @return: The bid id
    fn place_bid(
        ref self: OptionRoundFacade, amount: u256, price: u256, bidder: ContractAddress,
    ) -> Bid {
        set_contract_address(bidder);
        let bid: Bid = self.option_round_dispatcher.place_bid(bidder, amount, price);
        sanity_checks::place_bid(ref self, bid)
    }

    // Place multiple bids for multiple option bidders
    // @return: Array of bid ids
    fn place_bids(
        ref self: OptionRoundFacade,
        mut amounts: Span<u256>,
        mut prices: Span<u256>,
        mut bidders: Span<ContractAddress>,
    ) -> Array<Bid> {
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
        safe_option_round.place_bid(option_bidder_buyer, amount, price).expect_err(error);
    }

    // Place bids for option bidders, ignoring failed rejected bids
    // @return: An result for whether the bid was accepted or rejected
    #[feature("safe_dispatcher")]
    fn place_bids_ignore_errors(
        ref self: OptionRoundFacade,
        mut amounts: Span<u256>,
        mut prices: Span<u256>,
        mut bidders: Span<ContractAddress>,
    ) {
        assert_two_arrays_equal_length(bidders, amounts);
        assert_two_arrays_equal_length(bidders, prices);
        let safe_option_round = self.get_safe_dispatcher();

        loop {
            match bidders.pop_front() {
                Option::Some(bidder) => {
                    let bid_amount = amounts.pop_front().unwrap();
                    let bid_price = prices.pop_front().unwrap();
                    // Make bid
                    set_contract_address(*bidder);
                    match safe_option_round.place_bid(*bidder, *bid_amount, *bid_price) {
                        Result::Ok(_) => {},
                        Result::Err(_) => {}
                    }
                },
                Option::None => { break (); }
            }
        }
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
                    safe_option_round
                        .place_bid(*bidder, *bid_amount, *bid_price)
                        .expect_err(*error);
                },
                Option::None => { break (); }
            }
        };
    }

    // Update a bid for an option bidder
    // @return: The updated bid
    fn update_bid(ref self: OptionRoundFacade, id: felt252, price_increase: u256) -> Bid {
        let old_bid = self.get_bid_details(id);
        let bidder = old_bid.owner;
        set_contract_address(bidder);
        let new_bid = self.option_round_dispatcher.update_bid(bidder, id, price_increase);
        sanity_checks::update_bid(ref self, old_bid, new_bid)
    }

    // @note add bidder as param for testing
    #[feature("safe_dispatcher")]
    fn update_bid_expect_error(
        ref self: OptionRoundFacade,
        id: felt252,
        price_increase: u256,
        bidder: ContractAddress,
        error: felt252,
    ) {
        let safe_option_round = self.get_safe_dispatcher();
        set_contract_address(bidder);
        safe_option_round.update_bid(bidder, id, price_increase).expect_err(error);
    }

    // Refunds all unused bids of an option bidder
    // @return: The amount refunded
    fn refund_bid(ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress) -> u256 {
        set_contract_address(option_bidder_buyer);
        let refundable_balance = self.get_refundable_balance_for(option_bidder_buyer);
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
        let (exercised_amount, _, _) = self
            .option_round_dispatcher
            .exercise_options(option_bidder_buyer);
        sanity_checks::exercise_options(ref self, exercised_amount, individual_payout)
    }

    #[feature("safe_dispatcher")]
    fn exercise_options_expect_error(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress, error: felt252,
    ) {
        set_contract_address(option_bidder_buyer);
        let safe_option_round = self.get_safe_dispatcher();
        safe_option_round.exercise_options(option_bidder_buyer).expect_err(error);
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
    fn mint_options(ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress) -> u256 {
        set_contract_address(option_bidder_buyer);
        let option_erc20_balance_before = get_erc20_balance(
            self.contract_address(), option_bidder_buyer
        );
        let options_minted = self.option_round_dispatcher.mint_options(option_bidder_buyer);
        sanity_checks::tokenize_options(
            ref self, option_bidder_buyer, option_erc20_balance_before, options_minted,
        )
    }

    #[feature("safe_dispatcher")]
    fn mint_options_expect_error(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress, error: felt252,
    ) {
        set_contract_address(option_bidder_buyer);
        let safe_option_round = self.get_safe_dispatcher();
        safe_option_round.mint_options(option_bidder_buyer).expect_err(error);
    }

    /// Reads ///

    /// Dates

    fn get_deployment_date(ref self: OptionRoundFacade) -> u64 {
        self.option_round_dispatcher.get_deployment_date()
    }

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
        self.option_round_dispatcher.get_starting_liquidity()
    }

    fn sold_liquidity(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_sold_liquidity()
    }


    fn unsold_liquidity(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_unsold_liquidity()
    }

    fn total_premiums(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_total_premium()
    }

    fn total_payout(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_total_payout()
    }

    fn get_auction_clearing_price(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_clearing_price()
    }

    fn total_options_sold(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_options_sold()
    }

    fn get_bid_details(ref self: OptionRoundFacade, bid_id: felt252) -> Bid {
        self.option_round_dispatcher.get_bid_details(bid_id)
    }

    fn get_bidding_nonce_for(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress
    ) -> u64 {
        self.option_round_dispatcher.get_account_bid_nonce(option_bidder_buyer)
    }

    fn get_bid_tree_nonce(ref self: OptionRoundFacade) -> u64 {
        self.option_round_dispatcher.get_bid_tree_nonce()
    }


    fn get_bids_for(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress
    ) -> Array<Bid> {
        self.option_round_dispatcher.get_account_bids(option_bidder_buyer)
    }

    fn get_refundable_balance_for(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress
    ) -> u256 {
        self.option_round_dispatcher.get_account_refundable_balance(option_bidder_buyer)
    }

    fn get_payout_balance_for(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress
    ) -> u256 {
        self.option_round_dispatcher.get_account_payout_balance(option_bidder_buyer)
    }

    fn get_mintable_options_for(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress
    ) -> u256 {
        self.option_round_dispatcher.get_account_mintable_options(option_bidder_buyer)
    }

    /// Other
    fn get_state(ref self: OptionRoundFacade) -> OptionRoundState {
        self.option_round_dispatcher.get_state()
    }

    fn vault_address(ref self: OptionRoundFacade) -> ContractAddress {
        self.option_round_dispatcher.get_vault_address()
    }

    fn contract_address(ref self: OptionRoundFacade) -> ContractAddress {
        self.option_round_dispatcher.contract_address
    }

    fn get_round_id(ref self: OptionRoundFacade) -> u64 {
        self.option_round_dispatcher.get_round_id()
    }

    /// Previously OptionRoundParms

    fn get_strike_price(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_strike_price()
    }

    fn get_cap_level(ref self: OptionRoundFacade) -> u128 {
        self.option_round_dispatcher.get_cap_level()
    }

    fn get_reserve_price(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_reserve_price()
    }

    fn get_total_options_available(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_options_available()
    }

    fn get_settlement_price(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_settlement_price()
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
