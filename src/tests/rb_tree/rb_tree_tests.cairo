use pitch_lake_starknet::{
    tests::rb_tree::rb_tree_mock_contract::RBTreeMockContract,
    contracts::utils::red_black_tree::{ Bid }
};
use starknet::{deploy_syscall, SyscallResultTrait, contract_address_const, ContractAddress };

#[starknet::interface]
pub trait IRBTree<TContractState> {
    fn insert(ref self: TContractState, value: Bid);
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
    let mock_owner = mock_address(123456); 
    rb_tree.insert(Bid { 
        id: 1,
        nonce: 1,
        owner: mock_owner,
        amount: 10,
        price: 10,
        is_tokenized: false,
        is_refunded: false, 
    });
}