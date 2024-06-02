use starknet::{
    get_block_timestamp, ContractAddress, testing::{set_block_timestamp, set_contract_address}
};
use pitch_lake_starknet::{
    market_aggregator::{
        MarketAggregator, IMarketAggregator, IMarketAggregatorDispatcher,
        IMarketAggregatorDispatcherTrait, IMarketAggregatorSafeDispatcher,
        IMarketAggregatorSafeDispatcherTrait
    },
    vault::{IVaultDispatcher, IVaultDispatcherTrait, Vault, VaultType}, option_round,
    option_round::{
        OptionRound, StartAuctionParams, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,
        IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundState,
    },
    tests::{
        utils::{
            structs::{OptionRoundParams}, event_helpers::{clear_event_logs},
            test_accounts::{liquidity_provider_1, option_bidder_buyer_1, bystander},
            variables::{vault_manager, decimals},
            facades::{
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
                vault_facade::{VaultFacade, VaultFacadeTrait},
            },
            mocks::mock_market_aggregator::{
                MockMarketAggregator, IMarketAggregatorSetterDispatcher,
                IMarketAggregatorSetterDispatcherTrait
            },
        },
    },
};


/// Starting Auction ///

// Start the auction with LP1 depositing 100 eth
fn accelerate_to_auctioning(ref self: VaultFacade) -> u256 {
    accelerate_to_auctioning_custom(
        ref self, array![liquidity_provider_1()].span(), array![100 * decimals()].span()
    )
}

// Start the auction with custom deposits
fn accelerate_to_auctioning_custom(
    ref self: VaultFacade, lps: Span<ContractAddress>, amounts: Span<u256>
) -> u256 {
    // Deposit liquidity
    self.deposit_multiple(amounts, lps);
    // Jump past round transition period and start the auction
    timeskip_and_start_auction(ref self)
}

// Jump past round transition period and start the auction
fn timeskip_and_start_auction(ref self: VaultFacade) -> u256 {
    let now = get_block_timestamp();
    let rtp = self.get_round_transition_period();
    set_block_timestamp(now + rtp + 1);
    set_contract_address(bystander());
    self.start_auction()
}


/// Ending Auction ///

// End the auction, bidding for all options at reserve price (OB1)
fn accelerate_to_running(ref self: VaultFacade) -> (u256, u256) {
    let mut current_round = self.get_current_round();
    let bid_count = current_round.get_total_options_available();
    let bid_price = current_round.get_reserve_price();
    let bid_amount = bid_count * bid_price;
    accelerate_to_running_custom(
        ref self,
        array![option_bidder_buyer_1()].span(),
        array![bid_amount].span(),
        array![bid_price].span()
    )
}

// End the auction with custom bids
fn accelerate_to_running_custom(
    ref self: VaultFacade,
    bidders: Span<ContractAddress>,
    max_amounts: Span<u256>,
    prices: Span<u256>
) -> (u256, u256) {
    // Place bids
    let mut current_round = self.get_current_round();
    current_round.place_bids(max_amounts, prices, bidders);
    // Jump to the auction end date and end the auction
    timeskip_and_end_auction(ref self)
}

// Jump to the auction end date and end the auction
fn timeskip_and_end_auction(ref self: VaultFacade) -> (u256, u256) {
    let mut current_round = self.get_current_round();
    set_contract_address(bystander());
    set_block_timestamp(current_round.get_params().auction_end_time + 1);
    self.end_auction()
}

/// Settling option round ///

// Settle the option round with a custom settlement price (compared to strike to determine payout)
fn accelerate_to_settled(ref self: VaultFacade, avg_base_fee: u256) -> u256 {
    self.set_market_aggregator_value(avg_base_fee);
    timeskip_and_settle_round(ref self)
}

// Jump to the option expriry date and settle the round
fn timeskip_and_settle_round(ref self: VaultFacade) -> u256 {
    let mut current_round = self.get_current_round();
    set_contract_address(bystander());
    set_block_timestamp(current_round.get_params().option_expiry_time + 1);
    self.settle_option_round()
}

