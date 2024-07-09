use pitch_lake_starknet::{
    tests::option_round::rb_tree::rb_tree_mock_contract::RBTreeMockContract,
    contracts::utils::red_black_tree::{ Bid }
};
use starknet::{deploy_syscall, SyscallResultTrait, contract_address_const, ContractAddress };

#[starknet::interface]
pub trait IRBTree<TContractState> {
    fn insert(ref self: TContractState, value: Bid);
    fn get_nonce(ref self: TContractState) -> u64;
    fn get_tree_structure(ref self: TContractState) -> Array<Array<(Bid, bool, u256)>>;
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
    insert(rb_tree, 1, 1);
    insert(rb_tree, 2, 2);
    insert(rb_tree, 3, 3);
    let tree_structure = rb_tree.get_tree_structure();
    println!("{:?}", tree_structure);
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