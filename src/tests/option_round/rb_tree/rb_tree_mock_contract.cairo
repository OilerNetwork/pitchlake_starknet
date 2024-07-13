#[starknet::contract]
mod RBTreeMockContract {
    use pitch_lake_starknet::contracts::components::red_black_tree::{RBTreeComponent};

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

