use pitch_lake_starknet::{contracts::{option_round::{types::{Bid}}}};

#[starknet::interface]
pub trait IRBTreeMockContract<TContractState> {
    fn insert(ref self: TContractState, value: Bid);
    fn find(self: @TContractState, bid_id: felt252) -> Bid;
    fn get_tree_structure(self: @TContractState) -> Array<Array<(u256, bool, u128)>>;
    fn is_tree_valid(self: @TContractState) -> bool;
    fn delete(ref self: TContractState, bid_id: felt252);
    fn add_node(ref self: TContractState, value: Bid, color: bool, parent: felt252) -> felt252;
}

#[starknet::contract]
mod RBTreeMockContract {
    use pitch_lake_starknet::contracts::components::red_black_tree::RBTreeComponent;

    component!(path: RBTreeComponent, storage: rb_tree, event: RBTreeEvent);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        rb_tree: RBTreeComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        RBTreeEvent: RBTreeComponent::Event
    }

    #[abi(embed_v0)]
    impl RBTreeImpl = RBTreeComponent::RBTree<ContractState>;
}

