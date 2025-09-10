use pitch_lake::types::Bid;

#[starknet::interface]
trait IRBTreeMockContract<TContractState> {
    fn insert(ref self: TContractState, value: Bid);
    fn find(self: @TContractState, bid_id: felt252) -> Bid;
    fn get_tree_structure(self: @TContractState) -> Array<Array<(u256, bool, u128)>>;
    fn is_tree_valid(self: @TContractState) -> bool;
    fn delete(ref self: TContractState, bid_id: felt252);
    fn add_node(ref self: TContractState, value: Bid, color: bool, parent: felt252) -> felt252;
}

#[starknet::contract]
mod RBTreeMockContract {
    use pitch_lake::library::red_black_tree::RBTreeComponent;
    use pitch_lake::types::Bid;

    component!(path: RBTreeComponent, storage: rb_tree, event: RBTreeEvent);

    impl RBTreeImpl = RBTreeComponent::RBTreeImpl<ContractState>;
    impl RBTreeTestingImpl = RBTreeComponent::RBTreeTestingImpl<ContractState>;
    impl RBTreeOperationsImpl = RBTreeComponent::RBTreeOperationsImpl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        rb_tree: RBTreeComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        RBTreeEvent: RBTreeComponent::Event,
    }

    #[abi(embed_v0)]
    impl RBTreeMockContractImpl of super::IRBTreeMockContract<ContractState> {
        // Tree main functions
        fn insert(ref self: ContractState, value: Bid) {
            self.rb_tree._insert(value);
        }

        fn find(self: @ContractState, bid_id: felt252) -> Bid {
            self.rb_tree._find(bid_id)
        }

        fn delete(ref self: ContractState, bid_id: felt252) {
            self.rb_tree._delete(bid_id);
        }

        // Tree testing functions
        fn get_tree_structure(self: @ContractState) -> Array<Array<(u256, bool, u128)>> {
            self.rb_tree._get_tree_structure()
        }

        fn is_tree_valid(self: @ContractState) -> bool {
            self.rb_tree._is_tree_valid()
        }

        // Internal function for testing
        fn add_node(ref self: ContractState, value: Bid, color: bool, parent: felt252) -> felt252 {
            self.rb_tree._add_node(value, color, parent)
        }
    }
}

