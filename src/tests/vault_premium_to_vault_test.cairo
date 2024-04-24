use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait
};
use pitch_lake_starknet::option_round::{OptionRoundParams};

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
use pitch_lake_starknet::tests::utils::{
    setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    vault_manager, weth_owner, mock_option_params, assert_event_option_amount_transfer
};
use pitch_lake_starknet::tests::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};
use pitch_lake_starknet::option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};

// @note move to vault/auction_end tests
// collateral balance of should be vault::get_unlocked_liquidity_for()
// @note Add test that unlocked is premium after auction, and is premium + next position if there is a deposit, and is premium + unsold options if there is any
#[test]
#[available_gas(10000000)]
fn test_premium_collection_ratio_conversion_unallocated_pool_1() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round.get_params();
    // Deposit liquidity
    let deposit_amount_wei_1: u256 = 1000 * decimals();
    let deposit_amount_wei_2: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei_1, liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei_2, liquidity_provider_2());
    // Make bid (ob1)
    let bid_amount: u256 = params.total_options_available;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_amount * bid_price;
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    current_round.end_auction();

    // Premium comes from unallocated pool
    let total_collateral: u256 = current_round.total_collateral();
    let total_premium_to_be_paid: u256 = current_round.get_auction_clearing_price()
        * current_round.total_options_sold();
    // LP % of the round
    let ratio_of_liquidity_provider_1: u256 = (vault_facade
        .get_collateral_balance_for(liquidity_provider_1())
        * 100)
        / total_collateral;
    let ratio_of_liquidity_provider_2: u256 = (vault_facade
        .get_collateral_balance_for(liquidity_provider_2())
        * 100)
        / total_collateral;
    // LP premiums share
    let premium_for_liquidity_provider_1: u256 = (ratio_of_liquidity_provider_1
        * total_premium_to_be_paid)
        / 100;
    let premium_for_liquidity_provider_2: u256 = (ratio_of_liquidity_provider_2
        * total_premium_to_be_paid)
        / 100;
    // The actual unallocated balance of the LPs
    let actual_unallocated_balance_provider_1: u256 = vault_facade
        .get_unallocated_balance_for(liquidity_provider_1());
    let actual_unallocated_balance_provider_2: u256 = vault_facade
        .get_unallocated_balance_for(liquidity_provider_2());

    assert(
        actual_unallocated_balance_provider_1 == premium_for_liquidity_provider_1,
        'premium paid in ratio'
    );
    assert(
        actual_unallocated_balance_provider_2 == premium_for_liquidity_provider_2,
        'premium paid in ratio'
    );
}

// @note move to vault/auction_end tests
#[test]
#[available_gas(10000000)]
fn test_premium_collection_ratio_conversion_unallocated_pool_2() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round.get_params();
    // Deposit liquidity
    let deposit_amount_wei_1: u256 = 1000 * decimals();
    vault_facade.deposit(deposit_amount_wei_1, liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei_1, liquidity_provider_2());
    // Make bid
    let bid_amount_user_1: u256 = ((params.total_options_available / 2) + 1) * params.reserve_price;
    let bid_amount_user_2: u256 = (params.total_options_available / 2) * params.reserve_price;
    current_round.place_bid(bid_amount_user_1, params.reserve_price, option_bidder_buyer_1());
    current_round.place_bid(bid_amount_user_2, params.reserve_price, option_bidder_buyer_2());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    current_round.end_auction();
    // Premium comes from unallocated pool
    let total_collateral: u256 = current_round.total_collateral();
    let total_premium_to_be_paid: u256 = current_round.get_auction_clearing_price()
        * current_round.total_options_sold();
    // LP % of the round
    let ratio_of_liquidity_provider_1: u256 = (vault_facade
        .get_collateral_balance_for(liquidity_provider_1())
        * 100)
        / total_collateral;
    let ratio_of_liquidity_provider_2: u256 = (vault_facade
        .get_collateral_balance_for(liquidity_provider_2())
        * 100)
        / total_collateral;
    // LP premiums share
    let premium_for_liquidity_provider_1: u256 = (ratio_of_liquidity_provider_1
        * total_premium_to_be_paid)
        / 100;
    let premium_for_liquidity_provider_2: u256 = (ratio_of_liquidity_provider_2
        * total_premium_to_be_paid)
        / 100;
    // The actual unallocated balance of the LPs
    let actual_unallocated_balance_provider_1: u256 = vault_facade
        .get_unallocated_balance_for(liquidity_provider_1());
    let actual_unallocated_balance_provider_2: u256 = vault_facade
        .get_unallocated_balance_for(liquidity_provider_2());

    assert(
        actual_unallocated_balance_provider_1 == premium_for_liquidity_provider_1,
        'premium paid in ratio'
    );
    assert(
        actual_unallocated_balance_provider_2 == premium_for_liquidity_provider_2,
        'premium paid in ratio'
    );
}

