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


//@note: confirm start/end auction flow in relation to vault function and set_contract_address accordingly
//fn start_auction(ref option_round_dispatcher: IOptionRoundDispatcher) -> bool {
//    let result: bool = option_round_dispatcher.start_auction();
//     return result;
// }

// fn end_auction(ref option_round_dispatcher: IOptionRoundDispatcher) {
//     option_round_dispatcher.end_auction();
// }

#[derive(Drop)]
struct OptionRoundFacade {
    option_round_dispatcher: IOptionRoundDispatcher,
}

#[generate_trait]
impl OptionRoundFacadeImpl of OptionRoundFacadeTrait {
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

    fn refund_bid(ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress) -> u256 {
        set_contract_address(option_bidder_buyer);
        let result: u256 = self.option_round_dispatcher.refund_unused_bids(option_bidder_buyer);
        result
    }

    fn exercise_options(ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress) -> u256 {
        self.option_round_dispatcher.exercise_options(option_bidder_buyer)
    }
    fn get_state(ref self: OptionRoundFacade) -> OptionRoundState {
        self.option_round_dispatcher.get_state()
    }

    fn vault_address(ref self: OptionRoundFacade) -> ContractAddress {
        self.option_round_dispatcher.vault_address()
    }
    fn starting_liquidity(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.starting_liquidity()
    }
    fn total_unallocated_liquidity(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.total_unallocated_liquidity()
    }
    fn total_payout(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.total_payouts()
    }

    fn total_unallocated_liquidity_collected(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.total_unallocated_liquidity_collected()
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

    fn total_options_sold(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.total_options_sold()
    }

    fn get_auction_clearing_price(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.get_auction_clearing_price()
    }

    fn total_collateral(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.total_collateral()
    }

    fn total_premiums(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.total_premiums()
    }

    // Gets the remaining liquidity of an option round (assuming it is settled)
    // @dev This is the amount that was rolled to the next round
    fn get_remaining_liquidity(ref self: OptionRoundFacade) -> u256 {
        let round = self.option_round_dispatcher;
        round.total_collateral()
            + round.total_premiums()
            - round.total_unallocated_liquidity_collected()
            - round.total_payouts()
    }

    // Get the round's liquidity spread (collateral, unallocated)
    fn get_all_round_liquidity(ref self: OptionRoundFacade) -> (u256, u256) {
        let round = self.option_round_dispatcher;
        let collateral = round.total_collateral();
        let unallocated = round.total_unallocated_liquidity();
        (collateral, unallocated)
    }

    fn get_payout_balance_for(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress
    ) -> u256 {
        self.option_round_dispatcher.get_payout_balance_for(option_bidder_buyer)
    }
    fn get_unused_bids_for(
        ref self: OptionRoundFacade, option_bidder_buyer: ContractAddress
    ) -> u256 {
        self.option_round_dispatcher.get_unused_bids_for(option_bidder_buyer)
    }

    // Get the date the option round starts
    fn round_start_date(ref self: OptionRoundFacade) -> u64 {
        0
    }

    // Get the date the option round ends
    fn round_end_date(ref self: OptionRoundFacade) -> u64 {
        0
    }

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

    fn get_auction_start_date(ref self: OptionRoundFacade) -> u64 {
        self.option_round_dispatcher.get_auction_start_date()
    }

    fn get_auction_end_date(ref self: OptionRoundFacade) -> u64 {
        self.option_round_dispatcher.get_auction_end_date()
    }

    fn get_option_expiry_date(ref self: OptionRoundFacade) -> u64 {
        self.option_round_dispatcher.get_option_expiry_date()
    }


    //These functions have some custom logic

    fn bid_multiple(
        ref self: OptionRoundFacade,
        bidders: Span<ContractAddress>,
        amounts: Span<u256>,
        prices: Span<u256>
    ) {
        let _params = self.get_params();
        let mut index: u32 = 0;
        // let bid_price = params.reserve_price;
        while index < bidders
            .len() {
                // @note: shall we remove this?
                // assert(
                //     *prices[index] > bid_price && *amounts[index] > *prices[index],
                //     ('Invalid parameters at {}')
                // );
                self.place_bid(*amounts[index], *prices[index], *bidders[index]);
                index += 1;
            }
    }
}
