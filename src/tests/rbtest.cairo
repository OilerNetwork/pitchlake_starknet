use pitch_lake_starknet::contracts::{
    option_round::{OptionRound, Bid}, utils::rbtree::IRedBlackTreeDispatcherTrait
};
use pitch_lake_starknet::tests::{
    utils::{
        lib::test_accounts::{liquidity_provider_1, liquidity_provider_2, liquidity_provider_3},
        helpers::setup::{deploy_rbtree}
    }
};
#[test]
#[available_gas(10000000)]
fn test_update_bids_price_cannot_be_decreased_event_if_amount_is_increased() {
    let mut rbtree = deploy_rbtree();
    rbtree.insert(Bid { id: '1', owner: liquidity_provider_1(), amount: 1, price: 1, valid: true });
    rbtree.insert(Bid { id: '2', owner: liquidity_provider_2(), amount: 2, price: 1, valid: true });
    rbtree.insert(Bid { id: '2', owner: liquidity_provider_3(), amount: 1, price: 3, valid: true });
    rbtree.insert(Bid { id: '2', owner: liquidity_provider_1(), amount: 2, price: 1, valid: true });
    rbtree.insert(Bid { id: '2', owner: liquidity_provider_2(), amount: 1, price: 1, valid: true });
}

