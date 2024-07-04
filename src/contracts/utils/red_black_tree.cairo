#[starknet::interface]
trait IRBTree<TContractState> {
    fn insert(ref self: TContractState, value: u256);
    fn delete(ref self: TContractState, value: u256);
    fn get_root(self: @TContractState) -> felt252;
    fn traverse_postorder(ref self: TContractState);
    fn get_height(ref self: TContractState) -> u256;
    fn display_tree(ref self: TContractState);
    fn get_tree_structure(ref self: TContractState) -> Array<Array<(u256, bool, u256)>>;
    fn is_tree_valid(ref self: TContractState) -> bool;
}

const BLACK: bool = false;
const RED: bool = true;


#[starknet::component]
pub mod rb_tree_component {
    use super::{BLACK, RED};
    use core::{array::ArrayTrait, option::OptionTrait, traits::{IndexView, TryInto}};

    #[storage]
    struct Storage {
        root: felt252,
        tree: LegacyMap::<felt252, Node>,
        node_position: LegacyMap::<felt252, u256>,
        next_id: felt252,
    }

    #[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
    struct Node {
        value: u256,
        left: felt252,
        right: felt252,
        parent: felt252,
        color: bool,
    }

    // #[constructor]
    // fn constructor(ref self: ComponentState<TContractState>) {
    //     self.root.write(0);
    //     self.next_id.write(1);
    // }

    #[event]
    #[derive(Drop, starknet::Event, PartialEq)]
    pub enum Event {
       InsertEvent:InsertEvent
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct InsertEvent {
        node:Node,
    }


    #[embeddable_as(RBTree)]
    impl RBTreeImpl<
        TContractState, +HasComponent<TContractState>
    > of super::IRBTree<ComponentState<TContractState>> {
        fn insert(ref self: ComponentState<TContractState>, value: u256) {
            let new_node_id = self.create_new_node(value);

            if self.root.read() == 0 {
                self.root.write(new_node_id);
                return;
            }

            self.insert_node_recursively(self.root.read(), new_node_id, value);
            self.balance_after_insertion(new_node_id);
        }

        fn delete(ref self: ComponentState<TContractState>, value: u256) {
            let node_to_delete_id = self.find_node(self.root.read(), value);
            if node_to_delete_id == 0 {
                return;
            }
            self.delete_node(node_to_delete_id);
        }

        fn get_root(self: @ComponentState<TContractState>) -> felt252 {
            self.root.read()
        }

        fn traverse_postorder(ref self: ComponentState<TContractState>) {
            self.traverse_postorder_from_node(self.root.read());
        }

        fn get_height(ref self: ComponentState<TContractState>) -> u256 {
            return self.get_sub_tree_height(self.root.read());
        }

        fn display_tree(ref self: ComponentState<TContractState>) {
            self.display_tree_structure(self.root.read());
        }

        fn get_tree_structure(
            ref self: ComponentState<TContractState>
        ) -> Array<Array<(u256, bool, u256)>> {
            self.build_tree_structure_list()
        }

        fn is_tree_valid(ref self: ComponentState<TContractState>) -> bool {
            self.check_if_rb_tree_is_valid()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        fn traverse_postorder_from_node(
            ref self: ComponentState<TContractState>, current_id: felt252
        ) {
            if (current_id == 0) {
                return;
            }
            let current_node = self.tree.read(current_id);

            self.traverse_postorder_from_node(current_node.right);
            println!("{}", current_node.value);
            self.traverse_postorder_from_node(current_node.left);
        }

        fn find_node(
            ref self: ComponentState<TContractState>, current: felt252, value: u256
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
            value: u256
        ) {
            let mut current_node: Node = self.tree.read(current_id);

            if (value == current_node.value) {
                return;
            } else if value < current_node.value {
                if current_node.left == 0 {
                    current_node.left = new_node_id;

                    // update parent
                    self.update_parent(new_node_id, current_id);

                    self.tree.write(current_id, current_node);
                    return;
                }

                self.insert_node_recursively(current_node.left, new_node_id, value);
            } else {
                if current_node.right == 0 {
                    current_node.right = new_node_id;

                    // update parent
                    self.update_parent(new_node_id, current_id);

                    self.tree.write(current_id, current_node);
                    return;
                }

                self.insert_node_recursively(current_node.right, new_node_id, value);
            }
        }

        fn create_new_node(ref self: ComponentState<TContractState>, value: u256) -> felt252 {
            let new_node_id = self.next_id.read();
            self.next_id.write(new_node_id + 1);

            let mut color = RED;
            if (self.root.read() == 0) {
                color = BLACK;
            }

            let new_node = Node { value, left: 0, right: 0, parent: 0, color: color };

            self.tree.write(new_node_id, new_node);
            return new_node_id;
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

        fn get_sub_tree_height(ref self: ComponentState<TContractState>, node_id: felt252) -> u256 {
            let node = self.tree.read(node_id);

            if (node_id == 0) {
                return 0;
            } else {
                let left_height = self.get_sub_tree_height(node.left);
                let right_height = self.get_sub_tree_height(node.right);

                if (left_height > right_height) {
                    return left_height + 1;
                } else {
                    return right_height + 1;
                }
            }
        }

        fn power(ref self: ComponentState<TContractState>, base: u256, exponent: u256) -> u256 {
            let mut result = 1;
            let mut i = 0;
            while i < exponent {
                result *= base;
                i += 1;
            };
            return result;
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
            if delete_id == 0 {
                return; // Node not found
            }

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
                        if self.is_red(w) {
                            self.set_color(w, BLACK);
                            self.set_color(x_parent, RED);
                            self.rotate_left(x_parent);
                            x_parent_node = self.tree.read(x_parent);
                            w = x_parent_node.right;
                        }
                        let mut w_node: Node = self.tree.read(w);
                        if (w_node.left == 0 || self.is_black(w_node.left))
                            && (w_node.right == 0 || self.is_black(w_node.right)) {
                            self.set_color(w, RED);
                            x = x_parent;
                            x_parent = self.get_parent(x);
                        } else {
                            if w_node.right == 0 || self.is_black(w_node.right) {
                                if w_node.left != 0 {
                                    self.set_color(w_node.left, BLACK);
                                }
                                self.set_color(w, RED);
                                self.rotate_right(w);
                                w = w_node.right;
                            }
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
                        if self.is_red(w) {
                            self.set_color(w, BLACK);
                            self.set_color(x_parent, RED);
                            self.rotate_right(x_parent);
                            x_parent_node = self.tree.read(x_parent);
                            w = x_parent_node.left;
                        }
                        let mut w_node: Node = self.tree.read(w);
                        if (w_node.right == 0 || self.is_black(w_node.right))
                            && (w_node.left == 0 || self.is_black(w_node.left)) {
                            self.set_color(w, RED);
                            x = x_parent;
                            x_parent = self.get_parent(x);
                        } else {
                            if w_node.left == 0 || self.is_black(w_node.left) {
                                if w_node.right != 0 {
                                    self.set_color(w_node.right, BLACK);
                                }
                                self.set_color(w, RED);
                                self.rotate_left(w);
                                x_parent_node = self.tree.read(x_parent);
                                w = x_parent_node.left;
                            }
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
    impl PrintRBTree<
        TContractState, +HasComponent<TContractState>
    > of PrintRBTreeTrait<TContractState> {
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

        fn display_tree_structure(ref self: ComponentState<TContractState>, node_id: felt252) {
            println!("");

            let root_id = self.root.read();
            if root_id == 0 {
                println!("Tree is empty");
                return;
            }

            let tree_height = self.get_height();
            let no_of_levels = tree_height - 1;

            if no_of_levels == 0 {
                self.render_single_node(root_id);
                return;
            }

            let node_positions_by_level = self.get_node_positions_by_level();
            let all_nodes = self.build_complete_tree_representation(@node_positions_by_level);

            let (mut middle_spacing, mut begin_spacing) = self
                .calculate_initial_spacing(no_of_levels);

            self.render_tree_levels(all_nodes, no_of_levels, ref middle_spacing, ref begin_spacing);

            println!("");
        }

        fn render_single_node(ref self: ComponentState<TContractState>, node_id: felt252) {
            let root_node: Node = self.tree.read(node_id);
            if root_node.value < 10 {
                print!("0");
            }
            println!("{}B", root_node.value);
        }

        fn calculate_initial_spacing(
            ref self: ComponentState<TContractState>, no_of_levels: u256
        ) -> (u256, u256) {
            let middle_spacing = 3 * self.power(2, no_of_levels)
                + 5 * self.power(2, no_of_levels - 1)
                + 3 * (self.power(2, no_of_levels - 1) - 1);
            let begin_spacing = (middle_spacing - 3) / 2;
            (middle_spacing, begin_spacing)
        }

        fn render_tree_levels(
            ref self: ComponentState<TContractState>,
            all_nodes: Array<Array<felt252>>,
            no_of_levels: u256,
            ref middle_spacing: u256,
            ref begin_spacing: u256
        ) {
            let mut i = 0;
            loop {
                if i >= all_nodes.len().try_into().unwrap() {
                    break;
                }
                let level = all_nodes.at(i.try_into().unwrap());
                self.render_level(level, i, no_of_levels, begin_spacing, middle_spacing);

                if i < no_of_levels.try_into().unwrap() {
                    middle_spacing = begin_spacing;
                    begin_spacing = (begin_spacing - 3) / 2;
                }

                println!("");
                i += 1;
            }
        }

        fn render_level(
            ref self: ComponentState<TContractState>,
            level: @Array<felt252>,
            level_index: u256,
            no_of_levels: u256,
            begin_spacing: u256,
            middle_spacing: u256
        ) {
            let mut j = 0_u256;
            loop {
                if j >= level.len().try_into().unwrap() {
                    break;
                }
                let node_id = *level.at(j.try_into().unwrap());

                self
                    .print_node_spacing(
                        j, level_index, no_of_levels, begin_spacing, middle_spacing
                    );
                self.print_node(node_id);

                j += 1;
            }
        }

        fn print_node_spacing(
            ref self: ComponentState<TContractState>,
            node_index: u256,
            level_index: u256,
            no_of_levels: u256,
            begin_spacing: u256,
            middle_spacing: u256
        ) {
            if node_index == 0 {
                self.print_n_spaces(begin_spacing);
            } else if level_index == no_of_levels {
                if node_index % 2 == 0 {
                    self.print_n_spaces(3);
                } else {
                    self.print_n_spaces(5);
                }
            } else {
                self.print_n_spaces(middle_spacing);
            }
        }

        fn print_node(ref self: ComponentState<TContractState>, node_id: felt252) {
            if node_id == 0 {
                print!("...");
            } else {
                let node: Node = self.tree.read(node_id);
                let node_value = node.value;
                let node_color = node.color;

                if node_value < 10 {
                    print!("0");
                }
                print!("{}", node_value);

                if node_color == BLACK {
                    print!("B");
                } else {
                    print!("R");
                }
            }
        }

        fn build_tree_structure_list(
            ref self: ComponentState<TContractState>
        ) -> Array<Array<(u256, bool, u256)>> {
            if (self.root.read() == 0) {
                return ArrayTrait::new();
            }
            let filled_position_in_levels_original = self.get_node_positions_by_level();
            let mut filled_position_in_levels: Array<Array<(u256, bool, u256)>> = ArrayTrait::new();
            let mut filled_position_in_level: Array<(u256, bool, u256)> = ArrayTrait::new();
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

        fn build_complete_tree_representation(
            ref self: ComponentState<TContractState>,
            node_positions_by_level: @Array<Array<(felt252, u256)>>
        ) -> Array<Array<felt252>> {
            let no_of_levels = self.get_height();
            let mut i = 0;
            let mut complete_tree_representation: Array<Array<felt252>> = ArrayTrait::new();
            while i < no_of_levels {
                let node_positions_at_level = node_positions_by_level.at(i.try_into().unwrap());
                let all_nodes_in_level = self.fill_all_nodes_in_level(i, node_positions_at_level);
                complete_tree_representation.append(all_nodes_in_level);
                i = i + 1;
            };
            return complete_tree_representation;
        }

        fn fill_all_nodes_in_level(
            ref self: ComponentState<TContractState>,
            level: u256,
            filled_levels: @Array<(felt252, u256)>
        ) -> Array<felt252> {
            let mut i = 0;
            let max_no_of_nodes = self.power(2, level);
            let mut all_nodes_in_level: Array<felt252> = ArrayTrait::new();
            while i < max_no_of_nodes {
                let node_id = self.get_if_node_id_present(filled_levels, i);
                all_nodes_in_level.append(node_id);
                i += 1;
            };
            return all_nodes_in_level;
        }

        fn get_if_node_id_present(
            ref self: ComponentState<TContractState>,
            filled_levels: @Array<(felt252, u256)>,
            position: u256
        ) -> felt252 {
            let mut i = 0;
            let mut found_node_id = 0;
            // iterate through filled_levels
            while i < filled_levels
                .len() {
                    let (node_id, pos) = filled_levels.at(i.try_into().unwrap());
                    if (pos == @position) {
                        found_node_id = *node_id;
                    }
                    i += 1;
                };

            return found_node_id;
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

        fn print_n_spaces(ref self: ComponentState<TContractState>, n: u256) {
            let mut i = 0;
            while i < n {
                print!(" ");
                i += 1;
            }
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
