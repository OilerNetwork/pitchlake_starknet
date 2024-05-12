// use array::ArrayTrait;
// use debug::PrintTrait;
// use option::OptionTrait;
// use openzeppelin::token::erc20::interface::{
//     IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
//     IERC20SafeDispatcherTrait,
// };
// use pitch_lake_starknet::option_round::{OptionRoundParams};

// use result::ResultTrait;
// use starknet::{
//     ClassHash, ContractAddress, contract_address_const, deploy_syscall,
//     Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
//     testing::{set_block_timestamp, set_contract_address}
// };

use starknet::testing::{set_block_timestamp, set_contract_address};
// use starknet::contract_address::ContractAddressZeroable;
// use openzeppelin::utils::serde::SerializedAppend;

// use traits::Into;
// use traits::TryInto;
// use pitch_lake_starknet::eth::Eth;

use pitch_lake_starknet::tests::{
    option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
    vault_facade::{VaultFacade, VaultFacadeTrait},
    mocks::{
        mock_market_aggregator::{
            MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
            IMarketAggregatorSetterDispatcherTrait
        }
    },
    vault::utils::{accelerate_to_running}
};
use pitch_lake_starknet::tests::utils::{
    setup_facade, liquidity_provider_1, liquidity_provider_2, liquidity_provider_3,
    liquidity_provider_4, decimals, option_bidder_buyer_1, option_bidder_buyer_2
};


// Test the portion of premiums an LP can collect in a round is correct
#[test]
#[available_gas(10000000)]
fn test_premium_amount_for_liquidity_providers_1() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity
    let deposit_amount_wei_1: u256 = 1000 * decimals();
    let deposit_amount_wei_2: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei_1, liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei_2, liquidity_provider_2());
    vault_facade.start_auction();
    // End auction, minting all options at reserve price
    accelerate_to_running(ref vault_facade);
    // Get the premiums collectable for lp1 & lp2
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let total_collateral_in_pool: u256 = deposit_amount_wei_1 + deposit_amount_wei_2;
    let total_premium: u256 = current_round.get_auction_clearing_price()
        * current_round.total_options_sold();
    let lp1_expected_premium = (deposit_amount_wei_1 * total_premium) / total_collateral_in_pool;
    let lp2_expected_premium = (deposit_amount_wei_2 * total_premium) / total_collateral_in_pool;

    let lp1_actual_premium: u256 = vault_facade.get_unallocated_balance_for(liquidity_provider_1());
    let lp2_actual_premium: u256 = vault_facade.get_unallocated_balance_for(liquidity_provider_2());
    // Check LP portion is correct
    assert(lp1_actual_premium == lp1_expected_premium, 'lp1 collectable premium wrong');
    assert(lp2_actual_premium == lp2_expected_premium, 'lp2 collectable premium wrong');
}

// Test the portion of premiums an LP can collect in a round is correct (more LPs)
#[test]
#[available_gas(10000000)]
fn test_premium_amount_for_liquidity_providers_2() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity
    let deposit_amount_wei_1: u256 = 250 * decimals();
    let deposit_amount_wei_2: u256 = 500 * decimals();
    let deposit_amount_wei_3: u256 = 1000 * decimals();
    let deposit_amount_wei_4: u256 = 1500 * decimals();
    vault_facade.deposit(deposit_amount_wei_1, liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei_2, liquidity_provider_2());
    vault_facade.deposit(deposit_amount_wei_3, liquidity_provider_3());
    vault_facade.deposit(deposit_amount_wei_4, liquidity_provider_4());
    vault_facade.start_auction();
    // End auction, minting all options at reserve price
    accelerate_to_running(ref vault_facade);
    // Get the premiums collectable for lp1 & lp2
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let total_collateral_in_pool: u256 = deposit_amount_wei_1
        + deposit_amount_wei_2
        + deposit_amount_wei_3
        + deposit_amount_wei_4;
    let total_premium: u256 = current_round.get_auction_clearing_price()
        * current_round.total_options_sold();
    let lp1_expected_premium = (deposit_amount_wei_1 * total_premium) / total_collateral_in_pool;
    let lp2_expected_premium = (deposit_amount_wei_2 * total_premium) / total_collateral_in_pool;
    let lp3_expected_premium = (deposit_amount_wei_3 * total_premium) / total_collateral_in_pool;
    let lp4_expected_premium = (deposit_amount_wei_4 * total_premium) / total_collateral_in_pool;

    let lp1_actual_premium: u256 = vault_facade.get_unallocated_balance_for(liquidity_provider_1());
    let lp2_actual_premium: u256 = vault_facade.get_unallocated_balance_for(liquidity_provider_2());
    let lp3_actual_premium: u256 = vault_facade.get_unallocated_balance_for(liquidity_provider_3());
    let lp4_actual_premium: u256 = vault_facade.get_unallocated_balance_for(liquidity_provider_4());
    // Check LP portion is correct
    assert(lp1_actual_premium == lp1_expected_premium, 'lp1 collectable premium wrong');
    assert(lp2_actual_premium == lp2_expected_premium, 'lp2 collectable premium wrong');
    assert(lp3_actual_premium == lp3_expected_premium, 'lp3 collectable premium wrong');
    assert(lp4_actual_premium == lp4_expected_premium, 'lp4 collectable premium wrong');
}

// @note Need tests for premium collection: eth transfer, lp/round unallocated decrementing, remaining premiums for other LPs unaffected, cannot collect twice/more than remaining collectable amount


