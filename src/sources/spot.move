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
    use aptos_std::table::{Self, Table};
    use sea::rbtree::{Self, RBTree};
    use std::signer::address_of;

    // Structs ====================================================

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

    struct Pair<phantom BaseType> has store {
        fee: u64,
        pair_id: u64,
        quote_id: u64,
        lot_size: u64,
        price_coefficient: u64, // price coefficient, from 10^1 to 10^12
        base_precision: u64,  // pow(10, quote_decimals) / pow(10, )
        quote_precision: u64,  // pow(10, quote_decimals) / pow(10, )
        base: Coin<BaseType>,
        asks: RBTree<OrderEntity>,
        bids: RBTree<OrderEntity>,
    }

    struct QuoteConfig<phantom QuoteType> has store {
        quote: Coin<QuoteType>,
        tick_size: u64,
        min_notional: u64,
    }

    struct SpotMarket<phantom BaseType, phantom QuoteType> has key {
        n_pair: u64,
        n_quote: u64,
        quotes: Table<u64, QuoteConfig<QuoteType>>,
        pairs: Table<u64, Pair<BaseType>>
    }

    // Constants ====================================================
    const E_PAIR_NOT_EXIST: u64     = 1;
    const E_NO_AUTH: u64            = 2;
    const E_SPOT_MARKET_EXISTS: u64 = 3;
    const E_NO_SPOT_MARKET: u64     = 4;

    // Public functions ====================================================

    /// init spot market
    public fun init_spot_market<BaseType, QuoteType>(account: &signer) {
        assert!(address_of(account) == @sea, E_NO_AUTH);
        assert!(!exists<SpotMarket<BaseType, QuoteType>>(@sea), E_SPOT_MARKET_EXISTS);
        let spot_market = SpotMarket{
            n_pair: 0,
            n_quote: 0,
            quotes: table::new<u64, QuoteConfig<QuoteType>>(),
            pairs: table::new<u64, Pair<BaseType>>(),
        };

        move_to<SpotMarket<BaseType, QuoteType>>(account, spot_market);
    }

    public fun register_quote<BaseType, QuoteType>(
        account: &signer,
        quote: Coin<QuoteType>,
        tick_size: u64,
        min_notional: u64,
    ) acquires SpotMarket {
        assert!(address_of(account) == @sea, E_NO_AUTH);
        assert!(exists<SpotMarket<BaseType, QuoteType>>(@sea), E_NO_SPOT_MARKET);

        let spot_market_ref_mut = borrow_global_mut<SpotMarket<BaseType, QuoteType>>(@sea);

        let quote_id = spot_market_ref_mut.n_quote;
        spot_market_ref_mut.n_quote = spot_market_ref_mut.n_quote + 1;
        table::add(&mut spot_market_ref_mut.quotes, quote_id, QuoteConfig{
            quote: quote,
            tick_size: tick_size,
            min_notional: min_notional
        })
        // todo check this quote NOT in quotes table
        // assert!(table::contains(spot_market_ref_mut, ), );
    }

    // public fun register_pair<BaseType, QuoteType>(
    //     account: &signer,
    //     base: Coin<BaseType>,
    //     quote: Coin<QuoteType>,
    //     quote_id: u64,
    // ) {
    //     // move_to();
    // }

    /// match buy order, taker is buyer, maker is seller
    /// 
    public fun match(
        pair_id: u64,
        side: bool,
        orderbook: &mut RBTree<OrderEntity>,
        taker: &mut OrderEntity
    ) {
        let completed = false;
        while (!rbtree::is_empty(orderbook)) {
            let step = rbtree::borrow_leftmost_val_mut(orderbook);
            if (step.qty <= taker.qty) {
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


    // Private functions ====================================================

    fun swap_coin(
        step: &mut OrderEntity,
        ) {

    }
}
