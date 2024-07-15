use pitch_lake_starknet::tests::{
    utils::helpers::setup::setup_rb_tree_test,
    option_round::rb_tree::{
        {rb_tree_tests::{ insert, delete, mock_address, MOCK_ADDRESS, IRBTreeDispatcher, create_bid }}}
};
use core::pedersen::pedersen;

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
