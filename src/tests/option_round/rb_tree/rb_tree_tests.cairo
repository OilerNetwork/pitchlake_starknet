use core::traits::TryInto;
use pitch_lake_starknet::{
    tests::option_round::{rb_tree::rb_tree_mock_contract::RBTreeMockContract},
    contracts::option_round::types::Bid,
};
use starknet::{ contract_address_const, ContractAddress};
use core::pedersen::pedersen;
use pitch_lake_starknet::tests::utils::helpers::setup::setup_rb_tree_test;
const BLACK: bool = false;
const RED: bool = true;

const MOCK_ADDRESS: felt252 = 123456;

#[starknet::interface]
pub trait IRBTree<TContractState> {
    fn insert(ref self: TContractState, value: Bid);
    fn find(self: @TContractState, bid_id: felt252) -> Bid;
    fn get_tree_structure(self: @TContractState) -> Array<Array<(u256, bool, u128)>>;
    fn is_tree_valid(self: @TContractState) -> bool;
    fn delete(ref self: TContractState, bid_id: felt252);
    fn add_node(ref self: TContractState, value: Bid, color: bool, parent: felt252) -> felt252;
}



fn mock_address(value: felt252) -> ContractAddress {
    contract_address_const::<'liquidity_provider_1'>()
}

// Tests for insertion

#[test]
fn test_insert_into_empty_tree() {
    let rb_tree = setup_rb_tree_test();

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

    let node_2 = rb_tree.find(node_2_id);
    assert(node_2.price == 2, 'Node 2 price mismatch');

    let node_1 = rb_tree.find(node_1_id);
    assert(node_1.price == 1, 'Node 1 price mismatch');

    let node_4 = rb_tree.find(node_4_id);
    assert(node_4.price == 4, 'Node 4 price mismatch');

    let node_5 = rb_tree.find(node_5_id);
    assert(node_5.price == 5, 'Node 5 price mismatch');

    let node_9 = rb_tree.find(node_9_id);
    assert(node_9.price == 9, 'Node 9 price mismatch');

    let node_3 = rb_tree.find(node_3_id);
    assert(node_3.price == 3, 'Node 3 price mismatch');

    let node_6 = rb_tree.find(node_6_id);
    assert(node_6.price == 6, 'Node 6 price mismatch');

    let node_7 = rb_tree.find(node_7_id);
    assert(node_7.price == 7, 'Node 7 price mismatch');

    let node_15 = rb_tree.find(node_15_id);
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

    let node_10 = rb_tree.find(10);
    assert(node_10.price == 0, 'Node 10 should not exist');

    let node_11 = rb_tree.find(11);
    assert(node_11.price == 0, 'Node 11 should not exist');

    let node_12 = rb_tree.find(12);
    assert(node_12.price == 0, 'Node 12 should not exist');
}

#[test]
#[ignore]
fn test_recoloring_only() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(31, 1);
    rb_tree.insert(new_bid);
    let node_31 = new_bid.id;

    new_bid = create_bid(11, 2);
    let node_11 = rb_tree.add_node(new_bid, RED, node_31);

    new_bid = create_bid(41, 3);
    let node_41 = rb_tree.add_node(new_bid, RED, node_31);

    new_bid = create_bid(1, 4);
    rb_tree.add_node(new_bid, BLACK, node_11);

    new_bid = create_bid(27, 5);
    let node_27 = rb_tree.add_node(new_bid, BLACK, node_11);

    new_bid = create_bid(36, 6);
    rb_tree.add_node(new_bid, BLACK, node_41);

    new_bid = create_bid(46, 7);
    rb_tree.add_node(new_bid, BLACK, node_41);

    new_bid = create_bid(23, 8);
    rb_tree.add_node(new_bid, RED, node_27);

    new_bid = create_bid(29, 9);
    rb_tree.add_node(new_bid, RED, node_27);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 25, 10);

    let tree_after_recolor = array![
        array![(31, false, 0)],
        array![(11, false, 0), (41, false, 1)],
        array![(1, false, 0), (27, true, 1), (36, false, 2), (46, false, 3)],
        array![(23, false, 2), (29, false, 3)],
        array![(25, true, 5)]
    ];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_recolor);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_recoloring_two() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(31, 1);
    rb_tree.insert(new_bid);
    let node_31 = new_bid.id;

    let new_bid = create_bid(11, 2);
    let node_11 = rb_tree.add_node(new_bid, RED, node_31);

    let new_bid = create_bid(41, 3);
    let node_41 = rb_tree.add_node(new_bid, RED, node_31);

    let new_bid = create_bid(1, 4);
    rb_tree.add_node(new_bid, BLACK, node_11);

    let new_node = create_bid(27, 5);
    rb_tree.add_node(new_node, BLACK, node_11);

    let new_bid = create_bid(36, 6);
    let node_36 = rb_tree.add_node(new_bid, BLACK, node_41);

    let new_bid = create_bid(46, 7);
    rb_tree.add_node(new_bid, BLACK, node_41);

    let new_bid = create_bid(33, 8);
    rb_tree.add_node(new_bid, RED, node_36);

    let new_bid = create_bid(38, 9);
    rb_tree.add_node(new_bid, RED, node_36);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 40, 10);

    let tree_after_recolor = array![
        array![(31, false, 0)],
        array![(11, false, 0), (41, false, 1)],
        array![(1, false, 0), (27, false, 1), (36, true, 2), (46, false, 3)],
        array![(33, false, 4), (38, false, 5)],
        array![(40, true, 11)]
    ];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_recolor);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_right_rotation() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(21, 1);
    rb_tree.insert(new_bid);
    let node_21 = new_bid.id;

    let new_bid = create_bid(1, 2);
    let node_1 = rb_tree.add_node(new_bid, BLACK, node_21);

    let new_bid = create_bid(31, 3);
    let node_31 = rb_tree.add_node(new_bid, BLACK, node_21);

    let new_bid = create_bid(18, 4);
    rb_tree.add_node(new_bid, RED, node_1);

    let new_bid = create_bid(26, 5);
    rb_tree.add_node(new_bid, RED, node_31);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 24, 6);

    let tree_after_right_rotation = array![
        array![(21, false, 0)],
        array![(1, false, 0), (26, false, 1)],
        array![(18, true, 1), (24, true, 2), (31, true, 3)]
    ];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_right_rotation);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}


#[test]
#[ignore]
fn test_left_rotation_no_sibling() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(10, 1);
    rb_tree.insert(new_bid);
    let node_10 = new_bid.id;

    let new_bid = create_bid(7, 2);
    let node_7 = rb_tree.add_node(new_bid, BLACK, node_10);

    let new_bid = create_bid(20, 3);
    rb_tree.add_node(new_bid, BLACK, node_10);

    let new_bid = create_bid(8, 4);
    rb_tree.add_node(new_bid, RED, node_7);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 9, 5);

    let tree_after_left_rotation = array![
        array![(10, false, 0)],
        array![(8, false, 0), (20, false, 1)],
        array![(7, true, 0), (9, true, 1)]
    ];

    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_left_rotation);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_right_rotation_no_sibling_left_subtree() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(23, 1);
    rb_tree.insert(new_bid);
    let node_23 = new_bid.id;

    let new_bid = create_bid(3, 2);
    let node_3 = rb_tree.add_node(new_bid, BLACK, node_23);

    let new_bid = create_bid(33, 3);
    let node_33 = rb_tree.add_node(new_bid, BLACK, node_23);

    let new_bid = create_bid(2, 4);
    rb_tree.add_node(new_bid, RED, node_3);

    let new_bid = create_bid(28, 5);
    rb_tree.add_node(new_bid, RED, node_33);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 1, 6);

    let tree = rb_tree.get_tree_structure();
    let expected_tree_structure = array![
        array![(23, false, 0)],
        array![(2, false, 0), (33, false, 1)],
        array![(1, true, 0), (3, true, 1), (28, true, 2)]
    ];
    compare_tree_structures(@tree, @expected_tree_structure);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_left_right_rotation_no_sibling() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(21, 1);
    rb_tree.insert(new_bid);
    let node_21 = new_bid.id;

    let new_bid = create_bid(1, 2);
    let node_1 = rb_tree.add_node(new_bid, BLACK, node_21);

    let new_bid = create_bid(31, 3);
    let node_31 = rb_tree.add_node(new_bid, BLACK, node_21);

    let new_bid = create_bid(18, 4);
    rb_tree.add_node(new_bid, RED, node_1);

    let new_bid = create_bid(26, 5);
    rb_tree.add_node(new_bid, RED, node_31);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 28, 6);

    let tree_after_left_right_rotation = array![
        array![(21, false, 0)],
        array![(1, false, 0), (28, false, 1)],
        array![(18, true, 1), (26, true, 2), (31, true, 3)]
    ];

    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_left_right_rotation);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}
#[test]
#[ignore]
fn test_right_left_rotation_no_sibling() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(21, 1);
    rb_tree.insert(new_bid);
    let node_21 = new_bid.id;

    let new_bid = create_bid(1, 2);
    let node_1 = rb_tree.add_node(new_bid, BLACK, node_21);

    let new_bid = create_bid(31, 3);
    let node_31 = rb_tree.add_node(new_bid, BLACK, node_21);

    let new_bid = create_bid(18, 4);
    rb_tree.add_node(new_bid, RED, node_1);

    let new_bid = create_bid(26, 5);
    rb_tree.add_node(new_bid, RED, node_31);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 13, 6);

    let result = rb_tree.get_tree_structure();
    let expected_tree_structure = array![
        array![(21, false, 0)],
        array![(13, false, 0), (31, false, 1)],
        array![(1, true, 0), (18, true, 1), (26, true, 2)]
    ];

    compare_tree_structures(@result, @expected_tree_structure);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_recolor_lr() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(31, 1);
    rb_tree.insert(new_bid);
    let node_31 = new_bid.id;

    let new_bid = create_bid(11, 2);
    let node_11 = rb_tree.add_node(new_bid, RED, node_31);

    let new_bid = create_bid(41, 3);
    let node_41 = rb_tree.add_node(new_bid, BLACK, node_31);

    let new_bid = create_bid(1, 4);
    rb_tree.add_node(new_bid, BLACK, node_11);

    let new_bid = create_bid(27, 5);
    let node_27 = rb_tree.add_node(new_bid, BLACK, node_11);

    let new_bid = create_bid(36, 6);
    rb_tree.add_node(new_bid, RED, node_41);

    let new_bid = create_bid(51, 7);
    rb_tree.add_node(new_bid, RED, node_41);

    let new_bid = create_bid(22, 8);
    rb_tree.add_node(new_bid, RED, node_27);

    let new_bid = create_bid(30, 9);
    rb_tree.add_node(new_bid, RED, node_27);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 25, 10);

    let tree_after_recolor = array![
        array![(27, false, 0)],
        array![(11, true, 0), (31, true, 1)],
        array![(1, false, 0), (22, false, 1), (30, false, 2), (41, false, 3)],
        array![(25, true, 3), (36, true, 6), (51, true, 7)]
    ];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_recolor);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
fn test_functional_test_build_tree() {
    let rb_tree = setup_rb_tree_test();

    insert(rb_tree, 2, 1);
    let tree_structure = rb_tree.get_tree_structure();
    let tree_with_root_node = array![array![(2, false, 0)]];
    compare_tree_structures(@tree_structure, @tree_with_root_node);

    insert(rb_tree, 1, 2);
    let tree_with_left_node = array![array![(2, false, 0)], array![(1, true, 0)]];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_with_left_node);

    insert(rb_tree, 4, 3);
    let tree_with_right_node = array![
        array![(2, false, 0)], array![(1, true, 0)], array![(4, true, 0)]
    ];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_with_right_node);
    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 5, 4);
    let tree_after_recolor_parents = array![
        array![(2, false, 0)], array![(1, false, 0), (4, false, 1)], array![(5, true, 3)]
    ];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_recolor_parents);
    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 9, 5);
    let tree_after_left_rotation = array![
        array![(2, false, 0)],
        array![(1, false, 0), (5, false, 1)],
        array![(4, true, 2), (9, true, 3)]
    ];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_left_rotation);
    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 3, 6);
    let tree_after_recolor = array![
        array![(2, false, 0)],
        array![(1, false, 0), (5, true, 1)],
        array![(4, false, 2), (9, false, 3)],
        array![(3, true, 4)],
    ];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_recolor);
    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 6, 7);
    let tree_after_insertion = array![
        array![(2, false, 0)],
        array![(1, false, 0), (5, true, 1)],
        array![(4, false, 2), (9, false, 3)],
        array![(3, true, 4), (6, true, 6)],
    ];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_insertion);
    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 7, 8);
    let tree_structure = rb_tree.get_tree_structure();
    let tree_after_left_right_rotation_recolor = array![
        array![(2, false, 0)],
        array![(1, false, 0), (5, true, 1)],
        array![(4, false, 2), (7, false, 3)],
        array![(3, true, 4), (6, true, 6), (9, true, 7)],
    ];
    compare_tree_structures(@tree_structure, @tree_after_left_right_rotation_recolor);
    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 15, 9);
    let tree_structure = rb_tree.get_tree_structure();
    let tree_after_recolor = array![
        array![(5, false, 0)],
        array![(2, true, 0), (7, true, 1)],
        array![(1, false, 0), (4, false, 1), (6, false, 2), (9, false, 3)],
        array![(3, true, 2), (15, true, 7)],
    ];
    compare_tree_structures(@tree_structure, @tree_after_recolor);
    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_right_left_rotation_after_recolor() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(10, 1);
    rb_tree.insert(new_bid);
    let node_10 = new_bid.id;

    let new_bid = create_bid(5, 2);
    rb_tree.add_node(new_bid, BLACK, node_10);

    let new_bid = create_bid(20, 3);
    let node_20 = rb_tree.add_node(new_bid, RED, node_10);

    let new_bid = create_bid(15, 4);
    let node_15 = rb_tree.add_node(new_bid, BLACK, node_20);

    let new_bid = create_bid(25, 5);
    rb_tree.add_node(new_bid, BLACK, node_20);

    let new_bid = create_bid(12, 6);
    rb_tree.add_node(new_bid, RED, node_15);

    let new_bid = create_bid(17, 7);
    rb_tree.add_node(new_bid, RED, node_15);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 19, 8);

    let tree_after_right_left_rotation = array![
        array![(15, false, 0)],
        array![(10, true, 0), (20, true, 1)],
        array![(5, false, 0), (12, false, 1), (17, false, 2), (25, false, 3)],
        array![(19, true, 5)]
    ];

    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_right_left_rotation);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_right_rotation_after_recolor() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(33, 1);
    rb_tree.insert(new_bid);
    let node_33 = new_bid.id;

    let new_bid = create_bid(13, 2);
    let node_13 = rb_tree.add_node(new_bid, RED, node_33);

    let new_bid = create_bid(43, 3);
    let node_43 = rb_tree.add_node(new_bid, BLACK, node_33);

    let new_bid = create_bid(3, 4);
    let node_3 = rb_tree.add_node(new_bid, BLACK, node_13);

    let new_bid = create_bid(29, 5);
    rb_tree.add_node(new_bid, BLACK, node_13);

    let new_bid = create_bid(38, 6);
    rb_tree.add_node(new_bid, RED, node_43);

    let new_bid = create_bid(48, 7);
    rb_tree.add_node(new_bid, RED, node_43);

    let new_bid = create_bid(2, 8);
    rb_tree.add_node(new_bid, RED, node_3);

    let new_bid = create_bid(4, 9);
    rb_tree.add_node(new_bid, RED, node_3);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 1, 10);

    let tree_after_right_rotation = array![
        array![(13, false, 0)],
        array![(3, true, 0), (33, true, 1)],
        array![(2, false, 0), (4, false, 1), (29, false, 2), (43, false, 3)],
        array![(1, true, 0), (38, true, 6), (48, true, 7)]
    ];

    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_right_rotation);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

// Tests for deletion

#[test]
#[ignore]
fn test_deletion_root() {
    let rb_tree = setup_rb_tree_test();

    let node_5 = insert(rb_tree, 5, 1);
    insert(rb_tree, 3, 2);
    insert(rb_tree, 8, 3);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    delete(rb_tree, node_5);

    let tree_after_deletion = array![array![(8, false, 0)], array![(3, true, 0)]];

    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_deletion);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_deletion_root_2_nodes() {
    let rb_tree = setup_rb_tree_test();

    let node_5 = insert(rb_tree, 5, 1);
    insert(rb_tree, 8, 2);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    delete(rb_tree, node_5);

    let tree_after_deletion = array![array![(8, false, 0)]];

    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_deletion);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_delete_single_child() {
    let rb_tree = setup_rb_tree_test();

    insert(rb_tree, 5, 1);
    insert(rb_tree, 1, 2);
    let node_6 = insert(rb_tree, 6, 3);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    delete(rb_tree, node_6);

    let tree_after_deletion = array![array![(5, false, 0)], array![(1, true, 0)]];

    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_deletion);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_delete_single_deep_child() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(20, 1);
    rb_tree.insert(new_bid);
    let node_20 = new_bid.id;

    let new_bid = create_bid(10, 2);
    let node_10 = rb_tree.add_node(new_bid, BLACK, node_20);

    let new_bid = create_bid(38, 3);
    let node_38 = rb_tree.add_node(new_bid, RED, node_20);

    let new_bid = create_bid(5, 4);
    rb_tree.add_node(new_bid, RED, node_10);

    let new_bid = create_bid(15, 5);
    rb_tree.add_node(new_bid, RED, node_10);

    let new_bid = create_bid(28, 6);
    let node_28 = rb_tree.add_node(new_bid, BLACK, node_38);

    let new_bid = create_bid(48, 7);
    let node_48 = rb_tree.add_node(new_bid, BLACK, node_38);

    let new_bid = create_bid(23, 8);
    rb_tree.add_node(new_bid, RED, node_28);

    let new_bid = create_bid(29, 9);
    rb_tree.add_node(new_bid, RED, node_28);

    let new_bid = create_bid(41, 10);
    rb_tree.add_node(new_bid, RED, node_48);

    let new_bid = create_bid(49, 11);
    let node_49 = rb_tree.add_node(new_bid, RED, node_48);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    delete(rb_tree, node_49);

    let tree_after_deletion = array![
        array![(20, false, 0)],
        array![(10, false, 0), (38, true, 1)],
        array![(5, true, 0), (15, true, 1), (28, false, 2), (48, false, 3)],
        array![(23, true, 4), (29, true, 5), (41, true, 6)]
    ];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_deletion);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_deletion_red_node_red_successor_no_children() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(16, 1);
    rb_tree.insert(new_bid);
    let node_16 = new_bid.id;

    let new_bid = create_bid(11, 2);
    let node_11 = rb_tree.add_node(new_bid, RED, node_16);

    let new_bid = create_bid(41, 3);
    let node_41 = rb_tree.add_node(new_bid, RED, node_16);

    let new_bid = create_bid(1, 4);
    rb_tree.add_node(new_bid, BLACK, node_11);

    let new_bid = create_bid(13, 5);
    rb_tree.add_node(new_bid, BLACK, node_11);

    let new_bid = create_bid(26, 6);
    rb_tree.add_node(new_bid, BLACK, node_41);

    let new_bid = create_bid(44, 7);
    let node_44 = rb_tree.add_node(new_bid, BLACK, node_41);

    let new_bid = create_bid(42, 8);
    rb_tree.add_node(new_bid, RED, node_44);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    delete(rb_tree, node_41);

    let tree_after_deletion = array![
        array![(16, false, 0)],
        array![(11, true, 0), (42, true, 1)],
        array![(1, false, 0), (13, false, 1), (26, false, 2), (44, false, 3)]
    ];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_deletion);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_mirror_deletion_red_node_red_successor_no_children() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(16, 1);
    rb_tree.insert(new_bid);
    let node_16 = new_bid.id;

    let new_bid = create_bid(11, 2);
    let node_11 = rb_tree.add_node(new_bid, RED, node_16);

    let new_bid = create_bid(41, 3);
    let node_41 = rb_tree.add_node(new_bid, RED, node_16);

    let new_bid = create_bid(1, 4);
    rb_tree.add_node(new_bid, BLACK, node_11);

    let new_bid = create_bid(13, 5);
    let node_13 = rb_tree.add_node(new_bid, BLACK, node_11);

    let new_bid = create_bid(26, 6);
    rb_tree.add_node(new_bid, BLACK, node_41);

    let new_bid = create_bid(44, 7);
    let node_44 = rb_tree.add_node(new_bid, BLACK, node_41);

    let new_bid = create_bid(12, 8);
    rb_tree.add_node(new_bid, RED, node_13);

    let new_bid = create_bid(42, 9);
    rb_tree.add_node(new_bid, RED, node_44);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    delete(rb_tree, node_11);

    let tree_after_deletion = array![
        array![(16, false, 0)],
        array![(12, true, 0), (41, true, 1)],
        array![(1, false, 0), (13, false, 1), (26, false, 2), (44, false, 3)],
        array![(42, true, 6)]
    ];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_deletion);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_deletion_black_node_black_successor_right_red_child() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(16, 1);
    rb_tree.insert(new_bid);
    let node_16 = new_bid.id;

    let new_bid = create_bid(11, 2);
    let node_11 = rb_tree.add_node(new_bid, BLACK, node_16);

    let new_bid = create_bid(36, 3);
    let node_36 = rb_tree.add_node(new_bid, BLACK, node_16);

    let new_bid = create_bid(1, 4);
    rb_tree.add_node(new_bid, BLACK, node_11);

    let new_bid = create_bid(13, 5);
    rb_tree.add_node(new_bid, BLACK, node_11);

    let new_bid = create_bid(26, 6);
    rb_tree.add_node(new_bid, BLACK, node_36);

    let new_bid = create_bid(44, 7);
    let node_44 = rb_tree.add_node(new_bid, RED, node_36);

    let new_bid = create_bid(38, 8);
    let node_38 = rb_tree.add_node(new_bid, BLACK, node_44);

    let new_bid = create_bid(47, 9);
    rb_tree.add_node(new_bid, BLACK, node_44);

    let new_bid = create_bid(41, 10);
    rb_tree.add_node(new_bid, RED, node_38);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    delete(rb_tree, node_36);

    let tree_after_deletion = array![
        array![(16, false, 0)],
        array![(11, false, 0), (38, false, 1)],
        array![(1, false, 0), (13, false, 1), (26, false, 2), (44, true, 3)],
        array![(41, false, 6), (47, false, 7)]
    ];

    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_deletion);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_deletion_black_node_black_successor_no_child() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(21, 1);
    rb_tree.insert(new_bid);
    let node_21 = new_bid.id;

    let new_bid = create_bid(1, 2);
    rb_tree.add_node(new_bid, BLACK, node_21);

    let new_bid = create_bid(41, 3);
    let node_41 = rb_tree.add_node(new_bid, RED, node_21);

    let new_bid = create_bid(31, 4);
    rb_tree.add_node(new_bid, BLACK, node_41);

    let new_bid = create_bid(49, 5);
    rb_tree.add_node(new_bid, BLACK, node_41);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    delete(rb_tree, node_21);

    let tree = rb_tree.get_tree_structure();
    let expected_tree_structure = array![
        array![(31, false, 0)], array![(1, false, 0), (41, false, 1)], array![(49, true, 3)]
    ];
    compare_tree_structures(@tree, @expected_tree_structure);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_deletion_black_node_no_successor() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(21, 1);
    rb_tree.insert(new_bid);
    let node_21 = new_bid.id;

    let new_bid = create_bid(1, 2);
    let node_1 = rb_tree.add_node(new_bid, BLACK, node_21);

    let new_bid = create_bid(41, 3);
    let node_41 = rb_tree.add_node(new_bid, BLACK, node_21);

    let new_bid = create_bid(36, 4);
    rb_tree.add_node(new_bid, RED, node_41);

    let new_bid = create_bid(51, 5);
    rb_tree.add_node(new_bid, RED, node_41);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    delete(rb_tree, node_1);

    let tree = rb_tree.get_tree_structure();
    let expected_tree_structure = array![
        array![(41, false, 0)], array![(21, false, 0), (51, false, 1)], array![(36, true, 1)]
    ];
    compare_tree_structures(@tree, @expected_tree_structure);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_mirror_deletion_black_node_no_successor() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(10, 1);
    rb_tree.insert(new_bid);
    let node_10 = new_bid.id;

    let new_bid = create_bid(5, 2);
    let node_5 = rb_tree.add_node(new_bid, BLACK, node_10);

    let new_bid = create_bid(12, 3);
    let node_12 = rb_tree.add_node(new_bid, BLACK, node_10);

    let new_bid = create_bid(1, 4);
    rb_tree.add_node(new_bid, RED, node_5);

    let new_bid = create_bid(7, 5);
    rb_tree.add_node(new_bid, RED, node_5);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    delete(rb_tree, node_12);

    let tree = rb_tree.get_tree_structure();
    let expected_tree_structure = array![
        array![(5, false, 0)], array![(1, false, 0), (10, false, 1)], array![(7, true, 2)]
    ];

    compare_tree_structures(@tree, @expected_tree_structure);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_deletion_black_node_no_successor_2() {
    let rb_tree = setup_rb_tree_test();

    insert(rb_tree, 21, 1);
    let node_1 = insert(rb_tree, 1, 2);
    insert(rb_tree, 41, 3);

    delete(rb_tree, node_1);

    let tree = rb_tree.get_tree_structure();
    let expected_tree_structure = array![array![(21, false, 0)], array![(41, true, 1)]];

    compare_tree_structures(@tree, @expected_tree_structure);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_deletion_black_node_no_successor_3() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(10, 1);
    rb_tree.insert(new_bid);
    let node_10 = new_bid.id;

    let new_bid = create_bid(7, 2);
    let node_7 = rb_tree.add_node(new_bid, BLACK, node_10);

    let new_bid = create_bid(50, 3);
    let node_50 = rb_tree.add_node(new_bid, BLACK, node_10);

    let new_bid = create_bid(4, 4);
    let node_4 = rb_tree.add_node(new_bid, BLACK, node_7);

    let new_bid = create_bid(9, 5);
    rb_tree.add_node(new_bid, BLACK, node_7);

    let new_bid = create_bid(30, 6);
    let node_30 = rb_tree.add_node(new_bid, RED, node_50);

    let new_bid = create_bid(70, 7);
    rb_tree.add_node(new_bid, BLACK, node_50);

    let new_bid = create_bid(15, 8);
    rb_tree.add_node(new_bid, BLACK, node_30);

    let new_bid = create_bid(40, 9);
    rb_tree.add_node(new_bid, BLACK, node_30);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    delete(rb_tree, node_4);

    let tree_after_deletion = array![
        array![(30, false, 0)],
        array![(10, false, 0), (50, false, 1)],
        array![(7, false, 0), (15, false, 1), (40, false, 2), (70, false, 3)],
        array![(9, true, 1)]
    ];

    let tree_structure = rb_tree.get_tree_structure();

    compare_tree_structures(@tree_structure, @tree_after_deletion);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_deletion_black_node_successor() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(10, 1);
    rb_tree.insert(new_bid);
    let node_10 = new_bid.id;

    let new_bid = create_bid(5, 2);
    let node_5 = rb_tree.add_node(new_bid, BLACK, node_10);

    let new_bid = create_bid(40, 3);
    let node_40 = rb_tree.add_node(new_bid, BLACK, node_10);

    let new_bid = create_bid(3, 4);
    rb_tree.add_node(new_bid, BLACK, node_5);

    let new_bid = create_bid(7, 5);
    rb_tree.add_node(new_bid, BLACK, node_5);

    let new_bid = create_bid(20, 6);
    rb_tree.add_node(new_bid, BLACK, node_40);

    let new_bid = create_bid(60, 7);
    let node_60 = rb_tree.add_node(new_bid, RED, node_40);

    let new_bid = create_bid(50, 8);
    rb_tree.add_node(new_bid, BLACK, node_60);

    let new_bid = create_bid(80, 9);
    rb_tree.add_node(new_bid, BLACK, node_60);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    delete(rb_tree, node_10);

    let tree_after_deletion = array![
        array![(20, false, 0)],
        array![(5, false, 0), (60, false, 1)],
        array![(3, false, 0), (7, false, 1), (40, false, 2), (80, false, 3)],
        array![(50, true, 5)]
    ];

    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_deletion);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[ignore]
fn test_mirror_deletion_black_node_successor() {
    let rb_tree = setup_rb_tree_test();

    let mut new_bid = create_bid(20, 1);
    rb_tree.insert(new_bid);
    let node_20 = new_bid.id;

    let new_bid = create_bid(10, 2);
    let node_10 = rb_tree.add_node(new_bid, BLACK, node_20);

    let new_bid = create_bid(30, 3);
    let node_30 = rb_tree.add_node(new_bid, BLACK, node_20);

    let new_bid = create_bid(8, 4);
    let node_8 = rb_tree.add_node(new_bid, RED, node_10);

    let new_bid = create_bid(15, 5);
    let node_15 = rb_tree.add_node(new_bid, BLACK, node_10);

    let new_bid = create_bid(25, 6);
    rb_tree.add_node(new_bid, BLACK, node_30);

    let new_bid = create_bid(35, 7);
    rb_tree.add_node(new_bid, BLACK, node_30);

    let new_bid = create_bid(6, 8);
    rb_tree.add_node(new_bid, BLACK, node_8);

    let new_bid = create_bid(9, 9);
    rb_tree.add_node(new_bid, BLACK, node_8);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    delete(rb_tree, node_15);

    let tree_after_deletion = array![
        array![(20, false, 0)],
        array![(8, false, 0), (30, false, 1)],
        array![(6, false, 0), (10, false, 1), (25, false, 2), (35, false, 3)],
        array![(9, true, 2)]
    ];

    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_after_deletion);

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
fn test_delete_tree_one_by_one() {
    let rb_tree = setup_rb_tree_test();

    let node_90 = insert(rb_tree, 90, 1);
    let node_70 = insert(rb_tree, 70, 2);
    let node_43 = insert(rb_tree, 43, 3);
    delete(rb_tree, node_70);
    insert(rb_tree, 24, 4);
    insert(rb_tree, 14, 5);
    insert(rb_tree, 93, 6);
    let node_47 = insert(rb_tree, 47, 7);
    delete(rb_tree, node_47);
    delete(rb_tree, node_90);
    insert(rb_tree, 57, 8);
    let node_1 = insert(rb_tree, 1, 9);
    insert(rb_tree, 60, 10);
    let node_47 = insert(rb_tree, 47, 11);
    delete(rb_tree, node_47);
    delete(rb_tree, node_1);
    delete(rb_tree, node_90);
    delete(rb_tree, node_43);
    insert(rb_tree, 49, 12);

    let final_tree = rb_tree.get_tree_structure();
    let expected_tree_structure = array![
        array![(57, false, 0)],
        array![(24, false, 0), (60, false, 1)],
        array![(14, true, 0), (49, true, 1), (93, true, 3)]
    ];
    compare_tree_structures(@final_tree, @expected_tree_structure);
    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

// Stress tests

#[test]
#[available_gas(50000000000)]
#[ignore]
fn test_add_1_to_100_delete_100_to_1() {
    let rb_tree = setup_rb_tree_test();
    let mut i = 1;
    while i <= 100 {
        insert(rb_tree, i, i.try_into().unwrap());
        println!("Inserted: {:?}", i);
        let is_tree_valid = rb_tree.is_tree_valid();
        assert(is_tree_valid, 'Tree is not valid');
        i += 1;
    };

    i = 100;
    while i >= 1 {
        let id = poseidon::poseidon_hash_span(
            array![mock_address(MOCK_ADDRESS).into(), i.try_into().unwrap()].span()
        );
        delete(rb_tree, id);
        println!("Deleted: {:?}", i);
        let is_tree_valid = rb_tree.is_tree_valid();
        assert(is_tree_valid, 'Tree is not valid');
        i -= 1;
    };

    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');
}

#[test]
#[available_gas(50000000000)]
#[ignore]
fn test_add_1_to_100_delete_1_to_100() {
    let rb_tree = setup_rb_tree_test();
    let mut i = 1;
    while i <= 100 {
        insert(rb_tree, i, i.try_into().unwrap());
        println!("Inserted: {:?}", i);
        let is_tree_valid = rb_tree.is_tree_valid();
        assert(is_tree_valid, 'Tree is not valid');
        i += 1;
    };

    i = 1;
    while i <= 100 {
        let id = poseidon::poseidon_hash_span(
            array![mock_address(MOCK_ADDRESS).into(), i.try_into().unwrap()].span()
        );
        delete(rb_tree, id);
        println!("Deleted: {:?}", i);
        let is_tree_valid = rb_tree.is_tree_valid();
        assert(is_tree_valid, 'Tree is not valid');
        i += 1;
    };
}

const max_no: u8 = 100;

fn random(seed: felt252) -> u8 {
    // Use pedersen hash to generate a pseudo-random felt252
    let hash = pedersen(seed, 0);

    // Convert the felt252 to u256 and take the last 8 bits
    let random_u256: u256 = hash.into();
    let random_u8: u8 = (random_u256 & 0xFF).try_into().unwrap();

    // Scale
    (random_u8 % max_no) + 1
}

#[test]
#[available_gas(50000000000)]
#[ignore]
fn testing_random_insertion_and_deletion() {
    let rb_tree = setup_rb_tree_test();
    let no_of_nodes: u8 = max_no;
    let mut inserted_node_ids: Array<felt252> = ArrayTrait::new();

    let mut i: u32 = 0;

    while i < no_of_nodes
        .try_into()
        .unwrap() {
            let price = random(i.try_into().unwrap());
            let nonce = i.try_into().unwrap();

            let new_bid = create_bid(price.try_into().unwrap(), nonce);

            rb_tree.insert(new_bid);

            inserted_node_ids.append(new_bid.id);

            let bid = rb_tree.find(new_bid.id);
            println!("Inserting price {}", bid.price);

            assert(bid.price == price.try_into().unwrap(), 'Insertion error');

            let is_tree_valid = rb_tree.is_tree_valid();
            assert(is_tree_valid, 'Tree is not valid');

            i += 1;
        };

    let mut j: u32 = 0;

    while j < no_of_nodes
        .try_into()
        .unwrap() {
            let bid_id = inserted_node_ids.at(j);

            delete(rb_tree, *bid_id);

            let found_bid = rb_tree.find(*bid_id);

            assert(found_bid.id == 0, 'Bid delete error');

            let is_tree_valid = rb_tree.is_tree_valid();
            assert(is_tree_valid, 'Tree is not valid');

            println!("Deleted node no. {}", j);

            j += 1;
        }
}

// Test Utilities

fn create_bid(price: u256, nonce: u64) -> Bid {
    let bidder = mock_address(MOCK_ADDRESS);
    let id = poseidon::poseidon_hash_span(array![bidder.into(), nonce.try_into().unwrap()].span());
    Bid {
        id: id,
        nonce: nonce,
        owner: bidder,
        amount: 0,
        price: price,
        is_tokenized: false,
        is_refunded: false,
    }
}

fn insert(rb_tree: IRBTreeDispatcher, price: u256, nonce: u64) -> felt252 {
    let bidder = mock_address(MOCK_ADDRESS);
    let id = poseidon::poseidon_hash_span(array![bidder.into(), nonce.try_into().unwrap()].span());
    rb_tree
        .insert(
            Bid {
                id: id,
                nonce: nonce,
                owner: bidder,
                amount: 0,
                price: price,
                is_tokenized: false,
                is_refunded: false,
            }
        );
    return id;
}

fn is_tree_valid(rb_tree: IRBTreeDispatcher) {
    let is_tree_valid = rb_tree.is_tree_valid();
    println!("Is tree valid: {:?}", is_tree_valid);
}

fn delete(rb_tree: IRBTreeDispatcher, bid_id: felt252) {
    rb_tree.delete(bid_id);
}

fn compare_tree_structures(
    actual: @Array<Array<(u256, bool, u128)>>, expected: @Array<Array<(u256, bool, u128)>>
) {
    if actual.len() != expected.len() {
        return;
    }

    let mut i = 0;

    // Compare outer array
    while i < actual
        .len() {
            let actual_inner = actual[i];
            let expected_inner = expected[i];
            compare_inner(actual_inner, expected_inner);
            i += 1;
        }
}

fn compare_inner(actual: @Array<(u256, bool, u128)>, expected: @Array<(u256, bool, u128)>) {
    if actual.len() != expected.len() {
        return;
    }

    let mut i = 0;

    while i < actual
        .len() {
            let actual_tuple = *actual[i];
            let expected_tuple = *expected[i];
            compare_tuple(actual_tuple, expected_tuple);
            i += 1;
        }
}

fn compare_tuple(actual: (u256, bool, u128), expected: (u256, bool, u128)) {
    let (actual_price, actual_color, actual_position) = actual;
    let (expected_price, expected_color, expected_position) = expected;

    assert(actual_price == expected_price, 'Price mismatch');
    assert(actual_color == expected_color, 'Color mismatch');
    assert(actual_position == expected_position, 'Position mismatch');

    return;
}
