use starknet::{
    contract_address_const, get_block_timestamp, ContractAddress,
    testing::{set_block_timestamp, set_contract_address}
};
use core::fmt::Display;
use pitch_lake::{
    vault::{
        contract::Vault,
        interface::{FossilDataPoints, VaultType, IVaultDispatcher, IVaultDispatcherTrait}
    },
    option_round::{
        contract::{OptionRound},
        interface::{OptionRoundState, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,},
    },
    fact_registry::{
        contract::FactRegistry,
        interface::{
            JobRange, JobRequest, JobRequestParams, IFactRegistry, IFactRegistryDispatcher,
            IFactRegistryDispatcherTrait,
        }
    },
    tests::{
        utils::{
            lib::{
                test_accounts::{
                    vault_manager, liquidity_provider_1, option_bidder_buyer_1, bystander,
                    option_bidders_get, liquidity_providers_get,
                },
                variables::{decimals},
            },
            helpers::{ // accelerators::{accelerate_to_auction_custom_auction_params},
                event_helpers::{clear_event_logs,},
                general_helpers::{to_gwei, assert_two_arrays_equal_length, get_erc20_balances},
                //setup::{deploy_custom_option_round},
            },
            facades::{
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
                vault_facade::{VaultFacade, VaultFacadeTrait},
                fact_registry_facade::{FactRegistryFacade, FactRegistryFacadeTrait},
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
    let mut current_round = self.get_current_round();
    current_round.place_bids(max_amounts, prices, bidders);

    // Jump to the auction end date and end the auction
    timeskip_and_end_auction(ref self)
}

/// Settling option round

// Settle the option round with a custom settlement price (compared to strike to determine payout)
fn accelerate_to_settled(ref self: VaultFacade, TWAP: u256) -> u256 {
    let mut current_round = self.get_current_round();
    let to = current_round.get_option_settlement_date();

    // Create a fake job request for the round to settle
    let JobRange { twap_range, volatility_range, reserve_price_range } = Vault::EXPECTED_JOB_RANGE;
    let job_request: JobRequest = JobRequest {
        identifiers: array![selector!("PITCH_LAKE_V1")].span(),
        params: JobRequestParams {
            twap: (to - twap_range, to),
            volatility: (to - volatility_range, to),
            reserve_price: (to - reserve_price_range, to),
        }
    };

    // Mock verify the fact in the registry
    let data = FossilDataPoints { twap: TWAP, volatility: 5000, reserve_price: to_gwei(2), };
    self.get_fact_registry_facade().set_fact(job_request, data);

    // Jump to the option expiry date and settle the round
    timeskip_and_settle_round(ref self, job_request)
}


/// Timeskips ///

/// Timeskip and do nothing

// Jump past the auction end date
fn timeskip_past_auction_end_date(ref self: VaultFacade) {
    let mut current_round = self.get_current_round();
    set_block_timestamp(current_round.get_auction_end_date());
}

// Jump past the option expiry date
fn timeskip_past_option_expiry_date(ref self: VaultFacade) {
    let mut current_round = self.get_current_round();
    set_block_timestamp(current_round.get_option_settlement_date());
}

// Jump past the round transition period
fn timeskip_past_round_transition_period(ref self: VaultFacade) {
    let now = get_block_timestamp();
    let round_transition_period = self.vault_dispatcher.get_round_transition_period();
    set_block_timestamp(now + round_transition_period);
}

/// Timeskip and do something

// Jump past round transition period and start the auction
fn timeskip_and_start_auction(ref self: VaultFacade) -> u256 {
    timeskip_past_round_transition_period(ref self);
    set_contract_address(bystander());
    self.vault_dispatcher.start_auction()
}

// Jump to the auction end date and end the auction
fn timeskip_and_end_auction(ref self: VaultFacade) -> (u256, u256) {
    let mut current_round = self.get_current_round();
    set_block_timestamp(current_round.get_auction_end_date());
    set_contract_address(bystander());
    self.vault_dispatcher.end_auction()
}

// Jump to the option expriry date and settle the round
fn timeskip_and_settle_round(ref self: VaultFacade, job_request: JobRequest) -> u256 {
    let current_round_id = self.get_current_round_id();
    if current_round_id.is_non_zero() {
        let mut current_round = self.get_current_round();
        set_block_timestamp(current_round.get_option_settlement_date());
    }
    set_contract_address(bystander());
    self.settle_option_round(job_request)
}

