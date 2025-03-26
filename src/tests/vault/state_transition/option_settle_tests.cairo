use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}, contract_address::ContractAddressZeroable,
};
use openzeppelin_utils::serde::SerializedAppend;
use openzeppelin_token::erc20::interface::ERC20ABIDispatcherTrait;
use pitch_lake::{
    library::{eth::Eth},
    vault::{
        contract::Vault,
        interface::{
            IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, IVaultSafeDispatcherTrait
        }
    },
    option_round::contract::OptionRound::Errors, option_round::interface::PricingData,
    tests::{
        utils::{
            helpers::{
                general_helpers::{
                    get_portion_of_amount, create_array_linear, create_array_gradient,
                    get_erc20_balances, sum_u256_array,
                },
                event_helpers::{
                    clear_event_logs, assert_event_option_settle, assert_event_transfer,
                    assert_no_events_left, pop_log, assert_event_option_round_deployed_single,
                    assert_event_option_round_deployed,
                },
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled,
                    accelerate_to_auctioning_custom, accelerate_to_running_custom
                },
                setup::{
                    deploy_vault_with_events, setup_facade, setup_test_auctioning_providers,
                    setup_test_running, AUCTION_DURATION, ROUND_TRANSITION_DURATION, ROUND_DURATION
                },
                fossil_client_helpers::{
                    get_mock_result_serialized, get_mock_result, get_request, get_request_serialized
                }
            },
            lib::{
                test_accounts::{
                    liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                    option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                    liquidity_providers_get, liquidity_provider_3, liquidity_provider_4,
                },
                variables::{decimals},
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                fossil_client_facade::{FossilClientFacade, FossilClientFacadeTrait},
                option_round_facade::{OptionRoundState, OptionRoundFacade, OptionRoundFacadeTrait},
            },
        },
    }
};
use debug::PrintTrait;
use crate::tests::utils::helpers::setup::FOSSIL_PROCESSOR;


/// Failures ///

// Test settling an option round while round auctioning fails
#[test]
#[available_gas(50000000)]
fn test_settling_option_round_while_round_auctioning_fails() {
    let (mut vault_facade, _) = setup_facade();

    accelerate_to_auctioning(ref vault_facade);

    // Settle option round before auction ends
    // vault_facade.settle_option_round_expect_error(Errors::OptionSettlementDateNotReached);
    let request = get_request_serialized(ref vault_facade);
    let mut result = get_mock_result_serialized();
    set_contract_address(FOSSIL_PROCESSOR());
    vault_facade
        .get_fossil_client_facade()
        .fossil_callback_expect_error(request, result, Errors::OptionSettlementDateNotReached);
}

// Test settling an option round before the option expiry date fails
#[test]
#[available_gas(50000000)]
fn test_settling_option_round_before_settlement_date_fails() {
    let (mut vault_facade, _) = setup_test_running();

    // Settle option round before expiry
    // vault_facade.settle_option_round_expect_error(Errors::OptionSettlementDateNotReached);
    let request = get_request_serialized(ref vault_facade);
    let mut result = get_mock_result_serialized();
    set_contract_address(FOSSIL_PROCESSOR());
    vault_facade
        .get_fossil_client_facade()
        .fossil_callback_expect_error(request, result, Errors::OptionSettlementDateNotReached);
}

// Test settling an option round while round settled fails
#[test]
#[available_gas(50000000)]
fn test_settling_option_round_while_settled_fails() {
    let (mut vault_facade, _) = setup_facade();
    accelerate_to_auctioning(ref vault_facade);
    accelerate_to_running(ref vault_facade);
    accelerate_to_settled(ref vault_facade, 0x123);

    // Settle option round after it has already settled
    // vault_facade.settle_option_round_expect_error(Errors::OptionRoundAlreadySettled);
    let request = get_request_serialized(ref vault_facade);
    let mut result = get_mock_result_serialized();
    set_contract_address(FOSSIL_PROCESSOR());
    vault_facade
        .get_fossil_client_facade()
        .fossil_callback_expect_error(request, result, Errors::OptionRoundAlreadySettled);
}

/// Event Tests ///

// Test settling an option round emits the correct event
#[test]
#[available_gas(5000000000)]
fn test_option_round_settled_event() {
    let mut rounds_to_run = 3;
    let (mut vault, _) = setup_facade();

    while rounds_to_run > 0_u32 {
        accelerate_to_auctioning(ref vault);
        accelerate_to_running(ref vault);

        let mut round = vault.get_current_round();
        let settlement_price = round.get_strike_price() + rounds_to_run.into();
        let total_payout = accelerate_to_settled(ref vault, settlement_price);
        let payout_per_option = total_payout / round.total_options_sold();

        // Check the event emits correctly
        assert_event_option_settle(
            vault.contract_address(),
            settlement_price,
            payout_per_option,
            round.get_round_id(),
            round.contract_address()
        );

        rounds_to_run -= 1;
    }
}

#[test]
#[available_gas(500000000)]
fn test_first_round_deployed_event() {
    set_block_timestamp(123);
    let vault_dispatcher = deploy_vault_with_events(2222, 9999, contract_address_const::<'eth'>());
    let mut vault = VaultFacade { vault_dispatcher };
    let mut current_round = vault.get_current_round();

    let exp_deployment_date = get_block_timestamp();
    let exp_auction_start_date = exp_deployment_date + ROUND_TRANSITION_DURATION;
    let exp_auction_end_date = exp_auction_start_date + AUCTION_DURATION;
    let exp_option_settlement_date = exp_auction_end_date + ROUND_DURATION;

    assert_event_option_round_deployed_single(
        vault.contract_address(),
        1,
        current_round.contract_address(),
        exp_auction_start_date,
        exp_auction_end_date,
        exp_option_settlement_date,
        pricing_data: PricingData { strike_price: 0, cap_level: 0, reserve_price: 0 }
    );

    assert_eq!(current_round.get_deployment_date(), exp_deployment_date);
    assert_eq!(current_round.get_auction_start_date(), exp_auction_start_date);
    assert_eq!(current_round.get_auction_end_date(), exp_auction_end_date);
    assert_eq!(current_round.get_option_settlement_date(), exp_option_settlement_date);
}

// Test every time a new round is deployed, the next round deployed event emits correctly
// @dev The first round to be deployed after deployment is round 2
#[test]
#[available_gas(500000000)]
fn test_next_round_deployed_events() {
    let (mut vault, _) = setup_facade();

    for i in 1_u64
        ..4 {
            let mut round_i = vault.get_current_round();
            accelerate_to_auctioning(ref vault);
            accelerate_to_running(ref vault);
            clear_event_logs(array![vault.contract_address()]);
            accelerate_to_settled(ref vault, round_i.get_strike_price());

            let mut round_i_plus_1 = vault.get_current_round();
            let auction_start_date = round_i_plus_1.get_auction_start_date();
            let auction_end_date = round_i_plus_1.get_auction_end_date();
            let settlement_date = round_i_plus_1.get_option_settlement_date();

            // Check new round is deployed
            assert(i + 1 == round_i_plus_1.get_round_id(), 'round contract address wrong');

            // Check the event emits correctly
            let pricing_data = PricingData {
                strike_price: round_i_plus_1.get_strike_price(),
                cap_level: round_i_plus_1.get_cap_level(),
                reserve_price: round_i_plus_1.get_reserve_price()
            };

            assert(pricing_data != Default::default(), 'Pricing data not set correctly');
            assert_event_option_round_deployed(
                vault.contract_address(),
                i + 1,
                round_i_plus_1.contract_address(),
                auction_start_date,
                auction_end_date,
                settlement_date,
                pricing_data
            );
        }
}


/// State Tests ///

/// Round ids/states

// Test settling an option round updates the current round id
#[test]
#[available_gas(500000000)]
fn test_settling_option_round_updates_current_round_id() {
    let mut rounds_to_run = 3;
    let (mut vault, _) = setup_facade();

    while rounds_to_run > 0_u32 {
        accelerate_to_auctioning(ref vault);
        accelerate_to_running(ref vault);

        let current_round_id = vault.get_current_round_id();
        accelerate_to_settled(ref vault, 123);

        let new_current_round_id = vault.get_current_round_id();

        assert(new_current_round_id == current_round_id + 1, 'current round id wrong');

        rounds_to_run -= 1;
    }
}

// Test settling an option round updates the current round's state
// @note should this be a state transition test in option round tests
#[test]
#[available_gas(500000000)]
fn test_settle_option_round_updates_round_state() {
    let mut rounds_to_run = 3;
    let (mut vault, _) = setup_facade();

    while rounds_to_run > 0_u32 {
        accelerate_to_auctioning(ref vault);
        accelerate_to_running(ref vault);
        let mut current_round = vault.get_current_round();

        assert(
            current_round.get_state() == OptionRoundState::Running, 'current round shd be running'
        );

        //accelerate_to_settled(ref vault, 0);
        accelerate_to_settled(ref vault, current_round.get_strike_price());

        assert(
            current_round.get_state() == OptionRoundState::Settled, 'current round shd be settled'
        );

        rounds_to_run -= 1;
    }
}

/// Liquidity

// Test settling transfers the payout from the vault to the option round
#[test]
#[available_gas(90000000)]
fn test_settling_option_round_transfers_payout() {
    let mut rounds_to_run = 3;
    let (mut vault, eth) = setup_facade();

    while rounds_to_run > 0_u32 {
        accelerate_to_auctioning(ref vault);
        accelerate_to_running(ref vault);

        // Vault and round eth balances before the round settles
        let mut current_round = vault.get_current_round();
        let round_balance_before = eth.balance_of(current_round.contract_address());
        let vault_balance_before = eth.balance_of(vault.contract_address());

        // Settle the round with a payout
        let total_payout = accelerate_to_settled(ref vault, 2 * current_round.get_strike_price());

        // Vault and round eth balances after auction ends
        let round_balance_after = eth.balance_of(current_round.contract_address());
        let vault_balance_after = eth.balance_of(vault.contract_address());

        // Check the payout transfers from vault to round
        assert(total_payout > 0, 'payout shd be > 0');
        assert(round_balance_after == round_balance_before + total_payout, 'round eth bal. wrong');
        assert(vault_balance_after == vault_balance_before - total_payout, 'vault eth bal. wrong');

        rounds_to_run -= 1;
    }
}

// Test that the vault and LP locked/unlocked balances update when the round settles
#[test]
#[available_gas(500000000)]
fn test_settling_option_round_updates_locked_and_unlocked_balances() {
    let number_of_liquidity_providers = 4;
    let mut deposit_amounts = create_array_gradient(
        100 * decimals(), 100 * decimals(), number_of_liquidity_providers
    )
        .span();
    //    let total_deposits = sum_u256_array(deposit_amounts);
    let (mut vault, _, liquidity_providers, _) = setup_test_auctioning_providers(
        number_of_liquidity_providers, deposit_amounts
    );
    let mut current_round = vault.get_current_round();

    // End auction
    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
    let total_premiums = options_sold * clearing_price;
    //    let mut liquidity_provider_premiums = get_portion_of_amount(deposit_amounts,
    //    total_premiums)
    //        .span();
    let sold_liq = current_round.sold_liquidity();
    let unsold_liq = current_round.unsold_liquidity();
    let total_liq = sold_liq + unsold_liq;

    // Vault and liquidity provider balances before auction starts
    let mut liquidity_providers_locked_before = vault.get_lp_locked_balances(liquidity_providers);
    let mut liquidity_providers_unlocked_before = vault
        .get_lp_unlocked_balances(liquidity_providers);
    let (vault_locked_before, vault_unlocked_before) = vault
        .get_total_locked_and_unlocked_balance();

    // Settle the round with a payout
    let total_payouts = accelerate_to_settled(ref vault, 2 * current_round.get_strike_price());
    let remaining_liq = sold_liq - total_payouts;
    let gained_liq = total_premiums + unsold_liq;
    //    let mut individual_remaining_liquidty = get_portion_of_amount(
    //        deposit_amounts, remaining_liq
    //    )
    //        .span();

    // Vault and liquidity provider balances after auction starts
    let mut liquidity_providers_locked_after = vault.get_lp_locked_balances(liquidity_providers);
    let mut liquidity_providers_unlocked_after = vault
        .get_lp_unlocked_balances(liquidity_providers);
    let (vault_locked_after, vault_unlocked_after) = vault.get_total_locked_and_unlocked_balance();

    // Check vault balance
    assert(total_premiums > 0, 'premiums shd be > 0');
    assert(
        (vault_locked_before, vault_unlocked_before) == (sold_liq, gained_liq),
        'vault balance before wrong'
    );
    assert(
        (vault_locked_after, vault_unlocked_after) == (0, gained_liq + remaining_liq),
        'vault balance after wrong'
    );

    // Check liquidity provider balances
    loop {
        match liquidity_providers_locked_before.pop_front() {
            Option::Some(lp_locked_balance_before) => {
                let lp_locked_balance_after = liquidity_providers_locked_after.pop_front().unwrap();
                let lp_unlocked_balance_before = liquidity_providers_unlocked_before
                    .pop_front()
                    .unwrap();
                let lp_unlocked_balance_after = liquidity_providers_unlocked_after
                    .pop_front()
                    .unwrap();

                let lp_deposit_amount = deposit_amounts.pop_front().unwrap();

                let lp_sold_liq = (*lp_deposit_amount * sold_liq) / total_liq;
                let lp_gained_liq = (*lp_deposit_amount * gained_liq) / total_liq;
                let lp_remaining_liq = (*lp_deposit_amount * remaining_liq) / total_liq;

                //                let lp_premium = liquidity_provider_premiums.pop_front().unwrap();
                //                let lp_remaining_liquidity =
                //                individual_remaining_liquidty.pop_front().unwrap();

                assert(
                    (
                        lp_locked_balance_before, lp_unlocked_balance_before
                    ) == (lp_sold_liq, lp_gained_liq),
                    'LP balance before wrong'
                );
                assert(
                    (
                        lp_locked_balance_after, lp_unlocked_balance_after
                    ) == (0, lp_gained_liq + lp_remaining_liq),
                    'LP balance after wrong'
                );
            },
            Option::None => { break (); }
        }
    };
}

// Test settling a round with 0 starting liq
#[test]
#[available_gas(500000000)]
fn test_null_round_settling() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let liquidity_provider = liquidity_provider_1();
    let deposit_amount = 0;
    accelerate_to_auctioning_custom(
        ref vault, array![liquidity_provider].span(), array![deposit_amount].span()
    );

    let option_buyer = option_bidder_buyer_1();
    let options_available = current_round.get_total_options_available();
    let reserve_price = current_round.get_reserve_price();
    vault
        .place_bid_expect_error(
            options_available, reserve_price, option_buyer, Errors::NoOptionsToBidFor
        );

    accelerate_to_running_custom(ref vault, array![].span(), array![].span(), array![].span());

    accelerate_to_settled(ref vault, 2 * current_round.get_strike_price());
}

// Test settling a round with 0 options sold
#[test]
#[available_gas(500000000)]
fn test_no_buyers_round_settling() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);

    accelerate_to_running_custom(ref vault, array![].span(), array![].span(), array![].span());

    accelerate_to_settled(ref vault, 2 * current_round.get_strike_price());
}

