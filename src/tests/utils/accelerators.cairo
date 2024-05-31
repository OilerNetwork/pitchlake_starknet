use starknet::{ContractAddress, testing::{set_block_timestamp, set_contract_address}};
use pitch_lake_starknet::{
    pitch_lake::{
        IPitchLakeDispatcher, IPitchLakeSafeDispatcher, IPitchLakeDispatcherTrait, PitchLake,
        IPitchLakeSafeDispatcherTrait
    },
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
            test_accounts::{liquidity_provider_1, option_bidder_buyer_1},
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

// Accelerate to the current round auctioning (needs non 0 liquidity to start auction)
fn accelerate_to_auctioning(ref self: VaultFacade) {
    accelerate_to_auctioning_custom(
        ref self, array![liquidity_provider_1()].span(), array![100 * decimals()].span()
    );
}

fn accelerate_to_auctioning_custom(
    ref self: VaultFacade, lps: Span<ContractAddress>, amounts: Span<u256>
) -> u256 {
    // Deposit liquidity into round
    let deposit_total = self.deposit_mutltiple(lps, amounts);
    // Start round 1's auction
    set_block_timestamp(starknet::get_block_timestamp() + self.get_round_transition_period() + 1);
    set_contract_address(vault_manager());
    self.start_auction();
    deposit_total
}

// Accelerate to the current round's auction end, bidding for all options at reserve price
fn accelerate_to_running(ref self: VaultFacade) -> u256 {
    let mut current_round = self.get_current_round();
    let bid_count = current_round.get_total_options_available();
    let bid_price = current_round.get_reserve_price();
    let bid_amount = bid_count * bid_price;
    accelerate_to_auctioning_custom(
        ref self, array![option_bidder_buyer_1()].span(), array![bid_amount, bid_count].span()
    )
}

fn accelerate_to_running_custom(
    ref self: VaultFacade,
    bidders: Span<ContractAddress>,
    max_amounts: Span<u256>,
    prices: Span<u256>
) -> (u256, u256) {
    // Place bids
    let mut current_round = self.get_current_round();
    current_round.place_bids(bidders, max_amounts, prices);
    // End auction
    set_block_timestamp(current_round.get_auction_end_date() + 1);
    self.end_auction()
}


fn accelerate_to_settled(ref self: VaultFacade, avg_base_fee: u256) {
    self.set_market_aggregator_value(avg_base_fee);
    timeskip_and_settle_round(ref self);
}


// Create various amounts array (For bids use the function twice for price and amount)
fn create_array_linear(amount: u256, len: u32) -> Array<u256> {
    let mut arr: Array<u256> = array![];
    let mut index = 0;
    while (index < len) {
        arr.append(amount);
        index += 1;
    };
    arr
}

fn create_array_gradient(amount: u256, step: u256, len: u32) -> Array<u256> {
    let mut arr: Array<u256> = array![];
    let mut index: u32 = 0;
    while (index < len) {
        arr.append(amount + index.into() * step);
        index += 1;
    };
    arr
}

/// State transition with additional logic

fn timeskip_and_settle_round(ref self: VaultFacade) -> u256 {
    let mut current_round = self.get_current_round();
    set_block_timestamp(current_round.get_params().option_expiry_time + 1);
    self.settle_option_round()
}

fn timeskip_and_end_auction(ref self: VaultFacade) -> (u256, u256) {
    let mut current_round = self.get_current_round();
    set_block_timestamp(current_round.get_params().auction_end_time + 1);
    self.end_auction()
}

