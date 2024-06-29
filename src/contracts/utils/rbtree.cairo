use starknet::{ContractAddress};
use pitch_lake_starknet::contracts::{option_round::OptionRound::Bid};

// The interface for the vault contract
#[starknet::interface]
trait IRedBlackTree<TContractState> {
    fn insert(ref self: TContractState, bid: Bid);

    fn delete(ref self: TContractState, node: felt252);

    fn get_bid_data(self: @TContractState);
//Rotations

}

#[starknet::contract]
mod RedBlackTree {
    use pitch_lake_starknet::contracts::{
        utils::rbtree::IRedBlackTree, option_round::OptionRound::Bid
    };
    // The type of vault

    #[derive(Copy, Drop, Serde, starknet::Store)]
    struct Node {
        parent: felt252,
        id: felt252,
        right: felt252,
        left: felt252,
        is_red: bool
    }


    #[storage]
    struct Storage {
        root: felt252,
        bid_details: LegacyMap<felt252, Bid>,
        list: LegacyMap<felt252, Node>
    }

    // @note Need to add eth address as a param here
    //  - Will need to update setup functions to accomodate
    #[constructor]
    fn constructor(ref self: ContractState,) {}

    #[abi(embed_v0)]
    impl RedBlackTreeImpl of super::IRedBlackTree<ContractState> {
        fn insert(ref self: ContractState, bid: Bid) {
            self.bid_details.write(bid.id, bid);

            let root = self._insert(self.root.read(), 0_felt252, bid);
            if (root != self.root.read()) {
                self.root.write(root);
            }
        }

        fn delete(ref self: ContractState, node: felt252) {}


        fn get_bid_data(self: @ContractState) {}
    //Rotations

    }


    // Internal Functions
    #[generate_trait]
    impl InternalImpl of RedBlackTreeInternalTrait {
        // Get a dispatcher for the ETH contract
        fn compare(self: @ContractState, a: felt252, b: felt252) -> u256 {
            return 2;
        }

        fn _delete(ref self: ContractState, root: felt252, parent: felt252, bid: Bid)->felt252{
            if(root == 0)
            {
                return 0;
            }
            let mut node_root = self.list.read(root);
            let cmp = self.compare(self.root.read(), bid.id);
            if (cmp < 0) {
                let left = self._delete(node_root.left,node_root.id, bid);
                if (left != node_root.left) {
                    node_root.left = left;
                    self.list.write(node_root.id, node_root)
                }
                { //let x.left = this._put(x.left, key, value);
                }
            } else if (cmp > 0) {
                let right = self._delete(node_root.right,node_root.id, bid);
                if (right != node_root.right) {
                    node_root.right = right;
                    self.list.write(node_root.id, node_root)
                } //x.right = this._put(x.right, key, value);
            } else { //Create a bucket
            // x.value = value;
            }
            return 1;
        }
        fn _insert(ref self: ContractState, root: felt252, parent: felt252, bid: Bid) -> felt252 {
            if (root == 0) {
                self
                    .list
                    .write(
                        bid.id, Node { id: bid.id, parent, right: 0, left: 0, is_red: true }
                    );
                return bid.id;
            }

            let mut node_root = self.list.read(root);
            let cmp = self.compare(self.root.read(), bid.id);
            if (cmp < 0) {
                let left = self._insert(node_root.left,node_root.id, bid);
                if (left != node_root.left) {
                    node_root.left = left;
                    self.list.write(node_root.id, node_root)
                }
                { //let x.left = this._put(x.left, key, value);
                }
            } else if (cmp > 0) {
                let right = self._insert(node_root.right,node_root.id, bid);
                if (right != node_root.right) {
                    node_root.right = right;
                    self.list.write(node_root.id, node_root)
                } //x.right = this._put(x.right, key, value);
            } else { //Create a bucket
            // x.value = value;
            }
            let mut node_right= self.list.read(node_root.right);
            let mut node_left = self.list.read(node_root.left);
            if(node_right.is_red==true &&  node_left.is_red!=true){

                node_root = self.rotate_left(node_root,node_left,node_right);
                node_right = self.list.read(node_root.right);
                node_left = self.list.read(node_root.left);

            };
            if(node_left.is_red==true && self.list.read(node_left.left).is_red==true){
                node_root = self.rotate_right(node_root, node_left, node_right);
                node_right = self.list.read(node_root.right);
                node_left = self.list.read(node_root.left);
            }
            if(node_left.is_red && node_right.is_red) {
                node_left.is_red==false;
                node_right.is_red==false;
                node_root.is_red == true;
                self.list.write(node_left.id,node_left);
                self.list.write(node_right.id,node_right);
                self.list.write(node_root.id,node_root);
            }
            self.root.read()
        }

        fn rotate_left(ref self: ContractState,mut node_root:Node,node_left:Node,node_right:Node) -> Node{
            let mut new_root = node_right;
            node_root.right = node_right.left;
            if(node_right.left!=0){
                let mut left = self.list.read(node_right.left);
                left.parent = node_root.id;
                self.list.write(left.id,left);
            }
            let mut root_parent = self.list.read(node_root.parent);
            new_root.parent=node_root.parent;
            if(node_root.parent==0){
                //Put root as new_root
                self.root.write(new_root.id);
            }
            else if(root_parent.left==node_root.id){
                
                root_parent.left=new_root.id;
                self.list.write(root_parent.id,root_parent)
            }
            else{
                root_parent.right=new_root.id;
                self.list.write(root_parent.id,root_parent)
            }
            new_root.left = node_root.id;
            node_root.parent = new_root.id;
            self.list.write(new_root.id,new_root);
            self.list.write(node_root.id,node_root);
            new_root
        }
        fn rotate_right(ref self: ContractState, mut node_root:Node, node_left:Node, node_right:Node) ->Node{
            let mut new_root = node_left;
            node_root.left = node_left.right;
            if(node_left.right!=0){
                let mut right = self.list.read(node_left.right);
                right.parent = node_root.id;
                self.list.write(right.id,right);
            }
            let mut root_parent = self.list.read(node_root.parent);
            new_root.parent=node_root.parent;
            if(node_root.parent==0){
                //Put root as new_root
                self.root.write(new_root.id);
            }
            else if(root_parent.right==node_root.id){
                
                root_parent.right=new_root.id;
                self.list.write(root_parent.id,root_parent)
            }
            else{
                root_parent.left=new_root.id;
                self.list.write(root_parent.id,root_parent)
            }
            new_root.right = node_root.id;
            node_root.parent = new_root.id;
            self.list.write(new_root.id,new_root);
            self.list.write(node_root.id,node_root);
            new_root
        }
    }
}
