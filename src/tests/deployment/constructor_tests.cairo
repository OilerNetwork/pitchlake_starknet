//use openzeppelin_token::erc20::interface::{ERC20ABIDispatcherTrait,};
use starknet::ContractAddress;
use pitch_lake::{
    library::eth::Eth,
    vault::{
        contract::Vault,
        interface::{
            IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, IVaultSafeDispatcherTrait
        }
    },
    option_round::{
        //contract::{OptionRound,},
        interface::{OptionRoundState, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,},
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
            lib::{variables::{decimals}, //            test_accounts::{
            //                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
            //                option_bidder_buyer_2
            //            },
            }
        },
    },
};
use debug::PrintTrait;


/// Constructor Tests ///

#[test]
#[available_gas(50000000)]
fn test_vault_constructor() {
    let (mut vault, eth) = setup_facade();
    let mut current_round = vault.get_current_round();
    let current_round_id = vault.get_current_round_id();

    // Check current round is 1
    assert(current_round_id == 1, 'current round should be 1');
    // Check current round is open and next round is settled
    assert(current_round.get_state() == OptionRoundState::Open, 'next round should be Open');
    // Test vault constructor values
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
    assert_eq!(current_round.decimals(), 0);

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
