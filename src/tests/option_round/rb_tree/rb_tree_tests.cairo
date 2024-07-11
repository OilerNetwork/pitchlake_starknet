use pitch_lake_starknet::{
    tests::option_round::rb_tree::rb_tree_mock_contract::RBTreeMockContract,
    contracts::option_round::OptionRound::Bid
};
use starknet::{deploy_syscall, SyscallResultTrait, contract_address_const, ContractAddress };

#[starknet::interface]
pub trait IRBTree<TContractState> {
    fn insert(ref self: TContractState, value: Bid) -> felt252;
    fn get_nonce(ref self: TContractState) -> u64;
    fn get_tree_structure(ref self: TContractState) -> Array<Array<(u256, bool, u128)>>;
    fn is_tree_valid(ref self: TContractState) -> bool;
    fn delete(ref self: TContractState, bid_id: felt252);
    fn get_bid(ref self: TContractState, bid_id: felt252) -> Bid;
}

fn setup_rb_tree() -> IRBTreeDispatcher {
    let (address, _) = deploy_syscall(
        RBTreeMockContract::TEST_CLASS_HASH.try_into().unwrap(), 0, array![].span(), false
    )
        .unwrap_syscall();
    IRBTreeDispatcher { contract_address: address }
}

fn mock_address(value: felt252) -> ContractAddress {
    contract_address_const::<'liquidity_provider_1'>()
}

// Tests for insertion

#[test]
fn test_insert_into_empty_tree() {
    let rb_tree = setup_rb_tree();

    let node_2_id = insert(rb_tree, 2, 1);
    let node_1_id = insert(rb_tree, 1, 2);
    let node_4_id = insert(rb_tree, 4, 3);
    let node_5_id = insert(rb_tree, 5, 4);
    let node_9_id = insert(rb_tree, 9, 5);
    let node_3_id = insert(rb_tree, 3, 6);
    let node_6_id = insert(rb_tree, 6, 7);
    let node_7_id = insert(rb_tree, 7, 8);
    let node_15_id = insert(rb_tree, 15, 9);

    // Positive tests

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    let node_2 = rb_tree.get_bid(node_2_id);
    assert(node_2.price == 2, 'Node 2 price mismatch');

    let node_1 = rb_tree.get_bid(node_1_id);
    assert(node_1.price == 1, 'Node 1 price mismatch');

    let node_4 = rb_tree.get_bid(node_4_id);
    assert(node_4.price == 4, 'Node 4 price mismatch');
    
    let node_5 = rb_tree.get_bid(node_5_id);
    assert(node_5.price == 5, 'Node 5 price mismatch');

    let node_9 = rb_tree.get_bid(node_9_id);
    assert(node_9.price == 9, 'Node 9 price mismatch');

    let node_3 = rb_tree.get_bid(node_3_id);
    assert(node_3.price == 3, 'Node 3 price mismatch');

    let node_6 = rb_tree.get_bid(node_6_id);
    assert(node_6.price == 6, 'Node 6 price mismatch');

    let node_7 = rb_tree.get_bid(node_7_id);
    assert(node_7.price == 7, 'Node 7 price mismatch');

    let node_15 = rb_tree.get_bid(node_15_id);
    assert(node_15.price == 15, 'Node 15 price mismatch');

    let tree = rb_tree.get_tree_structure();
    let expected_tree_structure = array![
        array![(5, false, 0)],
        array![(2, true, 0), (7, true, 1)],
        array![(1, false, 0), (4, false, 1), (6, false, 2), (9, false, 3)],
        array![(3, true, 2), (15, true, 7)]
    ];
    compare_tree_structures(@tree, @expected_tree_structure);
    
    // Negative tests

    let node_10 = rb_tree.get_bid(10);
    assert(node_10.price == 0, 'Node 10 should not exist');

    let node_11 = rb_tree.get_bid(11);
    assert(node_11.price == 0, 'Node 11 should not exist');

    let node_12 = rb_tree.get_bid(12);
    assert(node_12.price == 0, 'Node 12 should not exist');
}

// #[test]
// fn test_insertion() {
//     let rb_tree = setup_rb_tree();
    
//     insert(rb_tree, 2, 1);
//     let tree_structure = rb_tree.get_tree_structure();
//     let tree_with_root_node = array![
//         array![(2, false, 0)]
//     ];
//     compare_tree_structures(@tree_structure, @tree_with_root_node);

//     insert(rb_tree, 1, 2);
//     let tree_with_left_node = array![
//         array![(2, false, 0)],
//         array![(1, true, 0)]
//     ];
//     let tree_structure = rb_tree.get_tree_structure();
//     compare_tree_structures(@tree_structure, @tree_with_left_node);
    
//     insert(rb_tree, 4, 3);
//     let tree_with_right_node = array![
//         array![(2, false, 0)],
//         array![(1, true, 0)],
//         array![(4, true, 0)]
//     ];
//     let tree_structure = rb_tree.get_tree_structure();
//     compare_tree_structures(@tree_structure, @tree_with_right_node);
//     let is_tree_valid = rb_tree.is_tree_valid();
//     assert(is_tree_valid, 'Tree is not valid');

//     insert(rb_tree, 5, 4);
//     let tree_after_recolor_parents = array![
//         array![(2, false, 0)],
//         array![(1, false, 0), (4, false, 1)],
//         array![(5, true, 3)]
//     ];
//     let tree_structure = rb_tree.get_tree_structure();
//     compare_tree_structures(@tree_structure, @tree_after_recolor_parents);
//     let is_tree_valid = rb_tree.is_tree_valid();
//     assert(is_tree_valid, 'Tree is not valid');

//     insert(rb_tree, 9, 5);
//     let tree_after_left_rotation = array![
//         array![(2, false, 0)],
//         array![(1, false, 0), (5, false, 1)],
//         array![(4, true, 2), (9, true, 3)]
//     ];
//     let tree_structure = rb_tree.get_tree_structure();
//     compare_tree_structures(@tree_structure, @tree_after_left_rotation);
//     let is_tree_valid = rb_tree.is_tree_valid();
//     assert(is_tree_valid, 'Tree is not valid');

//     insert(rb_tree, 3, 6);
//     let tree_after_recolor = array![
//         array![(2, false, 0)],
//         array![(1, false, 0), (5, true, 1)],
//         array![(4, false, 2), (9, false, 3)],
//         array![(3, true, 4)],
//     ];
//     let tree_structure = rb_tree.get_tree_structure();
//     compare_tree_structures(@tree_structure, @tree_after_recolor);
//     let is_tree_valid = rb_tree.is_tree_valid();
//     assert(is_tree_valid, 'Tree is not valid');

//     insert(rb_tree, 6, 7);
//     let tree_after_insertion = array![
//         array![(2, false, 0)],
//         array![(1, false, 0), (5, true, 1)],
//         array![(4, false, 2), (9, false, 3)],
//         array![(3, true, 4), (6, true, 6)],
//     ];
//     let tree_structure = rb_tree.get_tree_structure();
//     compare_tree_structures(@tree_structure, @tree_after_insertion);
//     let is_tree_valid = rb_tree.is_tree_valid();
//     assert(is_tree_valid, 'Tree is not valid');

//     insert(rb_tree, 7, 8);
//     let tree_structure = rb_tree.get_tree_structure();
//     let tree_after_left_right_rotation_recolor = array![
//         array![(2, false, 0)],
//         array![(1, false, 0), (5, true, 1)],
//         array![(4, false, 2), (7, false, 3)],
//         array![(3, true, 4), (6, true, 6), (9, true, 7)],
//     ];
//     compare_tree_structures(@tree_structure, @tree_after_left_right_rotation_recolor);
//     let is_tree_valid = rb_tree.is_tree_valid();
//     assert(is_tree_valid, 'Tree is not valid');

//     insert(rb_tree, 15, 9);
//     let tree_structure = rb_tree.get_tree_structure();
//     let tree_after_recolor = array![
//         array![(5, false, 0)],
//         array![(2, true, 0), (7, true, 1)],
//         array![(1, false, 0), (4, false, 1), (6, false, 2), (9, false, 3)],
//         array![(3, true, 2), (15, true, 7)],
//     ];
//     compare_tree_structures(@tree_structure, @tree_after_recolor);
//     let is_tree_valid = rb_tree.is_tree_valid();
//     assert(is_tree_valid, 'Tree is not valid');
// }

// Tests for deletion


// #[test]
// fn test_deletion() {
//     let rb_tree = setup_rb_tree();

//     let node_90 = insert(rb_tree, 90, 1);
//     let node_70 = insert(rb_tree, 70, 2);
//     let node_43 = insert(rb_tree, 43, 3); 
//     delete(rb_tree, node_70);
//     insert(rb_tree, 24, 4);
//     insert(rb_tree, 14, 5);
//     insert(rb_tree, 93, 6);
//     let node_47 = insert(rb_tree, 47, 7);
//     delete(rb_tree, node_47);
//     delete(rb_tree, node_90);
//     insert(rb_tree, 57, 8);
//     let node_1 = insert(rb_tree, 1, 9);
//     insert(rb_tree, 60, 10);  
//     let node_47 =  insert(rb_tree, 47, 11);
//     delete(rb_tree, node_47);
//     delete(rb_tree, node_1);
//     delete(rb_tree, node_90);
//     delete(rb_tree, node_43);
//     insert(rb_tree, 49, 12);

//     let final_tree = rb_tree.get_tree_structure();
//     let expected_tree_structure = array![
//         array![(57, false, 0)],
//         array![(24, false, 0), (60, false, 1)],
//         array![(14, true, 0), (49, true, 1), (93, true, 3)]
//     ];
//     compare_tree_structures(@final_tree, @expected_tree_structure);
//     let is_tree_valid = rb_tree.is_tree_valid();
//     assert(is_tree_valid, 'Tree is not valid');
// }

// Test Utilities

fn insert(rb_tree: IRBTreeDispatcher, price: u256, nonce: u64) -> felt252 {
    let bidder = mock_address(123456);
    let id = poseidon::poseidon_hash_span(
        array![bidder.into(), nonce.try_into().unwrap()].span()
    );
    rb_tree.insert(Bid { 
        id: id,
        nonce: nonce,
        owner: bidder,
        amount: 0,
        price: price,
        is_tokenized: false,
        is_refunded: false,
    })
}

fn is_tree_valid(rb_tree: IRBTreeDispatcher) {
    let is_tree_valid = rb_tree.is_tree_valid();
    println!("Is tree valid: {:?}", is_tree_valid);
}

fn delete(rb_tree: IRBTreeDispatcher, bid_id: felt252) {
    rb_tree.delete(bid_id);
}

fn compare_tree_structures(
    actual: @Array<Array<(u256, bool, u128)>>,
    expected: @Array<Array<(u256, bool, u128)>>
) {
    if actual.len() != expected.len() {
        return;
    }

    let mut i = 0;    
    
    // Compare outer array
    while i < actual.len() {
        let actual_inner = actual[i];
        let expected_inner = expected[i];
        compare_inner(actual_inner, expected_inner);
        i += 1;
    }                      
}

fn compare_inner(
    actual: @Array<(u256, bool, u128)>,
    expected: @Array<(u256, bool, u128)>
) {
    if actual.len() != expected.len() {
        return;
    }

    let mut i = 0;

    while i < actual.len() {
        let actual_tuple = *actual[i];
        let expected_tuple = *expected[i];
        compare_tuple(actual_tuple, expected_tuple);
        i += 1;
    }
}

fn compare_tuple(
    actual: (u256, bool, u128),
    expected: (u256, bool, u128)
) {
    let (actual_price, actual_color, actual_position) = actual;
    let (expected_price, expected_color, expected_position) = expected;

    assert(actual_price == expected_price, 'Price mismatch');
    assert(actual_color == expected_color, 'Color mismatch');
    assert(actual_position == expected_position, 'Position mismatch');

    return;
}