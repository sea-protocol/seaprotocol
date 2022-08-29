/// # Module-level documentation sections
///
/// * [Background](#Background)
/// * [Implementation](#Implementation)
/// * [Basic public functions](#Basic-public-functions)
/// * [Traversal](#Traversal)
///
/// # Background
///
/// A rbtree (red black tree) is a kind of self-balancing binary search tree.
/// Each node stores an extra bit representing "color" ("red" or "black"), used
/// to ensure that the tree remains balanced during insertions and deletions.
/// When the tree is modified, the new tree is rearranged and "repainted" to 
/// restore the coloring properties that constrain how unbalanced the tree can 
/// become in the worst case. The properties are designed such that this rearranging 
/// and recoloring can be performed efficiently.
/// The re-balancing is not perfect, but guarantees searching in O(logn) time, 
/// where n is the number of entries. The insert and delete operations, along 
/// with the tree rearrangement and recoloring, are also performed in O(logn) time.
///
/// code:
/// https://github.com/torvalds/linux/blob/master/include/linux/rbtree.h
/// https://github.com/torvalds/linux/blob/master/include/linux/rbtree_types.h
/// https://github.com/tickbh/rbtree-rs
/// 
module sea::rbtree {
    use std::vector;

    /// A rbtree node
    struct RBNode<V> has store {
        // color is the first 1 bit
        // pos is the follow 31 bits
        // parent is the last 32 bits
        color_parent: u64,
        // left is the first 32 bits
        // right is the last 32 bits
        left_right: u64,
        // this is the key of the node, just use u128 for simplity and storage efficient
        key: u128,
        value: V
    }

    /// A rbtree for key-value pairs with value type `V`
    /// all vector index + 1
    /// nodes should less than 0x7fffffff
    struct RBTree<V> has store {
        /// Root node index
        root: u64,
        /// the left most node index
        leftmost: u64,
        nodes: vector<RBNode<V>>
    }

    // Constants ====================================================
    const U64_MASK: u64 = 0xffffffffffffffff;
    const COLOR_MASK: u64 = 0x8000000000000000;
    const POS_MASK: u64 = 0x7fffffff00000000;
    const PARENT_MASK: u64 = 0x00000000ffffffff;
    const LEFT_MASK: u64  = 0xffffffff00000000;
    const RIGHT_MASK: u64 = 0x00000000ffffffff;
    const RED: u64 = 0x8000000000000000;
    const BLACK: u64 = 0;
    const BLACK_MASK: u64 = 0x7fffffffffffffff;
    const RED_NULL_PARENT: u64 = 0x8000000000000000;
    const BLACK_NULL_PARENT: u64 = 0x0;
    const NULL_LEFT_RIGHT: u64 = 0x0;
    const MAX_NODES_LEN: u64 = 0x7fffffff;

    // Errors ====================================================
    const E_INSERT_FULL: u64   = 1;
    const E_DUP_KEY: u64       = 2;
    const E_NOT_FOUND_KEY: u64 = 3;

    /// Return an empty tree
    public fun empty<V>(): RBTree<V> {
        RBTree{
            root: 0,
            leftmost: 0,
            nodes: vector::empty<RBNode<V>>()
        }
    }

    /// Return a tree with one node having `key` and `value`
    public fun singleton<V>(
        key: u128,
        value: V
    ): RBTree<V> {
        RBTree{
            root: 1,
            leftmost: 1,
             // the root node is BLACK node
            nodes: vector::singleton<RBNode<V>>(create_rb_node(false, 1, key, value))
        }
    }

    /// Return `true` if `tree` has no outer nodes
    public fun is_empty<V>(tree: &RBTree<V>): bool {
        vector::is_empty<RBNode<V>>(&tree.nodes)
    }

    /// Return length of tree
    public fun length<V>(tree: &RBTree<V>): u64 {
        vector::length<RBNode<V>>(&tree.nodes)
    }

    /// insert a new node with key & value
    public fun rb_insert<V>(
        tree: &mut RBTree<V>,
        key: u128,
        value: V) {
        assert!(length<V>(tree) < MAX_NODES_LEN, E_INSERT_FULL);

        let node: RBNode<V>;
        if (is_empty(tree)) {
            // the root node is BLACK
            node = create_rb_node(false, 1, key, value);
            tree.leftmost = 1;
            tree.root = 1;
        } else {
            let pos = length(tree)+1;
            node = create_rb_node(true, pos, key, value);
            rb_insert_node(tree, &mut node, pos, key);
        };

        // push value, rbnode to vector
        vector::push_back(&mut tree.nodes, node);
    }

    /// find node position
    public fun rb_find<V>(
        tree: &RBTree<V>,
        key: u128): u64 {
        if (is_empty(tree)) {
            return 0
        };
        let idx = tree.root;
        loop {
            let node = get_node(&tree.nodes, idx);
            if (key == node.key) {
                return idx
            };
            if (key < node.key) {
                idx = get_left_index(node.left_right);
            } else {
                idx = get_right_index(node.left_right);
            };
            if (idx == 0) {
                return 0
            }
        }
    }

    public fun rb_remove_by_key<V>(
        tree: &mut RBTree<V>,
        key: u128) {
        let pos = rb_find(tree, key);
        if (pos == 0) {
            return
        };

        rb_remove_node(tree, pos);
    }

    public fun rb_remove_by_pos<V>(
        tree: &mut RBTree<V>,
        pos: u64) {
        if (is_empty(tree)) {
            return
        };
        rb_remove_node(tree, pos);
    }

    // Private functions ====================================================

    fun is_red(color: u64): bool {
        color & COLOR_MASK == RED
    }

    fun is_black(color: u64): bool {
        color & COLOR_MASK == BLACK
    }

    fun get_left_index(index: u64): u64 {
        (index & LEFT_MASK) >> 32
    }

    fun get_right_index(index: u64): u64 {
        index & RIGHT_MASK
    }

    fun get_left_right_index(index: u64): (u64, u64) {
        ((index & LEFT_MASK) >> 32, index & RIGHT_MASK)
    }

    fun get_parent_index(index: u64): u64 {
        index & PARENT_MASK
    }

    fun get_position(index: u64): u64 {
        (index & POS_MASK) >> 32
    }

    /// create a RBNode, without parent, left, right links
    fun create_rb_node<V>(
        is_red: bool,
        pos: u64,
        key: u128,
        val: V): RBNode<V> {
        let color_parent: u64;
        if (is_red) {
            color_parent = RED_NULL_PARENT | (pos << 32);
        } else {
            color_parent = (pos << 32);
        };
        RBNode{
            color_parent: color_parent,
            left_right: NULL_LEFT_RIGHT,
            key: key,
            value: val
        }
    }

    // tree is NOT empty
    fun rb_remove_node<V>(
        tree: &mut RBTree<V>,
        pos: u64) {
        let nodes = &mut tree.nodes;
        let node = get_node_mut(nodes, pos);
        let node_pos = get_position(node.color_parent);
        let (left, right) = get_left_right_index(node.left_right);
        let child_pos: u64;
        let parent_pos: u64;

        // both left child and right child is NOT null
        if (left != 0 && right != 0) {
            let replace = get_node_least_node(nodes, node);
            let replace_pos = get_position(replace.color_parent);
            if (is_root(tree.root, node_pos)) {
                tree.root = replace_pos;
            } else {
                let node_parent = get_node_mut(nodes, get_parent_index(node.color_parent));
                if (is_left_child(node_parent.left_right, node_pos)) {
                    set_node_left(node_parent, replace_pos);
                } else {
                    set_node_right(node_parent, replace_pos);
                }
            };
            child_pos = get_right_index(replace.left_right);
            let parent: &mut RBNode<V>;
            parent_pos = get_parent_index(replace.color_parent);
            if (node_pos == parent_pos) {
                parent_pos = replace_pos;
            } else {
                if (child_pos != 0) {
                    // set child parent
                    let child = get_node_mut(nodes, child_pos);
                    set_node_parent(child, parent_pos);
                };
                let parent = get_node_mut(nodes, parent_pos);
                set_node_left(parent, child_pos);
                let node_right = get_node_mut(nodes, get_right_index(node.left_right));
                set_node_parent(node_right, replace_pos);
            };
            if (is_black(replace.color_parent))  {
                // 
                rb_delete_rebalance(tree, child_pos, parent_pos);
            };
            // last vector swap
            return
        };

        if (left != 0) {
            child_pos = get_left_index(node.left_right);
        } else {
            child_pos = get_right_index(node.left_right);
        };
        parent_pos = get_parent_index(node.color_parent);
        if (child_pos != 0) {
            let child = get_node_mut(nodes, child_pos);
            set_node_parent(child, parent_pos);
        };
        if (is_root(tree.root, node_pos)) {
            tree.root = child_pos;
        } else {
            let parent = get_node_mut(nodes, parent_pos);
            if (is_left_child(parent.left_right, node_pos)) {
                set_node_left(parent, child_pos);
            } else {
                set_node_right(parent, child_pos);
            }
        };
        if (is_black(node.color_parent)) {
            rb_delete_rebalance(tree, child_pos, parent_pos);
        }
    }

    fun rb_delete_rebalance<V>(
        tree: &mut RBTree<V>,
        node_pos: u64,
        parent_pos: u64) {
        let node = get_node_mut(tree.nodes, node_pos);
        let other: &mut RBNode<V>;

        while ((!is_root(tree.root, node_pos)) && (is_black(node.color_parent))) {
            let parent = get_node_mut(tree.nodes, parent_pos);
            if (is_left_child(parent.left_right, node_pos)) {
                other = get_node_mut(tree.nodes, get_right_index(parent.left_right));
                if (is_red(other.color_parent)) {
                    set_black_color(other);
                    set_red_color(parent);
                    left_rotate(tree, parent);
                    other = get_node_mut(tree.nodes, get_right_index(parent.left_right));
                };

                // both left and right child is black 
                if (is_left_child_black(tree, other) && is_right_child_black(tree, other)) {
                    set_red_color(other);
                    node  = parent;
                    node_pos = get_position(node);
                    parent = get_node_mut(tree.nodes, get_parent_index(node.color_parent));
                } else {
                    // x brother w is black, and w left child is red, right child is black
                    if (is_right_child_black(tree.nodes, other)) {
                        set_node_color(nodes, get_left_index(other.left_right), false);
                        set_red_color(other);
                        right_rotate(tree, other);
                        other = get_node_mut(tree.nodes, get_right_index(parent.left_right)); 
                    };
                    set_node_color(nodes, other, is_red(parent.color_parent));
                    set_black_color(parent);
                    set_node_color(nodes, get_right_index(other.left_right), false);
                    left_rotate(tree, parent);
                    node = get_node_mut(tree.nodes, tree.root);
                    break;
                }
            } else {
                other = get_node_mut(tree.nodes, get_left_index(parent.left_right));
                if (is_red(other)) {
                    set_black_color(other);
                    set_red_color(parent);
                    right_rotate(tree, parent);
                    other = get_node_mut(tree.nodes, get_left_index(parent.left_right));
                };

                if (is_left_child_black(tree, other) && is_right_child_black(tree, other)) {
                    set_red_color(other);
                    node = parent;
                    node_pos = get_position(node);
                    parent = get_node_mut(tree.nodes, get_parent_index(node.color_parent));
                } else {
                    if (is_left_child_black(tree.nodes, other)) {
                        set_node_color(nodes, get_right_index(other.left_right), false);
                        set_red_color(other);
                        left_rotate(tree, other);
                        other = get_node_mut(tree.nodes, get_left_index(parent.left_right)); 
                    };
                    set_node_color(nodes, other, is_red(parent.color_parent));
                    set_black_color(parent);
                    set_node_color(nodes, get_left_index(other.left_right), false);
                    right_rotate(tree, parent);
                    node = get_node_mut(tree.nodes, tree.root);
                    break;
                }
            }
        };
        
        set_black_color(node);
    }

    fun set_node_color<V>(nodes: &vector<RBNode<V>>, pos: u64, is_red: bool) {
        if (pos == 0) {
            return
        };
        let node = get_node_mut(nodes, pos);
        if (is_red) {
            set_red_color(node);
        } else {
            set_black_color(node);
        }
    }
    // left child is black or nil
    fun is_left_child_black<V>(
        nodes: &vector<RBNode<V>>,
        node: &RBNode<V>): bool {
        let left = get_left_index(node.left_right);
        if (left == 0) {
            return true
        };
        let left_node = get_node(nodes, left);
        return is_black(left_node.color_parent)
    }

    fun is_right_child_black<V>(
        nodes: &vector<RBNode<V>>,
        node: &RBNode<V>): bool {
        let right = get_right_index(node.left_right);
        if (right == 0) {
            return true
        };
        let right_node = get_node(nodes, right);
        return is_black(right_node.color_parent)
    }

    fun get_node_least_node<V>(
        nodes: &vector<RBNode<V>>,
        node: &RBNode<V>): &RBNode<V> {
        let tmp: &RBNode<V> = node;
        loop {
            let left = get_left_index(tmp.left_right);
            if (left == 0) {
                return tmp
            };
            tmp = get_node(nodes, left);
        }
    }

    /// insert/link node into the rbtree
    fun rb_insert_node<V>(
        tree: &mut RBTree<V>,
        node: &mut RBNode<V>,
        node_pos: u64,
        key: u128) {
        // here, the tree should NOT be empty
        let parent_pos = tree.root;
        let parent: &mut RBNode<V>;
        let is_least = true;

        // find the parent
        loop {
            parent = get_node_mut<V>(&mut tree.nodes, parent_pos);
            assert!(key != parent.key, E_DUP_KEY);
            if (key < parent.key) {
                // left
                let left = get_left_index(parent.left_right);
                if (left == 0) {
                    set_parent_child(parent, node, parent_pos, node_pos);
                    break
                };
                parent_pos = left;
            } else {
                is_least = false;
                // right
                let right = get_right_index(parent.left_right);
                if (right == 0) {
                    set_parent_child(parent, node, parent_pos, node_pos);
                    break
                };
                parent_pos = right;
            }
        };
        if (is_least) {
            // set_leftmost_index(tree, node_pos);
            tree.leftmost = node_pos;
        };
        if (is_black(parent.color_parent)) {
            // the parent is BLACK node, done
            return
        };
        // rebalance the rbtree
        rb_insert_rebalance<V>(tree, parent, node);
    }

    fun is_left_child(left_right: u64, child_pos: u64): bool {
        get_left_index(left_right) == child_pos
    }

    fun is_right_child(left_right: u64, child_pos: u64): bool {
        get_right_index(left_right) == child_pos
    }

    fun flip_color<V>(
        grandad: &mut RBNode<V>,
        parent: &mut RBNode<V>,
        uncle: &mut RBNode<V>) {
        set_red_color(grandad);
        set_black_color(uncle);
        set_black_color(parent);
    }

    fun rb_insert_rebalance<V>(
        tree: &mut RBTree<V>,
        parent: &mut RBNode<V>,
        node: &mut RBNode<V>) {
        let node_pos = get_position(node.color_parent);
        while(is_red(parent.color_parent)) {
            let grandad: &mut RBNode<V> = get_node_mut(&mut tree.nodes, get_parent_index(parent.color_parent));
            let parent_pos = get_position(parent.color_parent);
            // parent is the left child of grandad
            if (is_left_child(grandad.left_right, parent_pos)) {
                let uncle_pos = get_right_index(grandad.left_right);
                let uncle: &mut RBNode<V>;

                // Case 1: uncle is not null and uncle is red node
                if (uncle_pos != 0) {
                    uncle = get_node_mut(&mut tree.nodes, uncle_pos);
                    // Case 1: uncle is null or uncle is red node
                    if (is_red(uncle.color_parent)) {
                        flip_color(grandad, parent, uncle);
                        node = grandad;
                        parent = get_node_mut(&mut tree.nodes, get_parent_index(node.color_parent));
                        continue
                    }
                };
                // Case 2: uncle is black, and node is right node
                if (is_right_child(parent.left_right, node_pos)) {
                    left_rotate(tree, parent);
                    let temp = parent;
                    parent = node;
                    node = temp;
                };
                // Case 3: uncle is black, and node is left node
                set_black_color(parent);
                set_red_color(grandad);
                right_rotate(tree, grandad);
            } else {
                // Case 1: uncle is red
                let uncle_pos = get_left_index(grandad.left_right);
                let uncle: &mut RBNode<V>;
                if (uncle_pos != 0) {
                    uncle = get_node_mut(&mut tree.nodes, uncle_pos);
                    // Case 1: uncle is null or uncle is red node
                    if (is_red(uncle.color_parent)) {
                        flip_color(grandad, parent, uncle);
                        node = grandad;
                        parent = get_node_mut(&mut tree.nodes, get_parent_index(node.color_parent));
                        continue
                    };
                };
                    // Case 2: uncle is black, and node is right child
                    if (is_right_child(parent.left_right, node_pos)) {
                        right_rotate(tree, parent);
                        let temp = parent;
                        parent = node;
                        node = temp;
                    };
                    // Case 3: uncle is black andd nodee is left child
                    set_black_color(parent);
                    set_red_color(grandad);
                    left_rotate(tree, grandad);
            }
        };
        set_black_color(get_node_mut(&mut tree.nodes, tree.root));
    }
    
    /*
     *
     *      px                              px
     *     /                               /
     *    x                               y
     *   /  \            -->             / \                #
     *  lx   y                          x  ry
     *     /   \                       /  \
     *    ly   ry                     lx  ly
     *
     *  node: x
     */
    fun left_rotate<V>(
        tree: &mut RBTree<V>,
        node: &mut RBNode<V>) {
        let node_pos = get_position(node.color_parent);
        let px_pos = get_parent_index(node.color_parent);
        let nodes = &mut tree.nodes;
        let y: &mut RBNode<V> = get_node_right_child(nodes, node);
        let y_pos = get_position(y.color_parent);

        set_node_right(node, get_right_index(y.left_right));

        let ly_index = get_left_index(y.left_right);
        if (ly_index != 0) {
            let ly: &mut RBNode<V> = get_node_mut(nodes, ly_index);
            set_node_parent<V>(ly, node_pos);
        };
        set_node_parent(y, px_pos);
        if (is_root(tree.root, node_pos)) {
            tree.root = get_position(y.color_parent);
        } else {
            let grandad = get_node_mut(nodes, px_pos);
            if (is_left_child(grandad.left_right, node_pos)) {
                set_node_left(grandad, y_pos);
            } else {
                set_node_right(grandad, y_pos);
            }
        };
        set_node_left(y, node_pos);
        set_node_parent(node, y_pos);
    }

    fun is_root(root: u64,
        node_pos: u64): bool {
        root == node_pos
    }
    /*
     *
     *            py                               py
     *           /                                /
     *          y                                x
     *         /  \           ---->             /  \                     #
     *        x   ry                           lx   y
     *       / \                                   / \                   #
     *      lx  rx                                rx  ry
     *
     *  node: y
     */
    fun right_rotate<V>(
        tree: &mut RBTree<V>,
        node: &mut RBNode<V>) {
        let node_pos = get_position(node.color_parent);
        let py_pos = get_parent_index(node.color_parent);
        let nodes = &mut tree.nodes;
        let x: &mut RBNode<V> = get_node_left_child(nodes, node);
        let x_pos = get_position(x.color_parent);

        set_node_left(node, get_left_index(x.left_right));
        let rx_index = get_right_index(x.left_right);
        if (rx_index > 0) {
            let rx = get_node_mut(nodes, rx_index);
            set_node_parent(rx, node_pos);
        };

        set_node_parent(x, py_pos);
        if (is_root(tree.root, node_pos)) {
            tree.root = get_position(x.color_parent);
        } else {
            let grandad = get_node_mut(nodes, py_pos);
            if (is_right_child(grandad.left_right, node_pos)) {
                set_node_right(grandad, x_pos);
            } else {
                set_node_left(grandad, x_pos);
            }
        };
        set_node_right(x, node_pos);
        set_node_parent(node, x_pos);
    }

    fun set_red_color<V>(node: &mut RBNode<V>) {
        node.color_parent = node.color_parent | RED;
    }
    
    fun set_black_color<V>(node: &mut RBNode<V>) {
        node.color_parent = node.color_parent & BLACK_MASK;
    }

    fun set_node_parent<V>(node: &mut RBNode<V>, parent_pos: u64) {
        node.color_parent =  node.color_parent | parent_pos;
    }

    fun set_node_left<V>(node: &mut RBNode<V>, left_pos: u64) {
        node.left_right =  node.left_right | (left_pos << 32);
    }

    fun set_node_right<V>(node: &mut RBNode<V>, right_pos: u64) {
        node.left_right =  node.left_right | right_pos;
    }
    
    /// set parent left child or right child
    fun set_parent_child<V>(
        parent: &mut RBNode<V>,
        child: &mut RBNode<V>,
        parent_pos: u64,
        child_pos: u64) {
        if (parent.key > child.key) {
            // left child
            set_node_left(parent, child_pos);
        } else {
            // right child
            set_node_right(parent, child_pos);
        };
        set_node_parent<V>(child, parent_pos);
    }

    fun get_node<V>(
        nodes: &vector<RBNode<V>>,
        index: u64): &RBNode<V> {
        vector::borrow<RBNode<V>>(nodes, index)
    }

    fun get_node_mut<V>(
        nodes: &mut vector<RBNode<V>>,
        index: u64): &mut RBNode<V> {
        vector::borrow_mut<RBNode<V>>(nodes, index)
    }

    fun get_node_left_index<V>(
        tree: &mut RBTree<V>,
        pos: u64): u64 {
        get_left_index(vector::borrow<RBNode<V>>(&tree.nodes, pos).left_right)
    }

    fun get_node_left_child<V>(
        nodes: &mut vector<RBNode<V>>,
        node: &RBNode<V>): &mut RBNode<V> {
        vector::borrow_mut<RBNode<V>>(nodes, get_left_index(node.left_right))
    }

    fun get_node_right_index<V>(
        tree: &mut RBTree<V>,
        pos: u64): u64 {
        get_right_index(vector::borrow<RBNode<V>>(&tree.nodes, pos).left_right)
    }

    fun get_node_right_child<V>(
        nodes: &mut vector<RBNode<V>>,
        node: &RBNode<V>): &mut RBNode<V> {
        vector::borrow_mut<RBNode<V>>(nodes, get_right_index(node.left_right))
    }

    fun get_node_left_right_index<V>(
        tree: &mut RBTree<V>,
        pos: u64): (u64, u64) {
        let left_right = vector::borrow<RBNode<V>>(&tree.nodes, pos).left_right;
        (get_left_index(left_right), get_right_index(left_right))
    }
    // Test-only functions ====================================================

}
