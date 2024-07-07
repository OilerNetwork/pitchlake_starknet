use starknet::{get_block_timestamp, testing::{set_contract_address, set_block_timestamp}};
use pitch_lake_starknet::{
    contracts::{option_round::{StartAuctionParams}},
    tests::{
        utils::{
            helpers::{
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_running_custom
                },
                setup::{setup_facade},
            },
            lib::{
                test_accounts::{
                    liquidity_provider_1, option_bidder_buyer_1, option_bidder_buyer_2,
                    option_bidder_buyer_3, option_bidder_buyer_4, option_bidders_get,
                },
                variables::{decimals},
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait, OptionRoundParams},
            },
        },
    }
};

const salt: u64 = 0x123;

// Test that only the vault can start an auction
#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('todo', 'ENTRYPOINT_FAILED'))]
fn test_only_vault_can_start_auction() {
    let (mut vault, _) = setup_facade();
    set_block_timestamp(get_block_timestamp() + salt);
    let (mut other_vault, _) = setup_facade();
    let mut round_to_start = vault.get_current_round();
    vault.deposit(100 * decimals(), liquidity_provider_1());

    set_contract_address(other_vault.contract_address());

    round_to_start
        .start_auction(
            StartAuctionParams {
                total_options_available: 1,
                starting_liquidity: 1,
                reserve_price: 123,
                cap_level: 123,
                strike_price: 123,
            }
        );
}

// @note Modify to check the Result of the function to be Result::Err(e)
// Test that only the vault can end an auction
#[test]
#[available_gas(50000000)]
fn test_only_vault_can_end_auction() {
    let (mut vault, _) = setup_facade();
    set_block_timestamp(get_block_timestamp() + salt);
    let (mut other_vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();

    current_round
        .place_bid(100 * decimals(), current_round.get_reserve_price(), option_bidder_buyer_1());
    set_block_timestamp(current_round.get_auction_end_date() + 1);
    set_contract_address(other_vault.contract_address());
    current_round.end_auction();
}

// Test that only the vault can settle an option round
#[test]
#[available_gas(50000000)]
fn test_only_vault_can_settle_option_round() {
    let (mut vault, _) = setup_facade();
    set_block_timestamp(get_block_timestamp() + salt);
    let (mut other_vault, _) = setup_facade();

    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    let mut current_round = vault.get_current_round();

    set_block_timestamp(current_round.get_option_expiry_date());
    set_contract_address(other_vault.contract_address());
    current_round.settle_option_round(0x123);
}

