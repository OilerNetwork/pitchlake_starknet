use pitch_lake_starknet::{
    tests::option_round::rb_tree::rb_tree_mock_contract::RBTreeMockContract,
    contracts::option_round::OptionRound::Bid
};
use starknet::{deploy_syscall, SyscallResultTrait, contract_address_const, ContractAddress };

#[starknet::interface]
pub trait IRBTree<TContractState> {
    fn insert(ref self: TContractState, value: Bid);
    fn get_nonce(ref self: TContractState) -> u64;
    fn get_tree_structure(ref self: TContractState) -> Array<Array<(u256, bool, u128)>>;
    fn is_tree_valid(ref self: TContractState) -> bool;
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

#[test]
fn test_insertion() {
    let rb_tree = setup_rb_tree();
    
    insert(rb_tree, 2, 1);
    let tree_structure = rb_tree.get_tree_structure();
    let tree_with_root_node = array![
        array![(2, false, 0)]
    ];
    compare_tree_structures(@tree_structure, @tree_with_root_node);

    insert(rb_tree, 1, 2);
    let tree_with_left_node = array![
        array![(2, false, 0)],
        array![(1, true, 0)]
    ];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_with_left_node);
    
    insert(rb_tree, 4, 3);
    let tree_with_right_node = array![
        array![(2, false, 0)],
        array![(1, true, 0)],
        array![(4, true, 0)]
    ];
    let tree_structure = rb_tree.get_tree_structure();
    compare_tree_structures(@tree_structure, @tree_with_right_node);
    let is_tree_valid = rb_tree.is_tree_valid();
    assert(is_tree_valid, 'Tree is not valid');

    insert(rb_tree, 5, 4);
    let tree_after_recolor_parents = array![
        array![(2, false, 0)],
        array![(1, false, 0), (4, false, 1)],
        array![(5, true, 3)]
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
    let is_tree_valid = rb_tree.is_tree_valid();
    println!("{:?}", @tree_structure);
    println!("{:?}", is_tree_valid);
}

fn insert(rb_tree: IRBTreeDispatcher, price: u256, nonce: u64) {
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
    });
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