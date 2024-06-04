use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcherTrait,
};
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall, SyscallResult,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use pitch_lake_starknet::{
    eth::Eth,
    vault::{
        IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault,
        IVaultSafeDispatcherTrait
    },
    option_round::{
        OptionRoundState, OptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,
        OptionRoundConstructorParams,
    },
    market_aggregator::{
        IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait,
        IMarketAggregatorSafeDispatcher, IMarketAggregatorSafeDispatcherTrait
    },
    tests::{
        utils::{
            event_helpers::{
                assert_event_auction_start, assert_event_auction_end, assert_event_option_settle
            },
            test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2,
            },
            variables::{vault_manager, decimals}, setup::{setup_facade},
            facades::{
                vault_facade::VaultFacadeTrait,
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
            mocks::mock_market_aggregator::{
                MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
                IMarketAggregatorSetterDispatcherTrait
            },
        },
    },
};
use debug::PrintTrait;


/// Constructor Tests ///
// These tests deal with the lifecycle of an option round, from deployment to settlement

// Test the vault deploys with current round 0 (settled), next round 1 (open),
// vault manager is set
#[test]
#[available_gas(10000000)]
fn test_vault_constructor() {
    let (mut vault, _) = setup_facade();
    let (mut current_round, mut next_round) = vault.get_current_and_next_rounds();
    let current_round_id = vault.get_current_round_id();

    // Check current round is 0
    assert(current_round_id == 0, 'current round should be 0');
    // Check current round is open and next round is settled
    assert(
        current_round.get_state() == OptionRoundState::Settled, 'current round should be Settled'
    );
    assert(next_round.get_state() == OptionRoundState::Open, 'next round should be Open');
    // Test vault constructor values
    assert(vault.get_vault_manager() == vault_manager(), 'vault manager incorrect');
}


// Test the option round constructor
// Test that round 0 deploys as settled, and round 1 deploys as open.
#[test]
#[available_gas(10000000)]
fn test_option_round_constructor() {
    let (mut vault, _) = setup_facade();
    let mut args = OptionRoundConstructorParams {
        vault_address: vault.contract_address(), round_id: 0
    };

    let (mut r0, mut r1) = vault.get_current_and_next_rounds();
    assert(r0.get_constructor_params() == args, 'r0 construcutor params wrong');
    args.round_id += 1;
    assert(r1.get_constructor_params() == args, 'r1 construcutor params wrong');
}


// Test market aggregator is deployed
// @note Need make sure mock has both setter & getter implementations
#[test]
#[available_gas(10000000)]
fn test_market_aggregator_deployed() {
    let (mut vault_facade, _) = setup_facade();
    // Get market aggregator dispatcher
    let _mkt_agg = IMarketAggregatorDispatcher {
        contract_address: vault_facade.get_market_aggregator()
    };

    // Entry point will fail if contract not deployed
    assert(vault_facade.get_market_aggregator_value() == 0, 'avg basefee shd be 0');
}

