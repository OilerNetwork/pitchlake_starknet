//Helper functions for posterity
use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait,
    VaultType
};

use starknet::{ContractAddress, testing::{set_contract_address}};
use pitch_lake_starknet::option_round::{
    IOptionRoundDispatcher, IOptionRoundDispatcherTrait, OptionRoundParams, OptionRoundState
};

use pitch_lake_starknet::tests::utils::{vault_manager};

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


    fn end_auction(ref self: OptionRoundFacade) {
        set_contract_address(vault_manager());
        self.option_round_dispatcher.end_auction();
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
        self.vault_address()
    }
    fn total_liquidity(ref self: OptionRoundFacade) -> u256 {
        self.option_round_dispatcher.total_liquidity()
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
        self.option_round_dispatcher.get_params()
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
    fn get_market_aggregator(ref self: OptionRoundFacade) -> ContractAddress {
        self.option_round_dispatcher.get_market_aggregator()
    }
}
