use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};

use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};
use pitch_lake_starknet::{
    eth::Eth, option_round::{OptionRoundState},
    tests::{
        utils::{
            event_helpers::{assert_event_transfer, pop_log, assert_no_events_left},
            test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
            },
            variables::{decimals}, setup::{setup_facade},
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
        },
    }
};
use debug::PrintTrait;


#[test]
#[available_gas(10000000)]
fn test_current_round_id_is_zero() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let mut next_round_facade: OptionRoundFacade = vault_facade.get_next_round();
    assert(vault_facade.get_current_round_id() == 0, 'current round should be 0');
    assert(
        current_round_facade.get_state() == OptionRoundState::Settled,
        'current round should be settled'
    );
    assert(next_round_facade.get_state() == OptionRoundState::Open, 'next round should be open');
}
// Test that deposits always go into the next round


