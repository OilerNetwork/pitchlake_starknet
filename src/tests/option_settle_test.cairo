use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
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
use pitch_lake_starknet::tests::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};
use pitch_lake_starknet::tests::{
    utils::{
        setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
        timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
        option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
        vault_manager, weth_owner, mock_option_params, assert_event_transfer
    },
};
use pitch_lake_starknet::tests::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait
};
// @note move to option_round/payout_tests

// @note move to vault/option_settle_test

// @note move to vault/option_settle_tests

// @note move to vault/option_settle_tests

// @note Add test that payout is capped even if index >>> strike
// @note add test that unallocated decrements when round settles (premiums + unsold were rolled over)
// @note add test that eth transfers to next round on settlement


