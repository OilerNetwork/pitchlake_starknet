//use array::ArrayTrait;
//use debug::PrintTrait;
//use option::OptionTrait;
//use openzeppelin::token::erc20::interface::{
//    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
//    IERC20SafeDispatcherTrait,
//};
//use result::ResultTrait;
//use starknet::{
//    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
//    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
//    testing::{set_block_timestamp, set_contract_address}
//};
//
//use starknet::contract_address::ContractAddressZeroable;
//use openzeppelin::utils::serde::SerializedAppend;
//
//use traits::Into;
//use traits::TryInto;
//use pitch_lake_starknet::eth::Eth;
//use pitch_lake_starknet::tests::vault_facade::{VaultFacade, VaultFacadeTrait};
//use pitch_lake_starknet::tests::option_round_facade::{
//    OptionRoundFacade, OptionRoundFacadeTrait, OptionRoundParams
//};
//use pitch_lake_starknet::tests::utils;
//use pitch_lake_starknet::tests::utils::{
//    setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
//    assert_event_transfer, timestamp_start_month, timestamp_end_month, liquidity_provider_1,
//    liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
//    option_bidder_buyer_4, zero_address, vault_manager, weth_owner, option_round_contract_address,
//    mock_option_params, pop_log, assert_no_events_left,
//};
//use pitch_lake_starknet::tests::vault::utils::{accelerate_to_auctioning};
//
//
//// @note Add event tests once we settle on 1 or 2 withdraw functions see withdraw_tests.cairo for more info
//
//// Test eth transfer when LP withdraws from their next round deposit
//#[test]
//#[available_gas(10000000)]
//fn test_withdraw_from_deposits_eth_transfer() {
//    let (mut vault_facade, eth_dispatcher) = setup_facade();
//    // Accelerate to current round auctioning
//    accelerate_to_auctioning(ref vault_facade);
//    // Make bids
//    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
//    let _params: OptionRoundParams = current_round_facade.get_params();
//    // Current round (auctioning) and next round (open)
//    let mut current_round = vault_facade.get_current_round();
//    let mut next_round = vault_facade.get_next_round();
//    // Initital eth balances for lp, current round, next round
//    let init_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
//    let init_current_round_balance = eth_dispatcher.balance_of(current_round.contract_address());
//    let init_next_round_balance = eth_dispatcher.balance_of(next_round.contract_address());
//    // Withdraw from next round deposit
//    let withdraw_amount = 1;
//    vault_facade.withdraw(withdraw_amount, liquidity_provider_1());
//    // Final eth balances for lp, current round, next round
//    let final_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
//    let final_current_round_balance = eth_dispatcher.balance_of(current_round.contract_address());
//    let final_next_round_balance = eth_dispatcher.balance_of(next_round.contract_address());
//    // Check liquidity changes
//    assert(final_lp_balance == init_lp_balance + withdraw_amount, 'lp shd receive eth');
//    assert(final_current_round_balance == init_current_round_balance, 'current eth shd be locked');
//    assert(
//        final_next_round_balance == init_next_round_balance - withdraw_amount, 'next shd send eth'
//    );
//    assert_event_transfer(
//        eth_dispatcher.contract_address,
//        next_round.contract_address(),
//        liquidity_provider_1(),
//        withdraw_amount
//    );
//}
//
//// Test collateral/unallocated amounts when LP withdraws from their next round deposit
//// @note add assertion that vault::round_positions[lp, next_id] decrements (need to add vault entry point for get_lp_deposit_in_round)
//#[test]
//#[available_gas(10000000)]
//fn test_withdraw_from_deposits_updates_collateral_and_unallocated() {
//    let (mut vault_facade, _) = setup_facade();
//    // Accelerate to round 1 running
//    accelerate_to_auctioning(ref vault_facade);
//    // Make bids
//    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
//    let _params: OptionRoundParams = current_round_facade.get_params();
//    // Current round (auctioning), next round (open)
//    let mut current_round = vault_facade.get_current_round();
//    let mut next_round = vault_facade.get_next_round();
//    // Initial collateral/unallocated
//    let (init_lp_collateral, init_lp_unallocated) = vault_facade
//        .get_lp_balance_spread(liquidity_provider_1());
//    let (init_current_round_collateral, init_current_round_unallocated) = current_round
//        .get_all_round_liquidity();
//    let (init_next_round_collateral, init_next_round_unallocated) = next_round
//        .get_all_round_liquidity();
//    // Withdraw from next round deposit
//    let withdraw_amount = 1;
//    vault_facade.withdraw(withdraw_amount, liquidity_provider_1());
//    // Final collateral/unallocated
//    let (final_lp_collateral, final_lp_unallocated) = vault_facade
//        .get_lp_balance_spread(liquidity_provider_1());
//    let (final_current_round_collateral, final_current_round_unallocated) = current_round
//        .get_all_round_liquidity();
//    let (final_next_round_collateral, final_next_round_unallocated) = next_round
//        .get_all_round_liquidity();
//    // Check collateral is untouched
//    assert(final_lp_collateral == init_lp_collateral, 'lp collateral wrong');
//    assert(
//        final_current_round_collateral == init_current_round_collateral,
//        'current round collateral wrong'
//    );
//    assert(
//        final_next_round_collateral == init_next_round_collateral, 'next round collateral wrong'
//    );
//    // Check unallocated is updated
//    assert(final_lp_unallocated == init_lp_unallocated - withdraw_amount, 'lp unallocated wrong');
//    assert(
//        final_current_round_unallocated == init_current_round_unallocated,
//        'current round unallocated wrong'
//    );
//    assert(
//        final_next_round_unallocated == init_next_round_unallocated - withdraw_amount,
//        'next round unallocated wrong'
//    );
//}
//


