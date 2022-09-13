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
    // use std::vector;
    use aptos_framework::coin::Coin;
    use sea::rbtree::{Self, RBTree};

    /// OrderEntity order entity. price, pair_id is on OrderBook
    struct OrderEntity has store {
        // base coin amount
        // we use qty to indicate base amount, vol to indicate quote amount
        qty: u64,
        // the grid id or 0 if is not grid
        grid: u64,
        // user address
        user: address
    }

    /// orders with the same price
    struct OrderStep has store {
        qty: u128,
        price: u64,
        orders: vector<OrderEntity>
    }

    struct Pair<phantom CoinType> has store {
        fee: u64,
        pair_id: u64,
        min_tick_size: u64,
        base: Coin<CoinType>,
        quote: Coin<CoinType>,
        asks: RBTree<OrderStep>,
        bids: RBTree<OrderStep>,
    }

    const E_PAIR_NOT_EXIST: u64 = 1;

    /// match buy order, taker is buyer, maker is seller
    /// 
    public fun match_buy(
        pair_id: u64,
        side: bool,
        orderbook: &mut RBTree<OrderStep>,
        taker: &mut OrderEntity
    ) {
        let completed = false;
        while (!rbtree::is_empty(orderbook)) {
            let step = rbtree::borrow_leftmost_val_mut(orderbook);
            if (step.qty <= (taker.qty as u128)) {
                // remove this step from orderbook
            } else {
                completed = true;
                // if the last maker order cannot match anymore
                break
            }
        };

        if (!completed) {
            // place left taker order into orderbook
        }
    }
}
