/// # Module-level documentation sections
///
/// * [Background](#Background)
/// * [Implementation](#Implementation)
/// * [Basic public functions](#Basic-public-functions)
/// * [Traversal](#Traversal)
///
/// # Background
///
/// spot pairs
/// 
module sea::spot {
    use aptos_framework::coin::Coin;
    use sea::rbtree::RBTree;

    struct Pair<phantom CoinType> has store {
        fee: u64,
        base: Coin<CoinType>,
        quote: Coin<CoinType>,
        pair_id: u64,
        asks: RBTree<u128>,
        bids: RBTree<u128>,
    }
}
