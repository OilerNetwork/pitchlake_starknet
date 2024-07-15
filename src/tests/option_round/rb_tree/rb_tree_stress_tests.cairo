use pitch_lake_starknet::{
    tests::{
        utils::helpers::setup::setup_rb_tree_test,
        option_round::rb_tree::rb_tree_tests::IRBTreeDispatcher,
    },
    contracts::option_round::types::Bid,
};

#[test]
#[available_gas(50000000000)]
#[ignore]
fn test_add_1_to_100_delete_100_to_1() {
    let rb_tree: IRBTreeDispatcher = setup_rb_tree_test();
    rb_tree.get_tree_structure();
}