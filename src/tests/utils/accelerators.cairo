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
    self.deposit_mutltiple(lps, amounts);
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


/// Array helpers ///

// Create array of length `len`, each element is `amount` (For bids use the function twice for price and amount)
fn create_array_linear(amount: u256, len: u32) -> Array<u256> {
    let mut arr: Array<u256> = array![];
    let mut index = 0;
    while (index < len) {
        arr.append(amount);
        index += 1;
    };
    arr
}

// Create array of length `len`, each element is `amount + index * step` (For bids use the function twice for price and amount)
fn create_array_gradient(amount: u256, step: u256, len: u32) -> Array<u256> {
    let mut arr: Array<u256> = array![];
    let mut index: u32 = 0;
    while (index < len) {
        arr.append(amount + index.into() * step);
        index += 1;
    };
    arr
}

// Sum all of the u256s in a given span
fn sum_u256_array(mut arr: Span<u256>) -> u256 {
    let mut sum = 0;
    match arr.pop_front() {
        Option::Some(el) => { sum += *el; },
        Option::None => {}
    }
    sum
}

// Assert two arrays of any type are equal
fn assert_two_arrays_equal_length<T, V>(arr1: Span<T>, arr2: Span<V>) {
    assert(arr1.len() == arr2.len(), 'Arrays not equal length');
}

// Sum an array of spreads and return the total spread
fn sum_spreads(mut spreads: Span<(u256, u256)>) -> (u256, u256) {
    let mut total_locked: u256 = 0;
    let mut total_unlocked: u256 = 0;
    loop {
        match spreads.pop_front() {
            Option::Some((
                locked, unlocked
            )) => {
                total_locked += *locked;
                total_unlocked += *unlocked;
            },
            Option::None => { break (); }
        }
    };
    (total_locked, total_unlocked)
}

// Split spreads into locked and unlocked arrays
fn split_spreads(mut spreads: Span<(u256, u256)>) -> (Array<u256>, Array<u256>) {
    let mut locked: Array<u256> = array![];
    let mut unlocked: Array<u256> = array![];
    loop {
        match spreads.pop_front() {
            Option::Some((
                locked_amount, unlocked_amount
            )) => {
                locked.append(*locked_amount);
                unlocked.append(*unlocked_amount);
            },
            Option::None => { break (); }
        }
    };
    (locked, unlocked)
}
