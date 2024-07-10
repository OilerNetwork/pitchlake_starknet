use pitch_lake_starknet::contracts::{utils::red_black_tree, option_round::OptionRound::Bid};
use starknet::ContractAddress;
#[starknet::interface]
trait IRBTree<TContractState> {
    fn insert(ref self: TContractState, value: Bid);
    fn find(ref self: TContractState, value: Bid) -> felt252;
    fn delete(ref self: TContractState, bid_id: felt252);
    fn find_clearing_price(ref self: TContractState) -> (u256, u256);
    fn get_tree_structure(ref self: TContractState) -> Array<Array<(Bid, bool, u256)>>;
    fn is_tree_valid(ref self: TContractState) -> bool;
    fn _get_total_options_available(self: @TContractState) -> u256;
    fn get_total_options_sold(self: @TContractState) -> u256;
}

const BLACK: bool = false;
const RED: bool = true;

#[starknet::component]
pub mod RBTreeComponent {
    use pitch_lake_starknet::contracts::utils::red_black_tree::IRBTree;
    use super::{BLACK, RED, Bid, ContractAddress};
    use core::{array::ArrayTrait, option::OptionTrait, traits::{IndexView, TryInto}};

    #[storage]
    struct Storage {
        root: felt252,
        tree: LegacyMap::<felt252, Node>,
        nonce: u64,
        node_position: LegacyMap<felt252, u256>,
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

    #[embeddable_as(RBTree)]
    impl RBTreeImpl<
        TContractState, +HasComponent<TContractState>
    > of super::IRBTree<ComponentState<TContractState>> {
        fn insert(ref self: ComponentState<TContractState>, value: Bid) {
            let new_node_id = value.id;

            if self.root.read() == 0 {
                // Write the root node id only after the first node is inserted
                // As we expect the root to be 0 if the tree is empty
                let root_node = self.create_new_node(@value, 0)
                self.tree.write(new_node_id, root_node);
                self.root.write(new_node_id);
                return;
            }

            self.insert_node_recursively(self.root.read(), new_node_id, value);
            self.balance_after_insertion(new_node_id);
            self.nonce.write(self.nonce.read() + 1);
        }

        fn find(ref self: ComponentState<TContractState>, value: Bid) -> felt252 {
            self.find_node(self.root.read(), value)
        }

        fn delete(ref self: ComponentState<TContractState>, bid_id: felt252) {
            let node: Node = self.tree.read(bid_id);
            // Check if bid exists
            if node.value.id == 0 {
                return;
            }
            self.delete_node(bid_id);
        }

        fn find_clearing_price(ref self: ComponentState<TContractState>) -> (u256, u256) {
            let total_options_available = self._get_total_options_available();
            let root: felt252 = self.root.read();
            let root_node: Node = self.tree.read(root);
            let root_bid: Bid = root_node.value;
            let (clearing_felt, remaining_options) = self
                .traverse_postorder_clearing_price_from_node(
                    root, total_options_available, root_bid.price, root
                );
            let clearing_node: Node = self.tree.read(clearing_felt);
            let total_options_sold = total_options_available - remaining_options;
            self.total_options_sold.write(total_options_sold);
            if (remaining_options == 0) {
                self.clearing_bid.write(clearing_felt);
            }
            self.clearing_price.write(clearing_node.value.price);
            (clearing_node.value.price, total_options_sold)
        }

        fn get_tree_structure(
            ref self: ComponentState<TContractState>
        ) -> Array<Array<(Bid, bool, u256)>> {
            self.build_tree_structure_list()
        }

        fn get_total_options_sold(self: @ComponentState<TContractState>) -> u256 {
            self.total_options_sold.read()
        }

        fn _get_total_options_available(self: @ComponentState<TContractState>) -> u256 {
            self.total_options_available.read()
        }

        fn is_tree_valid(ref self: ComponentState<TContractState>) -> bool {
            self.check_if_rb_tree_is_valid()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
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
            let current_node: Node = self.tree.read(current_id);

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
        fn find_node(
            ref self: ComponentState<TContractState>, current: felt252, value: Bid
        ) -> felt252 {
            if current == 0 {
                return 0;
            }

            let node: Node = self.tree.read(current);
            if value == node.value {
                return current;
            } else if value < node.value {
                return self.find_node(node.left, value);
            } else {
                return self.find_node(node.right, value);
            }
        }

        fn insert_node_recursively(
            ref self: ComponentState<TContractState>,
            current_id: felt252,
            new_node_id: felt252,
            value: Bid
        ) {
            let mut current_node: Node = self.tree.read(current_id);
            if value <= current_node.value {
                if current_node.left == 0 {
                    current_node.left = new_node_id;

                    let new_node = self.create_new_node(@value, current_id);
                    self.tree.write(new_node_id, new_node);
                    self.tree.write(current_id, current_node);

                    return;
                }

                self.insert_node_recursively(current_node.left, new_node_id, value);
            } else {
                if current_node.right == 0 {
                    current_node.right = new_node_id;

                    let new_node = self.create_new_node(@value, current_id);
                    self.tree.write(new_node_id, new_node);
                    self.tree.write(current_id, current_node);
                    return;
                }

                self.insert_node_recursively(current_node.right, new_node_id, value);
            }
        }

        fn remove_from_array<T, +Drop<T>, +PartialEq<T>>(
            self: @ComponentState<TContractState>, element: T, mut array: Array<T>
        ) -> Array<T> {
            let mut new_array: Array<T> = array![];
            loop {
                match array.pop_front() {
                    Option::Some(value) => { if (value != element) {
                        new_array.append(value);
                    } },
                    Option::None => { break; }
                }
            };
            new_array
        }

        fn create_new_node(self: @ComponentState<TContractState>, value: @Bid, parent: felt252) -> Node {
            // If the tree is non empty, we insert node as red
            let mut color = RED;

            // If the tree is empty, root node should be black
            if self.root.read() == 0 {
                color = BLACK;
            }

            Node { value: *value, left: 0, right: 0, parent: parent, color: color, }
        }

        fn is_left_child(ref self: ComponentState<TContractState>, node_id: felt252) -> bool {
            let node: Node = self.tree.read(node_id);
            let parent_id = node.parent;
            let parent: Node = self.tree.read(parent_id);
            return parent.left == node_id;
        }

        fn update_left(
            ref self: ComponentState<TContractState>, node_id: felt252, left_id: felt252
        ) {
            let mut node: Node = self.tree.read(node_id);
            node.left = left_id;
            self.tree.write(node_id, node);
        }

        fn update_right(
            ref self: ComponentState<TContractState>, node_id: felt252, right_id: felt252
        ) {
            let mut node: Node = self.tree.read(node_id);
            node.right = right_id;
            self.tree.write(node_id, node);
        }

        fn update_parent(
            ref self: ComponentState<TContractState>, node_id: felt252, parent_id: felt252
        ) {
            let mut node: Node = self.tree.read(node_id);
            node.parent = parent_id;
            self.tree.write(node_id, node);
        }

        fn get_parent(ref self: ComponentState<TContractState>, node_id: felt252) -> felt252 {
            if node_id == 0 {
                0
            } else {
                let node: Node = self.tree.read(node_id);
                node.parent
            }
        }

        fn is_black(ref self: ComponentState<TContractState>, node_id: felt252) -> bool {
            let node: Node = self.tree.read(node_id);
            node_id == 0 || node.color == BLACK
        }

        fn is_red(ref self: ComponentState<TContractState>, node_id: felt252) -> bool {
            if node_id == 0 {
                return false;
            }
            let node: Node = self.tree.read(node_id);
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
            let mut node: Node = self.tree.read(node_id);
            node.color = color;
            self.tree.write(node_id, node);
        }
    }

    #[generate_trait]
    impl DeleteBalance<
        TContractState, +HasComponent<TContractState>
    > of DeleteBalanceTrait<TContractState> {
        fn delete_node(ref self: ComponentState<TContractState>, delete_id: felt252) {
            let mut y = delete_id;
            let mut node_delete: Node = self.tree.read(delete_id);
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
                let y_node: Node = self.tree.read(y);
                y_original_color = y_node.color;
                x = y_node.right;

                if y_node.parent == delete_id {
                    x_parent = y;
                } else {
                    x_parent = y_node.parent;
                    self.transplant(y, x);
                    let mut y_node: Node = self.tree.read(y);
                    node_delete = self.tree.read(delete_id);
                    y_node.right = node_delete.right;
                    self.tree.write(y, y_node);
                    self.update_parent(node_delete.right, y);
                }

                self.transplant(delete_id, y);
                let mut y_node: Node = self.tree.read(y);
                node_delete = self.tree.read(delete_id);
                y_node.left = node_delete.left;
                y_node.color = node_delete.color;
                self.tree.write(y, y_node);
                node_delete = self.tree.read(delete_id);
                self.update_parent(node_delete.left, y);
            }

            if y_original_color == BLACK {
                self.delete_fixup(x, x_parent);
            }

            self.ensure_root_is_black();
        }

        fn delete_fixup(
            ref self: ComponentState<TContractState>, mut x: felt252, mut x_parent: felt252
        ) {
            while x != self.root.read()
                && (x == 0 || self.is_black(x)) {
                    let mut x_parent_node: Node = self.tree.read(x_parent);
                    if x == x_parent_node.left {
                        let mut w = x_parent_node.right;

                        // Case 1: x's sibling w is red
                        if self.is_red(w) {
                            self.set_color(w, BLACK);
                            self.set_color(x_parent, RED);
                            self.rotate_left(x_parent);
                            x_parent_node = self.tree.read(x_parent);
                            w = x_parent_node.right;
                        }
                        let mut w_node: Node = self.tree.read(w);

                        // Case 2: x's sibling w is black, and both of w's children are black
                        if (w_node.left == 0 || self.is_black(w_node.left))
                            && (w_node.right == 0 || self.is_black(w_node.right)) {
                            self.set_color(w, RED);
                            x = x_parent;
                            x_parent = self.get_parent(x);
                        } else {
                            // Case 3: x's sibling w is black, w's left child is red, and w's right child is black
                            if w_node.right == 0 || self.is_black(w_node.right) {
                                if w_node.left != 0 {
                                    self.set_color(w_node.left, BLACK);
                                }
                                self.set_color(w, RED);
                                self.rotate_right(w);
                                w = w_node.right;
                            }

                            // Case 4: x's sibling w is black, and w's right child is red
                            x_parent_node = self.tree.read(x_parent);
                            self.set_color(w, x_parent_node.color);
                            self.set_color(x_parent, BLACK);
                            w_node = self.tree.read(w);
                            if w_node.right != 0 {
                                self.set_color(w_node.right, BLACK);
                            }
                            self.rotate_left(x_parent);
                            x = self.root.read();
                            break;
                        }
                    } else {
                        // Mirror case for right child
                        let mut w = x_parent_node.left;

                        // Case 1 (mirror): x's sibling w is red
                        if self.is_red(w) {
                            self.set_color(w, BLACK);
                            self.set_color(x_parent, RED);
                            self.rotate_right(x_parent);
                            x_parent_node = self.tree.read(x_parent);
                            w = x_parent_node.left;
                        }
                        let mut w_node: Node = self.tree.read(w);

                        // Case 2 (mirror): x's sibling w is black, and both of w's children are black
                        if (w_node.right == 0 || self.is_black(w_node.right))
                            && (w_node.left == 0 || self.is_black(w_node.left)) {
                            self.set_color(w, RED);
                            x = x_parent;
                            x_parent = self.get_parent(x);
                        } else {
                            // Case 3 (mirror): x's sibling w is black, w's right child is red, and w's left child is black
                            if w_node.left == 0 || self.is_black(w_node.left) {
                                if w_node.right != 0 {
                                    self.set_color(w_node.right, BLACK);
                                }
                                self.set_color(w, RED);
                                self.rotate_left(w);
                                x_parent_node = self.tree.read(x_parent);
                                w = x_parent_node.left;
                            }
                            // Case 4 (mirror): x's sibling w is black, and w's left child is red
                            self.set_color(w, x_parent_node.color);
                            self.set_color(x_parent, BLACK);
                            w_node = self.tree.read(w);
                            if w_node.left != 0 {
                                self.set_color(w_node.left, BLACK);
                            }
                            self.rotate_right(x_parent);
                            x = self.root.read();
                            break;
                        }
                    }
                };
            if x != 0 {
                self.set_color(x, BLACK);
            }
        }

        fn transplant(ref self: ComponentState<TContractState>, u: felt252, v: felt252) {
            let u_node = self.tree.read(u);
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
            let mut node: Node = self.tree.read(current);
            while node.left != 0 {
                current = node.left;
                node = self.tree.read(current);
            };
            current
        }
    }

    #[generate_trait]
    impl InsertBalance<
        TContractState, +HasComponent<TContractState>
    > of InsertBalanceTrait<TContractState> {
        fn balance_after_insertion(ref self: ComponentState<TContractState>, node_id: felt252) {
            let mut current = node_id;
            let current_node: Node = self.tree.read(current);
            while current != self.root.read()
                && self
                    .is_red(current_node.parent) {
                        let parent = current_node.parent;
                        let parent_node: Node = self.tree.read(parent);
                        let grandparent = parent_node.parent;

                        if self.is_left_child(parent) {
                            current = self.balance_left_case(current, parent, grandparent);
                        } else {
                            current = self.balance_right_case(current, parent, grandparent);
                        }
                    };
            self.ensure_root_is_black();
        }

        fn balance_left_case(
            ref self: ComponentState<TContractState>,
            current: felt252,
            parent: felt252,
            grandparent: felt252
        ) -> felt252 {
            let grandparent_node: Node = self.tree.read(grandparent);
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
            let grandparent_node: Node = self.tree.read(grandparent);
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
            let mut new_current_node: Node = self.tree.read(new_current);
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
            let new_current_node: Node = self.tree.read(new_current);
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
            let mut y_node: Node = self.tree.read(y);
            let x = y_node.left;
            let x_node: Node = self.tree.read(x);
            let B = x_node.right;

            // Perform rotation
            self.update_right(x, y);
            self.update_left(y, B);

            // Update parent pointers
            // Is read again required?
            y_node = self.tree.read(y);
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
                let mut parent: Node = self.tree.read(y_parent);

                if parent.left == y {
                    parent.left = x;
                } else {
                    parent.right = x;
                }
                self.tree.write(y_parent, parent);
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
            x_node = self.tree.read(x);
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
                let mut parent: Node = self.tree.read(x_parent);
                if parent.left == x {
                    parent.left = y;
                } else {
                    parent.right = y;
                }
                self.tree.write(x_parent, parent);
            }

            // Return the new root of the subtree
            y
        }
    }

    #[generate_trait]
    impl RBTreeStructure<
        TContractState, +HasComponent<TContractState>
    > of RBTreeGetStructureTrait<TContractState> {
        fn get_node_positions_by_level(
            ref self: ComponentState<TContractState>
        ) -> Array<Array<(felt252, u256)>> {
            let mut queue: Array<(felt252, u256)> = ArrayTrait::new();
            let root_id = self.root.read();
            let initial_level = 0;
            let mut current_level = 0;
            let mut filled_position_in_levels: Array<Array<(felt252, u256)>> = ArrayTrait::new();
            let mut filled_position_in_level: Array<(felt252, u256)> = ArrayTrait::new();

            self.collect_position_and_levels_of_nodes(root_id, 0, initial_level);
            queue.append((root_id, 0));

            while !queue
                .is_empty() {
                    let (node_id, level) = queue.pop_front().unwrap();
                    let node = self.tree.read(node_id);

                    if level > current_level {
                        current_level = level;
                        filled_position_in_levels.append(filled_position_in_level);
                        filled_position_in_level = ArrayTrait::new();
                    }

                    let position = self.node_position.read(node_id);

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
            ref self: ComponentState<TContractState>
        ) -> Array<Array<(Bid, bool, u256)>> {
            if (self.root.read() == 0) {
                return ArrayTrait::new();
            }
            let filled_position_in_levels_original = self.get_node_positions_by_level();
            let mut filled_position_in_levels: Array<Array<(Bid, bool, u256)>> = ArrayTrait::new();
            let mut filled_position_in_level: Array<(Bid, bool, u256)> = ArrayTrait::new();
            let mut i = 0;
            while i < filled_position_in_levels_original
                .len() {
                    let level = filled_position_in_levels_original.at(i.try_into().unwrap());
                    let mut j = 0;
                    while j < level
                        .len() {
                            let (node_id, position) = level.at(j.try_into().unwrap());
                            let node = self.tree.read(*node_id);
                            filled_position_in_level.append((node.value, node.color, *position));
                            j += 1;
                        };
                    filled_position_in_levels.append(filled_position_in_level);
                    filled_position_in_level = ArrayTrait::new();
                    i += 1;
                };
            return filled_position_in_levels;
        }

        fn collect_position_and_levels_of_nodes(
            ref self: ComponentState<TContractState>, node_id: felt252, position: u256, level: u256
        ) {
            if node_id == 0 {
                return;
            }

            let node = self.tree.read(node_id);

            self.node_position.write(node_id, position);

            self.collect_position_and_levels_of_nodes(node.left, position * 2, level + 1);
            self.collect_position_and_levels_of_nodes(node.right, position * 2 + 1, level + 1);
        }
    }

    #[generate_trait]
    impl RBTreeValidation<
        TContractState, +HasComponent<TContractState>
    > of RBTreeValidationTrait<TContractState> {
        fn check_if_rb_tree_is_valid(ref self: ComponentState<TContractState>) -> bool {
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

        fn validate_node(ref self: ComponentState<TContractState>, node: felt252) -> (bool, u32) {
            if node == 0 {
                return (true, 1); // Null nodes are considered black
            }

            let node_data = self.tree.read(node);

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
}
