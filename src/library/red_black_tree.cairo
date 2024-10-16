use pitch_lake::{library::red_black_tree, types::{Bid}};
use starknet::ContractAddress;

#[starknet::component]
pub mod RBTreeComponent {
    use super::{Bid, ContractAddress};
    use core::{array::ArrayTrait, option::OptionTrait, traits::{TryInto}};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess,};
    use starknet::storage::{Map, StoragePathEntry};

    const BLACK: bool = false;
    const RED: bool = true;

    #[storage]
    struct Storage {
        root: felt252,
        tree: Map::<felt252, Node>,
        tree_nonce: u64,
        clearing_bid_amount_sold: u256,
        clearing_price: u256,
        clearing_bid: felt252,
        total_options_sold: u256,
        total_options_available: u256,
    }

    #[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
    struct Node {
        value: Bid,
        left: felt252,
        right: felt252,
        parent: felt252,
        color: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event, PartialEq)]
    pub enum Event {
        InsertEvent: InsertEvent
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct InsertEvent {
        node: Node,
    }

    #[generate_trait]
    pub impl RBTreeImpl<
        TContractState, +HasComponent<TContractState>
    > of RBTreeTrait<TContractState> {
        fn _insert(ref self: ComponentState<TContractState>, value: Bid) {
            let new_node_id = value.bid_id;

            if self.root.read().is_zero() {
                let root_node = self.create_root_node(@value);
                self.tree.entry(new_node_id).write(root_node);
                self.root.write(new_node_id);
            } else {
                self.insert_node_recursively(self.root.read(), new_node_id, value);
                self.balance_after_insertion(new_node_id);
            }

            self.tree_nonce.write(self.tree_nonce.read() + 1);
        }

        fn _find(self: @ComponentState<TContractState>, bid_id: felt252) -> Bid {
            let node: Node = self.tree.entry(bid_id).read();
            return node.value;
        }

        fn _update(ref self: ComponentState<TContractState>, bid_id: felt252, bid: Bid) {
            if bid_id.is_non_zero() {
                let mut node: Node = self.tree.read(bid_id);
                node.value = bid;
                // let new_node = Node { value: bid, ..node };
                self.tree.entry(bid_id).write(node);
            }
        }

        fn _delete(ref self: ComponentState<TContractState>, bid_id: felt252) {
            if bid_id.is_non_zero() {
                self.delete_node(bid_id);
            }
        }
    }

    #[generate_trait]
    pub impl RBTreeOptionRoundImpl<
        TContractState, +HasComponent<TContractState>
    > of RBTreeOptionRoundTrait<TContractState> {
        fn find_clearing_price(ref self: ComponentState<TContractState>) -> (u256, u256, u64) {
            let total_options_available = self._get_total_options_available();
            let root: felt252 = self.root.read();
            let root_node: Node = self.tree.entry(root).read();
            let root_bid: Bid = root_node.value;
            let (clearing_felt, remaining_options) = self
                .traverse_postorder_clearing_price_from_node(
                    root, total_options_available, root_bid.price, root
                );
            let clearing_node: Node = self.tree.entry(clearing_felt).read();
            let total_options_sold = total_options_available - remaining_options;
            self.total_options_sold.write(total_options_sold);
            if (remaining_options == 0) {
                self.clearing_bid.write(clearing_felt);
            }
            self.clearing_price.write(clearing_node.value.price);
            (clearing_node.value.price, total_options_sold, clearing_node.tree_nonce)
        }

        fn get_total_options_sold(self: @ComponentState<TContractState>) -> u256 {
            self.total_options_sold.read()
        }

        fn _get_total_options_available(self: @ComponentState<TContractState>) -> u256 {
            self.total_options_available.read()
        }

        fn traverse_postorder_clearing_price_from_node(
            ref self: ComponentState<TContractState>,
            current_id: felt252,
            total_options_available: u256,
            mut clearing_price: u256,
            mut clearing_felt: felt252,
        ) -> (felt252, u256) {
            if (current_id == 0) {
                return (clearing_felt, total_options_available);
            }
            let current_node: Node = self.tree.entry(current_id).read();

            //Recursive on Right Node
            let (clearing_felt, mut remaining_options) = self
                .traverse_postorder_clearing_price_from_node(
                    current_node.right, total_options_available, clearing_price, clearing_felt
                );
            if (remaining_options == 0) {
                return (clearing_felt, 0);
            }

            //Check for self
            if (current_node.value.amount >= remaining_options) {
                self.clearing_bid_amount_sold.write(remaining_options);

                return (current_id, 0);
            } else {
                remaining_options -= current_node.value.amount;
                clearing_price = current_node.value.price;
            }
            //Recursive on Left Node and return result directly to the outer call
            self
                .traverse_postorder_clearing_price_from_node(
                    current_node.left, remaining_options, clearing_price, current_id
                )
        }
    }

    #[generate_trait]
    impl RBTreeOperationsImpl<
        TContractState, +HasComponent<TContractState>
    > of RBTreeOperationsTrait<TContractState> {
        fn create_root_node(self: @ComponentState<TContractState>, value: @Bid) -> Node {
            Node { value: *value, left: 0, right: 0, parent: 0, color: BLACK, }
        }

        fn create_leaf_node(
            self: @ComponentState<TContractState>, value: @Bid, parent: felt252
        ) -> Node {
            Node { value: *value, left: 0, right: 0, parent: parent, color: RED, }
        }

        fn is_left_child(ref self: ComponentState<TContractState>, node_id: felt252) -> bool {
            let node: Node = self.tree.entry(node_id).read();
            let parent_id = node.parent;
            let parent: Node = self.tree.read(parent_id);
            return parent.left == node_id;
        }

        fn update_left(
            ref self: ComponentState<TContractState>, node_id: felt252, left_id: felt252
        ) {
            let mut node: Node = self.tree.entry(node_id).read();
            node.left = left_id;
            self.tree.entry(node_id).write(node);
        }

        fn update_right(
            ref self: ComponentState<TContractState>, node_id: felt252, right_id: felt252
        ) {
            let mut node: Node = self.tree.entry(node_id).read();
            node.right = right_id;
            self.tree.entry(node_id).write(node);
        }

        fn update_parent(
            ref self: ComponentState<TContractState>, node_id: felt252, parent_id: felt252
        ) {
            let mut node: Node = self.tree.entry(node_id).read();
            node.parent = parent_id;
            self.tree.entry(node_id).write(node);
        }

        fn get_parent(ref self: ComponentState<TContractState>, node_id: felt252) -> felt252 {
            if node_id == 0 {
                0
            } else {
                let node: Node = self.tree.entry(node_id).read();
                node.parent
            }
        }

        fn is_black(self: @ComponentState<TContractState>, node_id: felt252) -> bool {
            let node: Node = self.tree.entry(node_id).read();
            node_id == 0 || node.color == BLACK
        }

        fn is_red(self: @ComponentState<TContractState>, node_id: felt252) -> bool {
            if node_id == 0 {
                return false;
            }
            let node: Node = self.tree.entry(node_id).read();
            node.color == RED
        }

        fn ensure_root_is_black(ref self: ComponentState<TContractState>) {
            let root = self.root.read();
            self.set_color(root, BLACK); // Black
        }

        fn set_color(ref self: ComponentState<TContractState>, node_id: felt252, color: bool) {
            if node_id == 0 {
                return; // Can't set color of null node
            }
            let mut node: Node = self.tree.entry(node_id).read();
            node.color = color;
            self.tree.write(node_id, node);
        }

        // Add a new node directly by accepting parent and value (bid)
        fn _add_node(
            ref self: ComponentState<TContractState>, bid: Bid, color: bool, parent: felt252
        ) -> felt252 {
            let new_node = Node { value: bid, left: 0, right: 0, parent: parent, color: color, };
            let bid_id = bid.bid_id;
            let parent_node = self.tree.entry(parent).read();
            if bid <= parent_node.value {
                self.update_left(parent, bid_id);
            } else {
                self.update_right(parent, bid_id);
            }
            self.update_parent(bid_id, parent);
            self.tree.entry(bid_id).write(new_node);
            return bid_id;
        }
    }

    #[generate_trait]
    pub impl RBTreeTestingImpl<
        TContractState, +HasComponent<TContractState>
    > of RBTreeTestingTrait<TContractState> {
        fn _get_tree_structure(
            self: @ComponentState<TContractState>
        ) -> Array<Array<(u256, bool, u128)>> {
            self.build_tree_structure_list()
        }

        fn _is_tree_valid(self: @ComponentState<TContractState>) -> bool {
            self.check_if_rb_tree_is_valid()
        }

        fn get_node_positions_by_level(
            self: @ComponentState<TContractState>
        ) -> Array<Array<(felt252, u128)>> {
            let mut queue: Array<(felt252, u128)> = ArrayTrait::new();
            let root_id = self.root.read();
            let initial_level = 0;
            let mut current_level = 0;
            let mut filled_position_in_levels: Array<Array<(felt252, u128)>> = ArrayTrait::new();
            let mut filled_position_in_level: Array<(felt252, u128)> = ArrayTrait::new();
            let mut node_positions: Felt252Dict<u128> = Default::default();

            self
                .collect_position_and_levels_of_nodes(
                    root_id, 0, initial_level, ref node_positions
                );
            queue.append((root_id, 0));

            while !queue.is_empty() {
                let (node_id, level) = queue.pop_front().unwrap();
                let node = self.tree.entry(node_id).read();

                if level > current_level {
                    current_level = level;
                    filled_position_in_levels.append(filled_position_in_level);
                    filled_position_in_level = ArrayTrait::new();
                }

                let position = node_positions.get(node_id);

                filled_position_in_level.append((node_id, position));

                if node.left != 0 {
                    queue.append((node.left, current_level + 1));
                }

                if node.right != 0 {
                    queue.append((node.right, current_level + 1));
                }
            };
            filled_position_in_levels.append(filled_position_in_level);
            return filled_position_in_levels;
        }

        fn build_tree_structure_list(
            self: @ComponentState<TContractState>
        ) -> Array<Array<(u256, bool, u128)>> {
            if (self.root.read() == 0) {
                return ArrayTrait::new();
            }
            let filled_position_in_levels_original = self.get_node_positions_by_level();
            let mut filled_position_in_levels: Array<Array<(u256, bool, u128)>> = ArrayTrait::new();
            let mut filled_position_in_level: Array<(u256, bool, u128)> = ArrayTrait::new();
            let mut i = 0;
            while i < filled_position_in_levels_original.len() {
                let level = filled_position_in_levels_original.at(i.try_into().unwrap());
                let mut j = 0;
                while j < level.len() {
                    let (node_id, position) = level.at(j.try_into().unwrap());
                    let node = self.tree.entry(*node_id).read();
                    filled_position_in_level.append((node.value.price, node.color, *position));
                    j += 1;
                };
                filled_position_in_levels.append(filled_position_in_level);
                filled_position_in_level = ArrayTrait::new();
                i += 1;
            };
            return filled_position_in_levels;
        }

        fn collect_position_and_levels_of_nodes(
            self: @ComponentState<TContractState>,
            node_id: felt252,
            position: u128,
            level: u256,
            ref node_positions: Felt252Dict<u128>
        ) {
            if node_id == 0 {
                return;
            }

            let node = self.tree.entry(node_id).read();

            node_positions.insert(node_id, position);

            self
                .collect_position_and_levels_of_nodes(
                    node.left, position * 2, level + 1, ref node_positions
                );
            self
                .collect_position_and_levels_of_nodes(
                    node.right, position * 2 + 1, level + 1, ref node_positions
                );
        }

        fn check_if_rb_tree_is_valid(self: @ComponentState<TContractState>) -> bool {
            let root = self.root.read();
            if root == 0 {
                return true; // An empty tree is a valid RB tree
            }

            // Check if root is black
            if !self.is_black(root) {
                return false;
            }

            // Check other properties
            let (is_valid, _) = self.validate_node(root);
            is_valid
        }

        fn validate_node(self: @ComponentState<TContractState>, node: felt252) -> (bool, u32) {
            if node == 0 {
                return (true, 1); // Null nodes are considered black
            }

            let node_data = self.tree.entry(node).read();

            let (left_valid, left_black_height) = self.validate_node(node_data.left);
            let (right_valid, right_black_height) = self.validate_node(node_data.right);

            if !left_valid || !right_valid {
                return (false, 0);
            }

            // Check Red-Black properties
            if self.is_red(node) {
                if self.is_red(node_data.left) || self.is_red(node_data.right) {
                    return (false, 0); // Red node cannot have red children
                }
            }

            if left_black_height != right_black_height {
                return (false, 0); // Black height must be the same for both subtrees
            }

            let current_black_height = left_black_height + if self.is_black(node) {
                1
            } else {
                0
            };
            (true, current_black_height)
        }
    }

    #[generate_trait]
    impl RBTreeDeleteBalance<
        TContractState, +HasComponent<TContractState>
    > of RBTreeDeleteBalanceTrait<TContractState> {
        fn delete_node(ref self: ComponentState<TContractState>, delete_id: felt252) {
            let mut y = delete_id;
            let mut node_delete: Node = self.tree.entry(delete_id).read();
            let mut y_original_color = node_delete.color;
            let mut x: felt252 = 0;
            let mut x_parent: felt252 = 0;

            if node_delete.left == 0 {
                x = node_delete.right;
                x_parent = node_delete.parent;
                self.transplant(delete_id, x);
            } else if node_delete.right == 0 {
                x = node_delete.left;
                x_parent = node_delete.parent;
                self.transplant(delete_id, x);
            } else {
                y = self.minimum(node_delete.right);
                let y_node: Node = self.tree.entry(y).read();
                y_original_color = y_node.color;
                x = y_node.right;

                if y_node.parent == delete_id {
                    x_parent = y;
                } else {
                    x_parent = y_node.parent;
                    self.transplant(y, x);
                    let mut y_node: Node = self.tree.entry(y).read();
                    node_delete = self.tree.entry(delete_id).read();
                    y_node.right = node_delete.right;
                    self.tree.entry(y).write(y_node);
                    self.update_parent(node_delete.right, y);
                }

                self.transplant(delete_id, y);
                let mut y_node: Node = self.tree.entry(y).read();
                node_delete = self.tree.entry(delete_id).read();
                y_node.left = node_delete.left;
                y_node.color = node_delete.color;
                self.tree.entry(y).write(y_node);
                node_delete = self.tree.entry(delete_id).read();

                self.update_parent(node_delete.left, y);
            }

            self.tree.entry(delete_id).write(self.get_default_node());

            if y_original_color == BLACK {
                self.delete_fixup(x, x_parent);
            }

            self.ensure_root_is_black();
        }

        fn delete_fixup(
            ref self: ComponentState<TContractState>, mut x: felt252, mut x_parent: felt252
        ) {
            while x != self.root.read() && (x == 0 || self.is_black(x)) {
                let mut x_parent_node: Node = self.tree.entry(x_parent).read();
                if x == x_parent_node.left {
                    let mut w = x_parent_node.right;

                    // Case 1: x's sibling w is red
                    if self.is_red(w) {
                        self.set_color(w, BLACK);
                        self.set_color(x_parent, RED);
                        self.rotate_left(x_parent);
                        x_parent_node = self.tree.entry(x_parent).read();
                        w = x_parent_node.right;
                    }

                    // Case 2: x's sibling w is black, and both of w's children are black
                    let mut w_node: Node = self.tree.entry(w).read();
                    if (w_node.left == 0 || self.is_black(w_node.left))
                        && (w_node.right == 0 || self.is_black(w_node.right)) {
                        self.set_color(w, RED);
                        x = x_parent;
                        x_parent = self.get_parent(x);
                    } else {
                        // Case 3: x's sibling w is black, w's left child is red, and w's right
                        // child is black
                        if w_node.right == 0 || self.is_black(w_node.right) {
                            if w_node.left != 0 {
                                self.set_color(w_node.left, BLACK);
                            }
                            self.set_color(w, RED);
                            self.rotate_right(w);
                            x_parent_node = self.tree.entry(x_parent).read();
                            w = x_parent_node.right;
                        }

                        // Case 4: x's sibling w is black, and w's right child is red
                        x_parent_node = self.tree.entry(x_parent).read();
                        self.set_color(w, x_parent_node.color);
                        self.set_color(x_parent, BLACK);
                        w_node = self.tree.entry(w).read();
                        if w_node.right != 0 {
                            self.set_color(w_node.right, BLACK);
                        }
                        self.rotate_left(x_parent);
                        x = self.root.read();
                        break;
                    }
                } else {
                    // Mirror cases for when x is a right child
                    let mut w = x_parent_node.left;

                    // Case 1 (mirror): x's sibling w is red
                    if self.is_red(w) {
                        self.set_color(w, BLACK);
                        self.set_color(x_parent, RED);
                        self.rotate_right(x_parent);
                        x_parent_node = self.tree.entry(x_parent).read();
                        w = x_parent_node.left;
                    }

                    // Case 2 (mirror): x's sibling w is black, and both of w's children are black
                    let mut w_node: Node = self.tree.entry(w).read();
                    if (w_node.right == 0 || self.is_black(w_node.right))
                        && (w_node.left == 0 || self.is_black(w_node.left)) {
                        self.set_color(w, RED);
                        x = x_parent;
                        x_parent = self.get_parent(x);
                    } else {
                        // Case 3 (mirror): x's sibling w is black, w's right child is red, and w's
                        // left child is black
                        if w_node.left == 0 || self.is_black(w_node.left) {
                            if w_node.right != 0 {
                                self.set_color(w_node.right, BLACK);
                            }
                            self.set_color(w, RED);
                            self.rotate_left(w);
                            x_parent_node = self.tree.entry(x_parent).read();
                            w = x_parent_node.left;
                        }

                        // Case 4 (mirror): x's sibling w is black, and w's left child is red
                        x_parent_node = self.tree.read(x_parent);
                        self.set_color(w, x_parent_node.color);
                        self.set_color(x_parent, BLACK);
                        w_node = self.tree.entry(w).read();
                        if w_node.left != 0 {
                            self.set_color(w_node.left, BLACK);
                        }
                        self.rotate_right(x_parent);
                        x = self.root.read();
                        break;
                    }
                }
            };

            // Final color adjustment
            if x != 0 {
                self.set_color(x, BLACK);
            }
        }

        fn transplant(ref self: ComponentState<TContractState>, u: felt252, v: felt252) {
            let u_node = self.tree.entry(u).read();
            if u_node.parent == 0 {
                self.root.write(v);
            } else if self.is_left_child(u) {
                self.update_left(u_node.parent, v);
            } else {
                self.update_right(u_node.parent, v);
            }
            if v != 0 {
                self.update_parent(v, u_node.parent);
            }
        }

        fn minimum(ref self: ComponentState<TContractState>, node_id: felt252) -> felt252 {
            let mut current = node_id;
            let mut node: Node = self.tree.entry(current).read();
            while node.left != 0 {
                current = node.left;
                node = self.tree.entry(current).read();
            };
            current
        }


        fn get_default_node(ref self: ComponentState<TContractState>) -> Node {
            Node { value: self.get_default_bid(), left: 0, right: 0, parent: 0, color: BLACK, }
        }

        fn get_default_bid(ref self: ComponentState<TContractState>) -> Bid {
            Bid { bid_id: 0, owner: 0.try_into().unwrap(), amount: 0, price: 0, tree_nonce: 0 }
        }
    }

    #[generate_trait]
    impl RBTreeInsertBalance<
        TContractState, +HasComponent<TContractState>
    > of RBTreeInsertBalanceTrait<TContractState> {
        fn insert_node_recursively(
            ref self: ComponentState<TContractState>,
            current_id: felt252,
            new_node_id: felt252,
            value: Bid
        ) {
            let mut current_node: Node = self.tree.entry(current_id).read();
            if value <= current_node.value {
                if current_node.left == 0 {
                    current_node.left = new_node_id;

                    let new_node = self.create_leaf_node(@value, current_id);
                    self.tree.entry(new_node_id).write(new_node);
                    self.tree.entry(current_id).write(current_node);

                    return;
                }

                self.insert_node_recursively(current_node.left, new_node_id, value);
            } else {
                if current_node.right == 0 {
                    current_node.right = new_node_id;

                    let new_node = self.create_leaf_node(@value, current_id);
                    self.tree.entry(new_node_id).write(new_node);
                    self.tree.entry(current_id).write(current_node);
                    return;
                }

                self.insert_node_recursively(current_node.right, new_node_id, value);
            }
        }

        fn balance_after_insertion(ref self: ComponentState<TContractState>, node_id: felt252) {
            let mut current = node_id;
            let mut current_node: Node = self.tree.entry(current).read();
            while current != self.root.read() && self.is_red(current_node.parent) {
                let parent = current_node.parent;
                let parent_node: Node = self.tree.entry(parent).read();
                let grandparent = parent_node.parent;

                if self.is_left_child(parent) {
                    current = self.balance_left_case(current, parent, grandparent);
                } else {
                    current = self.balance_right_case(current, parent, grandparent);
                }
                current_node = self.tree.entry(current).read();
            };
            self.ensure_root_is_black();
        }

        fn balance_left_case(
            ref self: ComponentState<TContractState>,
            current: felt252,
            parent: felt252,
            grandparent: felt252
        ) -> felt252 {
            let grandparent_node: Node = self.tree.entry(grandparent).read();
            let uncle = grandparent_node.right;

            if self.is_red(uncle) {
                return self.handle_red_uncle(current, parent, grandparent, uncle);
            } else {
                return self.handle_black_uncle_left(current, parent, grandparent);
            }
        }

        fn balance_right_case(
            ref self: ComponentState<TContractState>,
            current: felt252,
            parent: felt252,
            grandparent: felt252
        ) -> felt252 {
            let grandparent_node: Node = self.tree.entry(grandparent).read();
            let uncle = grandparent_node.left;

            if self.is_red(uncle) {
                return self.handle_red_uncle(current, parent, grandparent, uncle);
            } else {
                return self.handle_black_uncle_right(current, parent, grandparent);
            }
        }

        fn handle_red_uncle(
            ref self: ComponentState<TContractState>,
            current: felt252,
            parent: felt252,
            grandparent: felt252,
            uncle: felt252
        ) -> felt252 {
            self.set_color(parent, BLACK); // Black
            self.set_color(uncle, BLACK); // Black
            self.set_color(grandparent, RED); // Red
            grandparent
        }

        fn handle_black_uncle_left(
            ref self: ComponentState<TContractState>,
            current: felt252,
            parent: felt252,
            grandparent: felt252
        ) -> felt252 {
            let mut new_current = current;
            if !self.is_left_child(current) {
                new_current = parent;
                self.rotate_left(new_current);
            }
            let mut new_current_node: Node = self.tree.entry(new_current).read();
            let new_parent = new_current_node.parent;
            self.set_color(new_parent, BLACK); // Black
            self.set_color(grandparent, RED); // Red
            self.rotate_right(grandparent);
            new_current
        }

        fn handle_black_uncle_right(
            ref self: ComponentState<TContractState>,
            current: felt252,
            parent: felt252,
            grandparent: felt252
        ) -> felt252 {
            let mut new_current = current;
            if self.is_left_child(current) {
                new_current = parent;
                self.rotate_right(new_current);
            }
            let new_current_node: Node = self.tree.entry(new_current).read();
            let new_parent = new_current_node.parent;
            self.set_color(new_parent, BLACK); // Black
            self.set_color(grandparent, RED); // Red
            self.rotate_left(grandparent);
            new_current
        }
    }

    #[generate_trait]
    impl RBTreeRotations<
        TContractState, +HasComponent<TContractState>
    > of RBTreeRotationsTrait<TContractState> {
        fn rotate_right(ref self: ComponentState<TContractState>, y: felt252) -> felt252 {
            let mut y_node: Node = self.tree.entry(y).read();
            let x = y_node.left;
            let x_node: Node = self.tree.entry(x).read();
            let B = x_node.right;

            // Perform rotation
            self.update_right(x, y);
            self.update_left(y, B);

            // Update parent pointers
            // Is read again required?
            y_node = self.tree.entry(y).read();
            let y_parent = y_node.parent;
            self.update_parent(x, y_parent);
            self.update_parent(y, x);
            if B != 0 {
                self.update_parent(B, y);
            }

            // Update root if necessary
            if y_parent == 0 {
                self.root.write(x);
            } else {
                let mut parent: Node = self.tree.entry(y_parent).read();

                if parent.left == y {
                    parent.left = x;
                } else {
                    parent.right = x;
                }
                self.tree.entry(y_parent).write(parent);
            }

            // Return the new root of the subtree
            x
        }

        fn rotate_left(ref self: ComponentState<TContractState>, x: felt252) -> felt252 {
            let mut x_node: Node = self.tree.read(x);
            let y = x_node.right;
            let y_node: Node = self.tree.read(y);
            let B = y_node.left;

            // Perform rotation
            self.update_left(y, x);
            self.update_right(x, B);

            // Update parent pointers
            x_node = self.tree.entry(x).read();
            let x_parent = x_node.parent;
            self.update_parent(y, x_parent);
            self.update_parent(x, y);
            if B != 0 {
                self.update_parent(B, x);
            }

            // Update root if necessary
            if x_parent == 0 {
                self.root.write(y);
            } else {
                let mut parent: Node = self.tree.entry(x_parent).read();
                if parent.left == x {
                    parent.left = y;
                } else {
                    parent.right = y;
                }
                self.tree.entry(x_parent).write(parent);
            }

            // Return the new root of the subtree
            y
        }
    }
}
