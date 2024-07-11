use starknet::{
    contract_address_const, get_block_timestamp, ContractAddress,
    testing::{set_block_timestamp, set_contract_address}
};
use pitch_lake_starknet::{
    contracts::{
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
    },
    tests::{
        utils::{
            lib::{
                structs::{OptionRoundParams},
                test_accounts::{
                    vault_manager, liquidity_provider_1, option_bidder_buyer_1, bystander,
                    option_bidders_get, liquidity_providers_get,
                },
                variables::{decimals},
            },
            helpers::{ // accelerators::{accelerate_to_auction_custom_auction_params},
                event_helpers::{clear_event_logs,},
                general_helpers::{assert_two_arrays_equal_length},
                setup::{deploy_custom_option_round},
            },
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


/// Accelerators ///

// Start the auction with LP1 depositing 100 eth
fn accelerate_to_auctioning(ref self: VaultFacade) -> u256 {
    accelerate_to_auctioning_custom(
        ref self, array![*liquidity_providers_get(1)[0]].span(), array![100 * decimals()].span()
    )
}

// Start the auction with custom deposits
fn accelerate_to_auctioning_custom(
    ref self: VaultFacade, liquidity_providers: Span<ContractAddress>, amounts: Span<u256>
) -> u256 {
    // Deposit liquidity
    self.deposit_multiple(amounts, liquidity_providers);
    // Jump past round transition period and start the auction
    timeskip_and_start_auction(ref self)
}

// Start the auction with a basic deposit with custom auction params
//fn accelerate_to_auctioning_custom_auction_params(
//    ref self: VaultFacade, total_options_available: u256, reserve_price: u256
//) -> u256 {
//    let auction_params = StartAuctionParams { total_options_available, reserve_price, };
//    set_contract_address(self.contract_address());
//    timeskip_past_round_transition_period(ref self);
//
//    let mut upcoming_round = self.get_next_round();
//    upcoming_round.start_auction(123)
//}

/// Ending Auction

// End the auction, OB1 bids for all options at reserve price
fn accelerate_to_running(ref self: VaultFacade) -> (u256, u256) {
    let mut current_round = self.get_current_round();
    let bid_amount = current_round.get_total_options_available();
    let bid_price = current_round.get_reserve_price();
    accelerate_to_running_custom(
        ref self,
        array![*option_bidders_get(1)[0]].span(),
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

// Helper function to deploy custom option round, start auction, place bids,
// then end auction
// Used to test real number outcomes for option distributions
// @note Re-name, add additional comments for clarity
fn accelerate_to_running_custom_option_round(
    vault_address: ContractAddress,
    total_options_available: u256,
    reserve_price: u256,
    bid_amounts: Span<u256>,
    bid_prices: Span<u256>,
) -> (u256, u256, OptionRoundFacade) {
    // Check amounts and prices array lengths are equal
    assert_two_arrays_equal_length(bid_amounts, bid_prices);

    // Deploy custom option round
    let auction_start_date: u64 = 1;
    let auction_end_date: u64 = 2;
    let option_settlement_date: u64 = 3;

    let mut option_round = deploy_custom_option_round(
        vault_address,
        1_u256,
        auction_start_date,
        auction_end_date,
        option_settlement_date,
        reserve_price,
        'cap_level',
        'strike price'
    );

    // Start auction
    set_contract_address(vault_address);
    set_block_timestamp(auction_start_date + 1);

    //Should this be called from the option round??
    option_round
        .start_auction(
            StartAuctionParams {
                total_options_available,
                starting_liquidity: 100 * decimals(),
                reserve_price: reserve_price,
                cap_level: 2,
                strike_price: 3,
            }
        );

    // Make bids
    let mut option_bidders = option_bidders_get(bid_amounts.len()).span();
    option_round.place_bids_raw(bid_amounts, bid_prices, option_bidders);

    // End auction
    set_contract_address(vault_address);
    set_block_timestamp(auction_end_date + 1);
    let (clearing_price, options_sold) = option_round.end_auction();

    (clearing_price, options_sold, option_round)
}

/// Settling option round

// Settle the option round with a custom settlement price (compared to strike to determine payout)
fn accelerate_to_settled(ref self: VaultFacade, avg_base_fee: u256) -> u256 {
    self.set_market_aggregator_value(avg_base_fee);
    timeskip_and_settle_round(ref self)
}


/// Timeskips ///

/// Timeskip and do nothing

// Jump past the auction end date
fn timeskip_past_auction_end_date(ref self: VaultFacade) {
    let mut current_round = self.get_current_round();
    set_block_timestamp(current_round.get_auction_end_date() + 1);
}

// Jump past the option expiry date
fn timeskip_past_option_expiry_date(ref self: VaultFacade) {
    let mut current_round = self.get_current_round();
    set_block_timestamp(current_round.get_option_settlement_date() + 1);
}

// Jump past the round transition period
fn timeskip_past_round_transition_period(ref self: VaultFacade) {
    let now = get_block_timestamp();
    let round_transition_period = self.vault_dispatcher.get_round_transition_period();
    set_block_timestamp(now + round_transition_period + 1);
}

/// Timeskip and do something

// Jump past round transition period and start the auction
fn timeskip_and_start_auction(ref self: VaultFacade) -> u256 {
    timeskip_past_round_transition_period(ref self);
    set_contract_address(bystander());
    match self.vault_dispatcher.start_auction() {
        Result::Ok(options_available) => options_available,
        Result::Err(e) => panic(array!['Error:', e.into()])
    }
}

// Jump to the auction end date and end the auction
fn timeskip_and_end_auction(ref self: VaultFacade) -> (u256, u256) {
    let mut current_round = self.get_current_round();
    set_block_timestamp(current_round.get_auction_end_date() + 1);
    set_contract_address(bystander());
    match self.vault_dispatcher.end_auction() {
        Result::Ok((clearing_price, options_sold)) => (clearing_price, options_sold),
        Result::Err(e) => panic(array!['Error:', e.into()])
    }
}

// Jump to the option expriry date and settle the round
fn timeskip_and_settle_round(ref self: VaultFacade) -> u256 {
    let mut current_round = self.get_current_round();
    set_block_timestamp(current_round.get_option_settlement_date() + 1);
    set_contract_address(bystander());
    self.settle_option_round()
}

