use pitch_lake_starknet::{
    tests::option_round::rb_tree::rb_tree_mock_contract::RBTreeMockContract,
    contracts::option_round::OptionRound::Bid
};
use starknet::{deploy_syscall, SyscallResultTrait, contract_address_const, ContractAddress };

#[starknet::interface]
pub trait IRBTree<TContractState> {
    fn insert(ref self: TContractState, value: Bid);
    fn get_nonce(ref self: TContractState) -> u64;
    fn get_tree_structure(ref self: TContractState) -> Array<Array<(u256, bool, u256)>>;
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
#[available_gas(50000000)]
fn test_insertion() {
    let rb_tree = setup_rb_tree();
    
    // Test 1 - Root insertion
    insert(rb_tree, 5, 1);
    let tree_structure = rb_tree.get_tree_structure();
    let tree_with_root_only = array![
        array![(5, false, 0)]
    ];
    println!("{:?}", tree_structure);
    compare_tree_structures(@tree_structure, @tree_with_root_only);
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
    actual: @Array<Array<(u256, bool, u256)>>,
    expected: @Array<Array<(u256, bool, u256)>>
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
    actual: @Array<(u256, bool, u256)>,
    expected: @Array<(u256, bool, u256)>
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
    actual: (u256, bool, u256),
    expected: (u256, bool, u256)
) {
    let (actual_price, actual_color, actual_position) = actual;
    let (expected_price, expected_color, expected_position) = expected;

    assert(actual_price == expected_price, 'Price mismatch');
    assert(actual_color == expected_color, 'Color mismatch');
    assert(actual_position == expected_position, 'Position mismatch');

    return;
}
