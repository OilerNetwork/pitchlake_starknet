use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::option_round::{OptionRoundState};

use result::ResultTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};

use starknet::contract_address::ContractAddressZeroable;
use openzeppelin::utils::serde::SerializedAppend;

use traits::Into;
use traits::TryInto;
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};
use pitch_lake_starknet::tests::utils;
use pitch_lake_starknet::tests::utils::{
    setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    assert_event_transfer, timestamp_start_month, timestamp_end_month, liquidity_provider_1,
    liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
    option_bidder_buyer_4, zero_address, vault_manager, weth_owner, option_round_contract_address,
    mock_option_params, pop_log, assert_no_events_left
};

// Accelerate the current round by starting its auction
// @dev Deposits 100 ETH as liquidity provider 1
// Accelerate to the current round auctioning (needs non 0 liquidity to start auction)
fn accelerate_to_auctioning(ref self: VaultFacade) {
    // Deposit liquidity so round 1's auction can start
    self.deposit(100 * decimals(), liquidity_provider_1());
    // Start round 1's auction
    self.start_auction();
}

// Accelerate the current round by ending its auction
// @dev Bids for all options at reserve price
// @dev Starts the round's auction if it hasn't yet
fn accelerate_to_running(ref self: VaultFacade) {
    // If the current round is not auctioning yet, start its auction first
    let mut current_round = self.get_current_round();
    if (current_round.get_state() != OptionRoundState::Auctioning) {
        accelerate_to_auctioning(ref self);
    }
    // Bid for all options at reserve price
    let mut current_round = self.get_current_round();
    let params = current_round.get_params();
    let bid_amount = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_amount = bid_amount * bid_price;
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    self.end_auction();
}

