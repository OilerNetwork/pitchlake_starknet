use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait,
    VaultType
};
use pitch_lake_starknet::option_round::{
    OptionRoundParams, IOptionRoundDispatcher, IOptionRoundDispatcherTrait
};
use pitch_lake_starknet::pitch_lake::{
    IPitchLakeDispatcher, IPitchLakeSafeDispatcher, IPitchLakeDispatcherTrait, PitchLake,
    IPitchLakeSafeDispatcherTrait
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
use pitch_lake_starknet::tests::utils;
use pitch_lake_starknet::tests::utils::{
    setup, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    vault_manager, weth_owner, option_round_contract_address, mock_option_params, pop_log,
    assert_no_events_left, deploy_pitch_lake
};

// @note Need to manually initialize round 1, either 
// upon vault deployment (constructor) or through a one-time round 1 initializer entry point
// @note Add test that all rounds, r > 1 are initialized automatically once 
// the round (r-1) settles

// Test that the strik price is set correctly based on the vault type
#[test]
#[available_gas(10000000)]
fn test_strike_price_based_on_vault_types() {
    // Deploy pitch lake
    let pitch_lake_dispatcher: IPitchLakeDispatcher = deploy_pitch_lake();
    // Deploy vaults
    let vault_dispatcher_at_the_money: IVaultDispatcher = pitch_lake_dispatcher
        .at_the_money_vault();
    let vault_dispatcher_in_the_money: IVaultDispatcher = pitch_lake_dispatcher
        .in_the_money_vault();
    let vault_dispatcher_out_the_money: IVaultDispatcher = pitch_lake_dispatcher
        .out_the_money_vault();

    // LP deposits (into each round 1) (cannot initialize round params if there is no liquidity)
    let deposit_amount_wei: u256 = 100 * decimals();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher_at_the_money.deposit_liquidity(deposit_amount_wei);
    vault_dispatcher_in_the_money.deposit_liquidity(deposit_amount_wei);
    vault_dispatcher_out_the_money.deposit_liquidity(deposit_amount_wei);

    // Vaults deploy with current -> 0: Settled, and next -> 1: Open,
    // In all future rounds, when the current round settles, the next is initialized 
    // The next round must be initialized inorder for its auction to start 
    // This means r1 will need to be manually initialized before its auction, then
    // all following rounds will be automatically initialized when the current one settles. 

    // @note Need to initialize r1 manually, then start the auction.

    // let id, params = vault.initialize_first_round();

    // Get each round 1 dispatcher
    let atm: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher_at_the_money
            .get_option_round_address(vault_dispatcher_at_the_money.current_option_round_id() + 1)
    };
    let itm: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher_in_the_money
            .get_option_round_address(vault_dispatcher_in_the_money.current_option_round_id() + 1)
    };
    let otm: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher_out_the_money
            .get_option_round_address(vault_dispatcher_out_the_money.current_option_round_id() + 1)
    };
    // Get each round's params
    let atm_params: OptionRoundParams = atm.get_params();
    let itm_params: OptionRoundParams = itm.get_params();
    let otm_params: OptionRoundParams = otm.get_params();
    // Check the strike price of each vault's round 1
    assert(atm_params.strike_price == atm_params.current_average_basefee, 'ATM stike wrong');
    assert(itm_params.strike_price > itm_params.current_average_basefee, 'ITM stike wrong');
    assert(otm_params.strike_price < otm_params.current_average_basefee, 'OTM stike wrong');
}

// @note Add tests for other init params. Reserve price, cap levels etc.
// @note Add test that option round params are logical (auction start time < auction end time < option settlement time)



