use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait,
    OptionRoundCreated
};
use pitch_lake_starknet::option_round::{OptionRoundParams};

use result::ResultTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};

use pitch_lake_starknet::tests::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};
use starknet::contract_address::ContractAddressZeroable;
use openzeppelin::utils::serde::SerializedAppend;

use traits::Into;
use traits::TryInto;
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{
    setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    zero_address, vault_manager, weth_owner, option_round_contract_address, mock_option_params,
    pop_log, assert_no_events_left, month_duration
};
use pitch_lake_starknet::option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};
use pitch_lake_starknet::tests::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait
};

// @note Add (or move in) test that checks LP's unallocated & next round's unallocated increment 
//
//
// @note round & lp liquity spread update
//

// Test auction cannot end if it has not started
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot end auction before it starts', 'ENTRYPOINT_FAILED'))]
fn test_auction_end_before_start_failure() {
    let (mut vault_facade, _) = setup_facade();
    // OptionRoundDispatcher
    let mut next_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = next_round.get_params();

    // Add liq. to next round
    let deposit_amount_wei = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());

    // Try to end auction before it starts 
    set_block_timestamp(params.option_expiry_time + 1);
    vault_facade.settle_option_round(liquidity_provider_1());
}

// Test auction cannot end before the auction end date 
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'Auction cannot settle before due time',))]
fn test_auction_end_before_end_date_failure() {
    let (mut vault_facade, _) = setup_facade();
    // Add liq. to current round
    // note Why some deposits are by option_bidder
    let deposit_amount_wei = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, option_bidder_buyer_1());

    // Start the auction
    vault_facade.start_auction();

    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = current_round.get_params();

    // Try to end auction before the end time
    set_block_timestamp(params.auction_end_time - 1);
    current_round.end_auction();
}
