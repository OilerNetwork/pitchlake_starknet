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
        OptionRoundState, OptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait
    },
    market_aggregator::{
        IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait,
        IMarketAggregatorSafeDispatcher, IMarketAggregatorSafeDispatcherTrait
    },
    tests::{
        mocks::mock_market_aggregator::{
            MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
            IMarketAggregatorSetterDispatcherTrait
        },
        vault_facade::VaultFacadeTrait,
        option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
        utils_new::{
            event_helpers::{
                assert_event_auction_start, assert_event_auction_end, assert_event_option_settle
            },
            test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2,
            },
            variables::{vault_manager, decimals}, setup::{setup_facade},
        },
    },
};
use debug::PrintTrait;

/// These tests deal with the lifecycle of an option round, from deployment to settlement ///

/// Constructor Tests ///

// @note move this to vault/deployment_tests
// Test the vault's constructor
#[test]
#[available_gas(10000000)]
fn test_vault_constructor() {
    let (mut vault_facade, _) = setup_facade();
    let current_round_id = vault_facade.current_option_round_id();
    let next_round_id = current_round_id + 1;
    // Test vault constructor values
    assert(
        vault_facade.vault_dispatcher.vault_manager() == vault_manager(), 'vault manager incorrect'
    );
    assert(current_round_id == 0, 'current round should be 0');
    assert(next_round_id == 1, 'next round should be 1');
}

// Test the option round constructor
// Test that round 0 deploys as settled, and round 1 deploys as open.
#[test]
#[available_gas(10000000)]
fn test_option_round_constructor() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let mut next_round_facade: OptionRoundFacade = vault_facade.get_next_round();
    // Round 0 should be settled
    let mut state: OptionRoundState = current_round_facade.get_state();
    let mut expected: OptionRoundState = OptionRoundState::Settled;
    assert(expected == state, 'round 0 should be Settled');
    // Round 1 should be Open
    state = next_round_facade.get_state();
    expected = OptionRoundState::Open;
    assert(expected == state, 'round 1 should be Open');
    // The round's vault & market aggregator addresses should be set
    assert(
        current_round_facade.vault_address() == vault_facade.contract_address(),
        'vault address should be set'
    );
    assert(
        next_round_facade.vault_address() == vault_facade.contract_address(),
        'vault address should be set'
    );
}

// Test market aggregator is deployed
#[test]
#[available_gas(10000000)]
fn test_market_aggregator_deployed() {
    let (mut vault_facade, _) = setup_facade();
    // Get market aggregator dispatcher
    let mkt_agg = IMarketAggregatorDispatcher {
        contract_address: vault_facade.get_market_aggregator()
    };

    // Entry point will fail if contract not deployed
    assert(vault_facade.get_market_aggregator_value() == 0, 'avg basefee shd be 0');
}
