use openzeppelin::token::erc20::interface::{ERC20ABIDispatcherTrait,};
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall, SyscallResult,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use pitch_lake_starknet::{
    library::eth::Eth, types::{OptionRoundState, OptionRoundConstructorParams},
    vault::{
        contract::Vault,
        interface::{
            IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, IVaultSafeDispatcherTrait
        }
    },
    option_round::{
        contract::{OptionRound,}, interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait,},
    },
    contracts::{
        market_aggregator::{
            IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait,
            IMarketAggregatorSafeDispatcher, IMarketAggregatorSafeDispatcherTrait
        },
    },
    tests::{
        utils::{
            helpers::{
                setup::{setup_facade},
                event_helpers::{
                    assert_event_auction_start, assert_event_auction_end, assert_event_option_settle
                }
            },
            facades::{
                vault_facade::VaultFacadeTrait,
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
            mocks::mock_market_aggregator::{
                MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
                IMarketAggregatorSetterDispatcherTrait
            },
            lib::{
                variables::{decimals},
                test_accounts::{
                    liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                    option_bidder_buyer_2, vault_manager
                },
            }
        },
    },
};
use debug::PrintTrait;


/// Constructor Tests ///
// These tests deal with the lifecycle of an option round, from deployment to settlement

// Test the vault deploys with current round 0 (settled), next round 1 (open),
// vault manager is set
#[test]
#[available_gas(50000000)]
fn test_vault_constructor() {
    let (mut vault, eth) = setup_facade();
    let mut current_round = vault.get_current_round();
    let current_round_id = vault.get_current_round_id();

    // Constructor args
    assert_eq!(vault.get_round_transition_period(), 'rtp'.try_into().unwrap());
    assert_eq!(vault.get_auction_run_time(), 'art'.try_into().unwrap());
    assert_eq!(vault.get_option_run_time(), 'ort'.try_into().unwrap());
    assert_eq!(vault.get_cap_level(), 10000);

    // Check current round is 1
    assert(current_round_id == 1, 'current round should be 1');
    // Check current round is open and next round is settled
    assert(current_round.get_state() == OptionRoundState::Open, 'next round should be Open');
    // Test vault constructor values
    assert(vault.get_vault_manager() == vault_manager(), 'vault manager incorrect');
    assert(vault.get_eth_address() == eth.contract_address, 'eth address incorrect');
}


// Test the option round constructor
// Test that round 0 deploys as settled, and round 1 deploys as open.
#[test]
#[available_gas(50000000)]
fn test_option_round_constructor() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();

    // Test constructor args
    assert_eq!(current_round.name(), "Pitch Lake Option Round 1");
    assert_eq!(current_round.symbol(), "PLOR1");
    assert_eq!(current_round.decimals(), 6);

    assert_eq!(current_round.vault_address(), vault.contract_address());
    assert_eq!(current_round.get_round_id(), 1);

    // Get time params
    let now = starknet::get_block_timestamp();
    let (auction_run_time, option_run_time, round_transition_period) = {
        (
            vault.get_auction_run_time(),
            vault.get_option_run_time(),
            vault.get_round_transition_period()
        )
    };

    let auction_start_date = now + round_transition_period;
    let auction_end_date = auction_start_date + auction_run_time;
    let option_settlement_date = auction_end_date + option_run_time;

    assert_eq!(current_round.get_auction_start_date(), auction_start_date);
    assert_eq!(current_round.get_auction_end_date(), auction_end_date);
    assert_eq!(current_round.get_option_settlement_date(), option_settlement_date);

    assert!(current_round.get_state() == OptionRoundState::Open, "state does not match");
// Test reserve price, cap level, strike price
// - might need to deploy a custom option round for this
}


// Test market aggregator is deployed
// @note Need make sure mock has both setter & getter implementations
#[test]
#[available_gas(50000000)]
fn test_market_aggregator_deployed() {
    let (mut vault_facade, _) = setup_facade();
    // Get market aggregator dispatcher
    let _mkt_agg = IMarketAggregatorDispatcher {
        contract_address: vault_facade.get_market_aggregator()
    };

    // Entry point will fail if contract not deployed
    assert(vault_facade.get_market_aggregator_value() == 0, 'avg basefee shd be 0');
}

