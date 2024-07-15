use pitch_lake_starknet::tests::utils::facades::option_round_facade::OptionRoundFacadeTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}, contract_address::ContractAddressZeroable
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcherTrait,};

use pitch_lake_starknet::{
    contracts::{
        components::eth::Eth,
        pitch_lake::{
            IPitchLakeDispatcher, IPitchLakeSafeDispatcher, IPitchLakeDispatcherTrait, PitchLake,
            IPitchLakeSafeDispatcherTrait
        },
        vault::{
            contract::Vault, interface::{IVaultDispatcher, IVaultDispatcherTrait}, types::VaultType
        },
        option_round::interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait},
    },
    tests::{
        utils::{
            helpers::{
                setup::{decimals, deploy_vault, deploy_pitch_lake},
                event_helpers::{pop_log, assert_no_events_left},
            },
            lib::test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4, bystander,
            },
            facades::{
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeImpl},
                vault_facade::{VaultFacade, VaultFacadeTrait}
            },
        },
    },
};
use debug::PrintTrait;

// @note Need to manually initialize round 1, either
// upon vault deployment (constructor) or through a one-time round 1 initializer entry point
// @note Add test that all rounds, r > 1 are initialized automatically once
// the round (r-1) settles

// Test that the strike price is set correctly based on the vault type
#[test]
#[available_gas(50000000)]
fn test_strike_price_based_on_vault_types() {
    // Deploy pitch lake
    let pitch_lake_dispatcher: IPitchLakeDispatcher = deploy_pitch_lake();
    // Fetch vaults as facades
    let mut vault_dispatcher_at_the_money = VaultFacade {
        vault_dispatcher: pitch_lake_dispatcher.at_the_money_vault()
    };
    let mut vault_dispatcher_in_the_money = VaultFacade {
        vault_dispatcher: pitch_lake_dispatcher.in_the_money_vault()
    };
    let mut vault_dispatcher_out_the_money = VaultFacade {
        vault_dispatcher: pitch_lake_dispatcher.out_the_money_vault()
    };

    // LP deposits into each round 1 because a round cannot start auctioning without liquidity
    let deposit_amount_wei: u256 = 100 * decimals();
    vault_dispatcher_at_the_money.deposit(deposit_amount_wei, liquidity_provider_1());
    vault_dispatcher_in_the_money.deposit(deposit_amount_wei, liquidity_provider_1());
    vault_dispatcher_out_the_money.deposit(deposit_amount_wei, liquidity_provider_1());

    // Get each round 1 dispatcher
    let mut atm = vault_dispatcher_at_the_money.get_current_round();
    let mut itm = vault_dispatcher_in_the_money.get_current_round();
    let mut otm = vault_dispatcher_out_the_money.get_current_round();

    // Check the strike price of each vault's round 1
    let atm_strike_price = atm.get_strike_price();
    let itm_strike_price = itm.get_strike_price();
    let otm_strike_price = otm.get_strike_price();
    let atm_avg_basefee = atm.get_current_average_basefee();
    let itm_avg_basefee = itm.get_current_average_basefee();
    let otm_avg_basefee = otm.get_current_average_basefee();

    assert(atm_strike_price == atm_avg_basefee, 'ATM stike wrong');
    assert(itm_strike_price > itm_avg_basefee, 'ITM stike wrong');
    assert(otm_strike_price < otm_avg_basefee, 'OTM stike wrong');
}
// @note Add tests for other init params. Reserve price, cap levels etc.
// @note Add test that option round params are logical (auction start time < auction end time < option settlement time)


