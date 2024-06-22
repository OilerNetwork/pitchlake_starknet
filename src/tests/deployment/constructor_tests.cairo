use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcherTrait,
};
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall, SyscallResult,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use pitch_lake_starknet::{
    contracts::{
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
    },
    tests::{
        utils::{
            helpers::{
                setup::{setup_facade},
                event_helpers::{
                    assert_event_auction_start, assert_event_auction_end, assert_event_option_settle
                },
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled
                },
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


/// @note Important update to lifecycle
// Previously, the current round was either auctioning/running/settled, and the next round was always open. Updating when the auction starts
// Since liquidity is held by the vault, the round does not need to deploy until the current one settles
// Therefore, the new lifecylce is: At deployment, the current round is 1 and it is open. Once round 1 settles, round 2 becomes the new current round
// and is open until the auction starts
// Making it so that the current round is either open/auctioning/running. Once it settles we update the current round, and shortly after (after rtp)
// does the auction start

/// Constructor Tests ///

// Test the vault deploys with the current round 1, and the vault manager is set
// vault manager is set
#[test]
#[available_gas(10000000)]
fn test_vault_constructor() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let current_round_id = vault.get_current_round_id();

    // Check current round is 1
    assert(current_round_id == 1, 'current round should be 1');
    // Check current round is open
    assert(current_round.get_state() == OptionRoundState::Open, 'current round should be Open');
    // Test vault constructor values
    assert(vault.get_vault_manager() == vault_manager(), 'vault manager incorrect');
}


// Test each time an option round is deployed its constructor params are correct
// @note Settling the round will deploy the next round and make it the current
#[test]
#[available_gas(10000000)]
fn test_option_round_constructor() {
    let (mut vault, _) = setup_facade();
    let mut i: u32 = 3;
    while i > 0 {
        let mut current_round = vault.get_current_round();
        let mut args = OptionRoundConstructorParams {
            vault_address: vault.contract_address(), round_id: 1
        };

        // Check the current round arg's and state are correct
        assert(current_round.get_constructor_params() == args, 'round construcutor params wrong');
        assert(current_round.get_state() == OptionRoundState::Open, 'round init state wrong');

        accelerate_to_auctioning(ref vault);
        accelerate_to_running(ref vault);
        accelerate_to_settled(ref vault, current_round.get_strike_price());
        args.round_id += 1;
        i -= 1;
    }
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

