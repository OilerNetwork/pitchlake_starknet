//Helper functions for posterity
use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait,
    VaultType
};
use starknet::{ContractAddress, testing::{set_contract_address}};
use pitch_lake_starknet::{
    option_round::{
        IOptionRoundDispatcher, IOptionRoundDispatcherTrait, OptionRoundState, StartAuctionParams,
    },
    tests::{utils::{variables::{vault_manager}, structs::{OptionRoundParams}}}
};


#[derive(Drop)]
struct OptionRoundFacade {
    option_round_dispatcher: IOptionRoundDispatcher,
}

#[generate_trait]
impl OptionRoundFacadeImpl of OptionRoundFacadeTrait {
    /// Writes ///

    /// State transition

    fn start_auction(ref self: OptionRoundFacade) {
        set_contract_address(vault_manager());
        let start_auction_params = StartAuctionParams {};
        self.option_round_dispatcher.start_auction(start_auction_params);
    }

    fn end_auction(ref self: OptionRoundFacade) -> u256 {
        set_contract_address(vault_manager());
        self.option_round_dispatcher.end_auction()
    }

    fn settle_option_round(ref self: OptionRoundFacade, settlement_price: u256) -> bool {
        self.option_round_dispatcher.settle_option_round(settlement_price)
    }

    /// OB functions

    fn place_bid(
        ref self: OptionRoundFacade,
        amount: u256,
        price: u256,
        option_bidder_buyer: ContractAddress,
    ) -> bool {
        set_contract_address(option_bidder_buyer);
        let result: bool = self.option_round_dispatcher.place_bid(amount, price);
        result
    }

    fn place_bids(
        ref self: OptionRoundFacade,
        mut bidders: Span<ContractAddress>,
        mut amounts: Span<u256>,
        mut prices: Span<u256>
    ) {
        loop {
            match bidders.pop_front() {
                Option::Some(bidder) => {
                    let bid_amount = amounts.pop_front().unwrap();
                    let bid_price = prices.pop_front().unwrap();
                    self.place_bid(*bid_amount, *bid_price, *bidder);
                },
                Option::None => { break (); }
            }
        };
    }

    fn refund_bid(ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress) -> u256 {
        set_contract_address(option_bidder_buyer);
        let result: u256 = self.option_round_dispatcher.refund_unused_bids(option_bidder_buyer);
        result
    }

    fn refund_bids(ref self: OptionRoundFacade, mut bidders: Span<ContractAddress>) {
        loop {
            match bidders.pop_front() {
                Option::Some(bidder) => { self.refund_bid(*bidder); },
                Option::None => { break (); }
            }
        };
    }

    fn exercise_options(ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress) -> u256 {
        self.option_round_dispatcher.exercise_options(option_bidder_buyer)
    }

    fn exercise_options_multiple(ref self: OptionRoundFacade, mut bidders: Span<ContractAddress>) {
        loop {
            match bidders.pop_front() {
                Option::Some(bidder) => { self.exercise_options(*bidder); },
                Option::None => { break (); }
            }
        };
    }

    /// Reads ///

    /// Dates

    fn get_auction_start_date(ref self: OptionRoundFacade) -> u64 {
        self.option_round_dispatcher.get_auction_start_date()
    }

    fn get_auction_end_date(ref self: OptionRoundFacade) -> u64 {
        self.option_round_dispatcher.get_auction_end_date()
    }

    fn get_option_expiry_date(ref self: OptionRoundFacade) -> u64 {
        self.option_round_dispatcher.get_option_expiry_date()
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

    fn get_unused_bids_for(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress
    ) -> u256 {
        self.option_round_dispatcher.get_unused_bids_for(option_bidder_buyer)
    }

    fn get_payout_balance_for(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress
    ) -> u256 {
        self.option_round_dispatcher.get_payout_balance_for(option_bidder_buyer)
    }

    /// Other

    fn get_state(ref self: OptionRoundFacade) -> OptionRoundState {
        self.option_round_dispatcher.get_state()
    }

    fn vault_address(ref self: OptionRoundFacade) -> ContractAddress {
        self.option_round_dispatcher.vault_address()
    }

    fn contract_address(ref self: OptionRoundFacade) -> ContractAddress {
        self.option_round_dispatcher.contract_address
    }

    fn get_params(ref self: OptionRoundFacade) -> OptionRoundParams {
        OptionRoundParams {
            current_average_basefee: self.get_current_average_basefee(),
            standard_deviation: self.get_standard_deviation(),
            strike_price: self.get_strike_price(),
            cap_level: self.get_cap_level(),
            collateral_level: 0,
            reserve_price: self.get_reserve_price(),
            total_options_available: self.get_total_options_available(),
            minimum_collateral_required: 0,
            auction_end_time: self.get_auction_end_date(),
            option_expiry_time: self.get_option_expiry_date(),
        }
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
}
