use pitch_lake_starknet::tests::{
    utils::{
        accelerators::{accelerate_to_auctioning,}, test_accounts::{option_bidders_get},
        variables::{decimals}, setup::{setup_facade},
        facades::{
            vault_facade::{VaultFacade, VaultFacadeTrait},
            option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}
        },
        utils::{get_erc20_balances, get_erc20_balance, scale_array, sum_u256_array},
    },
};
#[test]
#[available_gas(10000000)]
fn test_update_bids_cannot_be_lower() {
    let (mut vault_facade, eth) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Eth balances before bid
    let mut obs = option_bidders_get(3).span();
    let scale = array![1, 2, 3].span();
    let mut ob_balances_before = get_erc20_balances(eth.contract_address, obs).span();
    let round_balance_before = get_erc20_balance(
        eth.contract_address, current_round.contract_address()
    );
    // Place bids
    let bid_prices = scale_array(scale, reserve_price).span();
    let mut bid_amounts = scale_array(bid_prices, options_available).span();
    let bid_total = sum_u256_array(bid_amounts);
    current_round.place_bids(bid_amounts, bid_prices, obs);
    // Eth balances after bid
    let mut ob_balances_after = get_erc20_balances(eth.contract_address, obs).span();
    let round_balance_after = get_erc20_balance(
        eth.contract_address, current_round.contract_address()
    );

    // Check round balance
    assert(round_balance_after == round_balance_before + bid_total, 'round balance after wrong');
    // Check ob balances
    loop {
        match ob_balances_before.pop_front() {
            Option::Some(ob_balance_before) => {
                let ob_bid_amount = bid_amounts.pop_front().unwrap();
                let ob_balance_after = ob_balances_after.pop_front().unwrap();
                assert(
                    *ob_balance_after == *ob_balance_before - *ob_bid_amount,
                    'ob balance after wrong'
                );
            },
            Option::None => { break; }
        };
    }
}
