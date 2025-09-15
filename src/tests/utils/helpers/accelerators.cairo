use pitch_lake::{
    vault::interface::L1Data, vault::interface::{IVaultDispatcherTrait},
    tests::{
        utils::{
            lib::{
                test_accounts::{bystander, liquidity_providers_get, option_bidders_get},
                variables::{decimals},
            },
            helpers::{ // accelerators::{accelerate_to_auction_custom_auction_params},
                general_helpers::{to_gwei},
                //setup::{deploy_custom_option_round},
            },
            facades::{
                option_round_facade::{OptionRoundFacadeTrait},
                vault_facade::{VaultFacade, VaultFacadeTrait},
            },
        },
    },
};
use starknet::testing::{set_block_timestamp, set_contract_address};
use starknet::{ContractAddress, get_block_timestamp};


/// Accelerators ///

// Start the auction with LP1 depositing 100 eth
pub fn accelerate_to_auctioning(ref self: VaultFacade) -> u256 {
    accelerate_to_auctioning_custom(
        ref self, array![*liquidity_providers_get(1)[0]].span(), array![100 * decimals()].span(),
    )
}

// Start the auction with custom deposits
pub fn accelerate_to_auctioning_custom(
    ref self: VaultFacade, liquidity_providers: Span<ContractAddress>, amounts: Span<u256>,
) -> u256 {
    // Deposit liquidity
    self.deposit_multiple(amounts, liquidity_providers);
    // Jump past round transition period and start the auction
    timeskip_and_start_auction(ref self)
}

/// Ending Auction

// End the auction, OB1 bids for all options at reserve price
pub fn accelerate_to_running(ref self: VaultFacade) -> (u256, u256) {
    let mut current_round = self.get_current_round();
    let bid_amount = current_round.get_total_options_available();
    let bid_price = current_round.get_reserve_price();
    accelerate_to_running_custom(
        ref self,
        array![*option_bidders_get(1)[0]].span(),
        array![bid_amount].span(),
        array![bid_price].span(),
    )
}

// End the auction with custom bids
pub fn accelerate_to_running_custom(
    ref self: VaultFacade,
    bidders: Span<ContractAddress>,
    max_amounts: Span<u256>,
    prices: Span<u256>,
) -> (u256, u256) {
    let mut current_round = self.get_current_round();
    current_round.place_bids(max_amounts, prices, bidders);

    // Jump to the auction end date and end the auction
    timeskip_and_end_auction(ref self)
}

/// Settling option round

pub fn accelerate_to_settled_custom(ref self: VaultFacade, l1_data: L1Data) -> u256 {
    // Get the data request to fulfill
    let mut j = array![];
    self.get_request_to_settle_round().serialize(ref j);

    // Jump to the option expiry date and settle the round
    timeskip_to_settlement_date(ref self);
    let req = self.get_request_to_settle_round_serialized();
    let res = self.generate_settle_round_result_serialized(l1_data);
    self.fossil_callback(req, res)
}

// Settle the option round with a custom settlement price (compared to strike to determine payout)
pub fn accelerate_to_settled(ref self: VaultFacade, twap: u256) -> u256 {
    accelerate_to_settled_custom(
        ref self, L1Data { twap, max_return: 5000, reserve_price: to_gwei(2) },
    )
}


/// Timeskips ///

/// Timeskip and do nothing

// Jump past the auction end date
pub fn timeskip_past_auction_end_date(ref self: VaultFacade) {
    let mut current_round = self.get_current_round();
    set_block_timestamp(current_round.get_auction_end_date());
}

// Jump past the option expiry date
pub fn timeskip_past_option_expiry_date(ref self: VaultFacade) {
    let mut current_round = self.get_current_round();
    set_block_timestamp(current_round.get_option_settlement_date());
}

// Jump past the round transition period
pub fn timeskip_past_round_transition_period(ref self: VaultFacade) {
    let now = get_block_timestamp();
    let round_transition_period = self.get_round_transition_period();
    set_block_timestamp(now + round_transition_period);
}

// Jump to settlement date includes proving delay
pub fn timeskip_to_settlement_date(ref self: VaultFacade) {
    let mut current_round = self.get_current_round();
    set_block_timestamp(current_round.get_option_settlement_date() + self.get_proving_delay());
}

// Jump to settlement date does not include proving delay
pub fn timeskip_to_settlement_date_no_delay(ref self: VaultFacade) {
    let mut current_round = self.get_current_round();
    set_block_timestamp(current_round.get_option_settlement_date());
}

/// Timeskip and do something

// Jump past round transition period and start the auction
pub fn timeskip_and_start_auction(ref self: VaultFacade) -> u256 {
    timeskip_past_round_transition_period(ref self);
    set_contract_address(bystander());
    self.vault_dispatcher.start_auction()
}

// Jump to the auction end date and end the auction
pub fn timeskip_and_end_auction(ref self: VaultFacade) -> (u256, u256) {
    let mut current_round = self.get_current_round();
    set_block_timestamp(current_round.get_auction_end_date());
    set_contract_address(bystander());
    self.vault_dispatcher.end_auction()
}
