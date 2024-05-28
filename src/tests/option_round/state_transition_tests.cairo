use pitch_lake_starknet::{
    tests::{
        vault_facade::{VaultFacade, VaultFacadeTrait},
        option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait, OptionRoundParams},
        utils::{
            setup_facade, decimals, liquidity_provider_1, option_bidder_buyer_1,
            option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
            accelerate_to_running, accelerate_to_running_custom, option_bidders_get
        },
        vault::utils::{accelerate_to_auctioning}
    }
};
use starknet::{get_block_timestamp, testing::{set_contract_address, set_block_timestamp}};

// @note Modify to check the Result of the function to be Result::Err(e)
// Test that only the vault can start an auction
#[test]
#[available_gas(100000000)]
fn test_only_vault_can_start_auction() {
    let (mut vault, _) = setup_facade();
    let mut next_round = vault.get_next_round();
    vault.deposit(100 * decimals(), liquidity_provider_1());

    set_contract_address(liquidity_provider_1());
    next_round.start_auction();

    // Should run fine
    set_contract_address(vault.contract_address());
    next_round.start_auction();
}

// @note Modify to check the Result of the function to be Result::Err(e)
// Test that only the vault can end an auction
#[test]
#[available_gas(100000000)]
fn test_only_vault_can_end_auction() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();

    current_round
        .place_bid(100 * decimals(), current_round.get_reserve_price(), option_bidder_buyer_1());
    set_block_timestamp(current_round.get_auction_end_date() + 1);
    set_contract_address(liquidity_provider_1());
    current_round.end_auction();

    // Should run fine
    set_contract_address(vault.contract_address());
    current_round.end_auction();
}

// @note Modify to check the Result of the function to be Result::Err(e)
// Test that only the vault can settle an option round
#[test]
#[available_gas(100000000)]
fn test_only_vault_can_settle_option_round() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    let mut current_round = vault.get_current_round();

    set_block_timestamp(current_round.get_option_expiry_date());
    set_contract_address(liquidity_provider_1());
    current_round.settle_option_round(0x123);

    // Should run fine
    set_contract_address(vault.contract_address());
    current_round.settle_option_round(0x123);
}

