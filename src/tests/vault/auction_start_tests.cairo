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
use pitch_lake_starknet::option_round::{
    OptionRoundParams, IOptionRoundDispatcher, IOptionRoundDispatcherTrait
};

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
    vault_manager, weth_owner, mock_option_params
};
use pitch_lake_starknet::tests::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};


// Test that round's unallocated liquidity becomes collateral when auction start (multiple LPs)
// Test that a round & LP's unallocated update when the auction starts
#[test]
#[available_gas(10000000)]
fn test_unallocated_becomes_collateral() {
    let (mut vault_facade, _) = setup_facade();
    // Get next round (open)
    let mut next_round: OptionRoundFacade = vault_facade.get_current_round();
    // Add liq. to next round (1)
    let deposit_amount_wei_1 = 1000 * decimals();
    let deposit_amount_wei_2 = 10000 * decimals();
    let deposit_total = deposit_amount_wei_1 + deposit_amount_wei_2;
    vault_facade.deposit(deposit_amount_wei_1, liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei_2, liquidity_provider_2());
    // Initial collateral/unallocated 
    let (lp1_collateral, lp1_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_1());
    let (lp2_collateral, lp2_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_2());
    let (next_round_collateral, next_round_unallocated) = next_round.get_all_round_liquidity();
    let next_round_total_liquidity = next_round.total_liquidity();
    // Check initial spread
    assert(lp1_collateral == 0, 'lp1 collateral wrong');
    assert(lp2_collateral == 0, 'lp2 collateral wrong');
    assert(next_round_collateral == 0, 'next round collateral wrong');
    assert(next_round_total_liquidity == 0, 'next round total liq. wrong');
    assert(lp1_unallocated == deposit_amount_wei_1, 'lp1 unallocated wrong');
    assert(lp2_unallocated == deposit_amount_wei_2, 'lp2 unallocated wrong');
    assert(next_round_unallocated == deposit_total, 'next round unallocated wrong');
    // Start the auction
    vault_facade.start_auction();
    // Final collaterla/unallocated spread
    let (lp1_collateral, lp1_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_1());
    let (lp2_collateral, lp2_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_2());
    let (next_round_collateral, next_round_unallocated) = next_round.get_all_round_liquidity();
    let next_round_total_liquidity = next_round.total_liquidity();
    // Check final spread
    assert(lp1_collateral == deposit_amount_wei_1, 'lp1 collateral wrong');
    assert(lp2_collateral == deposit_amount_wei_2, 'lp2 collateral wrong');
    assert(next_round_collateral == deposit_total, 'next round collateral wrong');
    assert(next_round_total_liquidity == deposit_total, 'next round total liq. wrong');
    assert(lp1_unallocated == 0, 'lp1 unallocated wrong');
    assert(lp2_unallocated == 0, 'lp2 unallocated wrong');
    assert(next_round_unallocated == 0, 'next round unallocated wrong');
}

