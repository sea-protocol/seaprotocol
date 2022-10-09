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
    use std::signer::address_of;
    use std::vector;
    // use std::debug;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::block;
    // use aptos_std::table::{Self, Table};
    // use aptos_std::type_info::{Self, TypeInfo};
    // use aptos_framework::account::{Self, SignerCapability};
    use sea::rbtree::{Self, RBTree};
    use sea::price;
    use sea::utils;
    use sea::fee;
    use sea::math;
    use sea::escrow;
    // use sea::spot_account;

    // Structs ====================================================

    struct PlaceOrderOpts has copy, drop {
        addr: address,
        side: u8,
        // from_escrow: bool,
        // to_escrow: bool,
        post_only: bool,
        ioc: bool,
        fok: bool,
        is_market: bool,
    }

    /// OrderEntity order entity. price, pair_id is on OrderBook
    struct OrderEntity<phantom BaseType, phantom QuoteType> has store {
        // base coin amount
        // we use qty to indicate base amount, vol to indicate quote amount
        qty: u64,
        // the grid id or 0 if is not grid
        grid_id: u64,
        // user address
        // user: address,
        // escrow account id
        account_id: u64,
        base_frozen: Coin<BaseType>,
        quote_frozen: Coin<QuoteType>,
    }

    struct Pair<phantom BaseType, phantom QuoteType, phantom FeeRatio> has key {
        n_order: u64,
        n_grid: u64,
        fee_ratio: u64,
        base_id: u64,
        quote_id: u64,
        pair_id: u64,
        lot_size: u64,
        price_ratio: u64,       // price_coefficient*pow(10, base_precision-quote_precision)
        price_coefficient: u64, // price coefficient, from 10^1 to 10^12
        last_price: u64,        // last trade price
        last_timestamp: u64,    // last trade timestamp
        // base: Coin<BaseType>,
        // quote: Coin<QuoteType>,
        asks: RBTree<OrderEntity<BaseType, QuoteType>>,
        bids: RBTree<OrderEntity<BaseType, QuoteType>>,
        base_vault: Coin<BaseType>,
        quote_vault: Coin<QuoteType>,
    }

    struct QuoteConfig<phantom QuoteType> has key {
        quote_id: u64,
        tick_size: u64,
        min_notional: u64,
        // quote: Coin<QuoteType>,
    }

    // pairs count
    struct NPair has key {
        n_pair: u64,
        n_grid: u64,
    }

    // price step
    struct PriceStep has copy, drop {
        price: u64,
        qty: u64,
        orders: u64,
    }

    // order key, order qty
    // order_key = price << 64 | order_id
    struct OrderKeyQty has copy, drop {
        key: u128,
        qty: u64,
    }

    // struct SpotMarket<phantom BaseType, phantom QuoteType, phantom FeeRatio> has key {
    //     fee: u64,
    //     n_pair: u64,
    //     n_quote: u64,
    //     quotes: Table<u64, QuoteConfig<QuoteType>>,
    //     pairs: Table<u64, Pair<BaseType, QuoteType, FeeRatio>>
    // }
    //
    // struct SpotCoins has key {
    //     n_coin: u64,
    //     n_quote: u64,
    //     coin_map: Table<TypeInfo, u64>,
    //     quote_map: Table<TypeInfo, u64>,
    // }

    /// Stores resource account signer capability under Liquidswap account.
    // struct SpotAccountCapability has key { signer_cap: SignerCapability }

    // Constants ====================================================
    const BUY: u8 = 1;
    const SELL: u8 = 2;
    const MAX_PAIR_ID: u64 = 0xffffff;
    const ORDER_ID_MASK: u64 = 0xffffffffff;
    const MAX_U64: u128 = 0xffffffffffffffff;

    const E_PAIR_NOT_EXIST:      u64 = 1;
    const E_NO_AUTH:             u64 = 2;
    const E_QUOTE_CONFIG_EXISTS: u64 = 3;
    const E_NO_SPOT_MARKET:      u64 = 4;
    const E_VOL_EXCEED_MAX_U64:  u64 = 5;
    const E_VOL_EXCEED_MAX_U128: u64 = 6;
    const E_PAIR_EXISTS:         u64 = 7;
    const E_PAIR_PRICE_INVALID:  u64 = 8;
    const E_NOT_QUOTE_COIN:      u64 = 9;
    const E_EXCEED_PAIR_COUNT:   u64 = 10;
    const E_BASE_NOT_ENOUGH:     u64 = 11;
    const E_QUOTE_NOT_ENOUGH:    u64 = 12;
    const E_PRICE_TOO_LOW:       u64 = 13;
    const E_PRICE_TOO_HIGH:      u64 = 14;
    const E_INITIALIZED:         u64 = 15;
    const E_INVALID_GRID_PRICE:  u64 = 16;
    const E_GRID_PRICE_BUY:      u64 = 17;
    const E_GRID_ORDER_COUNT:    u64 = 18;

    // Public functions ====================================================

    public entry fun initialize(sea_admin: &signer) {
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);
        assert!(!exists<NPair>(address_of(sea_admin)), E_INITIALIZED);
        // let signer_cap = spot_account::retrieve_signer_cap(sea_admin);
        // move_to(sea_admin, SpotAccountCapability { signer_cap });
        move_to(sea_admin, NPair {
            n_pair: 0,
            n_grid: 0,
        });
    }

    /// init spot market
    // public fun init_spot_market<BaseType, QuoteType, FeeRatio>(account: &signer, fee: u64) {
    //     assert!(address_of(account) == @sea, E_NO_AUTH);
    //     assert!(!exists<SpotMarket<BaseType, QuoteType, FeeRatio>>(@sea), E_SPOT_MARKET_EXISTS);
    //     let spot_market = SpotMarket{
    //         fee: fee,
    //         n_pair: 0,
    //         n_quote: 0,
    //         quotes: table::new<u64, QuoteConfig<QuoteType>>(),
    //         pairs: table::new<u64, Pair<BaseType, QuoteType, FeeRatio>>(),
    //     };
    //     move_to<SpotMarket<BaseType, QuoteType, FeeRatio>>(account, spot_market);
    // }

    /// register_quote only the admin can register quote coin
    public fun register_quote<QuoteType>(
        account: &signer,
        tick_size: u64,
        min_notional: u64,
    ) {
        assert!(address_of(account) == @sea, E_NO_AUTH);
        assert!(!exists<QuoteConfig<QuoteType>>(@sea), E_QUOTE_CONFIG_EXISTS);
        let quote_id = escrow::get_or_register_coin_id<QuoteType>(true);

        move_to(account, QuoteConfig<QuoteType>{
            quote_id: quote_id,
            tick_size: tick_size,
            min_notional: min_notional,     
            // quote: quote,
        })
        // todo event
    }

    // register pair, quote should be one of the egliable quote
    public fun register_pair<BaseType, QuoteType, FeeRatio>(
        _owner: &signer,
        price_coefficient: u64
    ) acquires NPair {
        utils::assert_is_coin<BaseType>();
        utils::assert_is_coin<QuoteType>();
        assert!(escrow::is_quote_coin<QuoteType>(), E_NOT_QUOTE_COIN);
        assert!(!exists<Pair<BaseType, QuoteType, FeeRatio>>(@sea_spot), E_PAIR_EXISTS);

        let base_id = escrow::get_or_register_coin_id<BaseType>(false);
        let quote_id = escrow::get_or_register_coin_id<QuoteType>(true);

        let pair_account = escrow::get_spot_account();
        let fee_ratio = fee::get_fee_ratio<FeeRatio>();
        let base_scale = math::pow_10(coin::decimals<BaseType>());
        let quote_scale = math::pow_10(coin::decimals<QuoteType>());
        let npair = borrow_global_mut<NPair>(@sea);
        let pair_id = npair.n_pair + 1;
        assert!(pair_id <= MAX_PAIR_ID, E_EXCEED_PAIR_COUNT);
        npair.n_pair = pair_id;
        // validate the pow_10(base_decimals-quote_decimals) < price_coefficient
        let (ratio, ok) = price::calc_price_ratio(
            base_scale,
            quote_scale,
            price_coefficient);
        assert!(ok, E_PAIR_PRICE_INVALID);
        let pair: Pair<BaseType, QuoteType, FeeRatio> = Pair{
            n_order: 0,
            n_grid: 0,
            fee_ratio: fee_ratio,
            base_id: base_id,
            quote_id: quote_id,
            pair_id: pair_id,
            lot_size: 0,
            price_ratio: ratio,       // price_coefficient*pow(10, base_precision-quote_precision)
            price_coefficient: price_coefficient, // price coefficient, from 10^1 to 10^12
            last_price: 0,        // last trade price
            last_timestamp: 0,    // last trade timestamp
            asks: rbtree::empty<OrderEntity<BaseType, QuoteType>>(true),  // less price is in left
            bids: rbtree::empty<OrderEntity<BaseType, QuoteType>>(false),
            base_vault: coin::zero(),
            quote_vault: coin::zero(),
        };
        move_to(&pair_account, pair);
        // todo events
    }

    // place post only order
    public entry fun place_postonly_order<BaseType, QuoteType, FeeRatio>(
        account: &signer,
        side: u8,
        price: u64,
        qty: u64,
    ) acquires Pair {
        let account_addr = address_of(account);
        let pair = borrow_global_mut<Pair<BaseType, QuoteType, FeeRatio>>(@sea_spot);

        if (side == SELL)  {
            let bids = &mut pair.bids;
            if (!rbtree::is_empty(bids)) {
                let bid0 = get_best_price(bids);
                assert!(price >= bid0, E_PRICE_TOO_LOW);
            }
        } else {
            let asks = &mut pair.asks;
            if (!rbtree::is_empty(asks)) {
                let ask0 = get_best_price(asks);
                // debug::print(&ask0);
                assert!(price <= ask0, E_PRICE_TOO_HIGH);
            }
        };
        let order = OrderEntity{
            qty: qty,
            grid_id: 0,
            account_id: escrow::get_or_register_account_id(account_addr),
            base_frozen: coin::zero(),
            quote_frozen: coin::zero(),
        };
        check_init_taker_escrow<BaseType, QuoteType>(account, side);
        place_order(account, side, price, pair, order)
    }

    public entry fun place_limit_order<BaseType, QuoteType, FeeRatio>(
        account: &signer,
        side: u8,
        price: u64,
        qty: u64,
        ioc: bool,
        fok: bool,
        // from_escrow: bool,
        // to_escrow: bool,
    ) acquires Pair {
        if (fok) {
            // TODO check this order can be filled
        };
        let taker_addr = address_of(account);
        let opts = &PlaceOrderOpts {
            addr: taker_addr,
            side: side,
            // from_escrow: false,
            // to_escrow: to_escrow,
            post_only: false,
            ioc: ioc,
            fok: fok,
            is_market: false,
        };
        let order = OrderEntity{
            qty: qty,
            grid_id: 0,
            account_id: 0,
            base_frozen: coin::zero(),
            quote_frozen: coin::zero(),
        };
        // if (to_escrow) {
        //     check_init_taker_escrow<BaseType, QuoteType>(account, side);
        // };
        // we don't check whether the account has enough asset just abort
        match<BaseType, QuoteType, FeeRatio>(account, price, opts, order);
    }

    public entry fun place_market_order<BaseType, QuoteType, FeeRatio>(
        account: &signer,
        side: u8,
        qty: u64,
        // from_escrow: bool,
        // to_escrow: bool,
    ) acquires Pair {
        let taker_addr = address_of(account);
        let opts = &PlaceOrderOpts {
            addr: taker_addr,
            side: side,
            // from_escrow: from_escrow,
            // to_escrow: to_escrow,
            post_only: false,
            ioc: false,
            fok: false,
            is_market: true,
        };
        let order = OrderEntity{
            qty: qty,
            grid_id: 0,
            account_id: 0,
            base_frozen: coin::zero(),
            quote_frozen: coin::zero(),
        };
        // if (to_escrow) {
        //     check_init_taker_escrow<BaseType, QuoteType>(account, side);
        // };
        // we don't check whether the account has enough asset just abort
        match<BaseType, QuoteType, FeeRatio>(account, 0, opts, order);
    }

    public entry fun place_grid_order<BaseType, QuoteType, FeeRatio>(
        account: &signer,
        buy_price0: u64,
        sell_price0: u64,
        buy_orders: u64,
        sell_orders: u64,
        per_qty: u64,
        delta_price: u64,
        // from_escrow: bool,
    ) acquires Pair {
        assert!(buy_price0 < sell_price0, E_INVALID_GRID_PRICE);
        assert!(buy_orders + sell_orders >= 10, E_INVALID_GRID_PRICE);
        // 
        let account_addr = address_of(account);
        let pair = borrow_global_mut<Pair<BaseType, QuoteType, FeeRatio>>(@sea_spot);
        let account_id = escrow::get_or_register_account_id(account_addr);
        let grid_id = pair.n_grid + 1;
        pair.n_grid = grid_id;
        grid_id = (pair.pair_id << 40) | grid_id;

        if (sell_orders > 0)  {
            let bids = &mut pair.bids;
            if (!rbtree::is_empty(bids)) {
                let bid0 = get_best_price(bids);
                assert!(sell_price0 >= bid0, E_PRICE_TOO_LOW);
            };
            check_init_taker_escrow<BaseType, QuoteType>(account, SELL);
            let i = 0;
            let price = sell_price0;
            while (i < sell_orders) {
                let order = OrderEntity{
                    qty: per_qty,
                    grid_id: grid_id,
                    account_id: account_id,
                    base_frozen: coin::zero(),
                    quote_frozen: coin::zero(),
                };
                place_order(account, SELL, price, pair, order);
                price = price + delta_price;
            }
        };
        if (buy_orders > 0) {
            let asks = &mut pair.asks;
            if (!rbtree::is_empty(asks)) {
                let ask0 = get_best_price(asks);
                // debug::print(&ask0);
                assert!(buy_price0 <= ask0, E_PRICE_TOO_HIGH);
            };
            check_init_taker_escrow<BaseType, QuoteType>(account, BUY);
            let i = 0;
            let price = buy_price0;
            while (i < buy_orders) {
                let order = OrderEntity{
                    qty: per_qty,
                    grid_id: grid_id,
                    account_id: account_id,
                    base_frozen: coin::zero(),
                    quote_frozen: coin::zero(),
                };
                place_order(account, BUY, price, pair, order);
                assert!(price > delta_price, E_GRID_PRICE_BUY);
                price = price - delta_price;
            }
        };
    }

    // get pair prices, both asks and bids
    public entry fun get_pair_price_steps<BaseType, QuoteType, FeeRatio>():
        (u64, vector<PriceStep>, vector<PriceStep>) acquires Pair {
        let pair = borrow_global<Pair<BaseType, QuoteType, FeeRatio>>(@sea_spot);
        let asks = get_price_steps(&pair.asks);
        let bids = get_price_steps(&pair.bids);

        (block::get_current_block_height(), asks, bids)
    }

    // get pair keys, both asks and bids
    // key = (price << 64 | order_id)
    public entry fun get_pair_keys<BaseType, QuoteType, FeeRatio>():
        (u64, vector<OrderKeyQty>, vector<OrderKeyQty>) acquires Pair {
        let pair = borrow_global<Pair<BaseType, QuoteType, FeeRatio>>(@sea_spot);
        let asks = get_order_key_qty_list(&pair.asks);
        let bids = get_order_key_qty_list(&pair.bids);

        (block::get_current_block_height(), asks, bids)
    }

    // when cancel an order, we need order_key, not just order_id
    // order_key = order_price << 64 | order_id
    public entry fun cancel_order<BaseType, QuoteType, FeeRatio>(
        account: &signer,
        side: u8,
        order_key: u128,
        to_escrow: bool
        ) acquires Pair {
        let pair = borrow_global_mut<Pair<BaseType, QuoteType, FeeRatio>>(@sea_spot);
        cancel_order_by_key<BaseType, QuoteType, FeeRatio>(account, side, order_key, to_escrow, pair);
    }

    // Private functions ====================================================

    fun incr_pair_grid_id<BaseType, QuoteType, FeeRatio>(
        pair: &mut Pair<BaseType, QuoteType, FeeRatio>
    ): u64 {
        let grid_id = pair.n_grid + 1;
        pair.n_grid = grid_id;
        (pair.pair_id << 40) | grid_id
    }

    fun return_coin_to_account<CoinType>(
        account: &signer,
        account_addr: address,
        to_escrow: bool,
        frozen: Coin<CoinType>,
    ) {
        if (to_escrow) {
            escrow::check_init_account_escrow<CoinType>(account);
            escrow::incr_escrow_coin(account_addr, frozen);
        } else {
            if (!coin::is_account_registered<CoinType>(account_addr)) {
                coin::register<CoinType>(account);
            };
            coin::deposit(account_addr, frozen);
        };
    }

    fun cancel_order_by_key<BaseType, QuoteType, FeeRatio>(
        account: &signer,
        side: u8,
        order_key: u128,
        to_escrow: bool,
        pair: &mut Pair<BaseType, QuoteType, FeeRatio>,
    ) {
        let account_addr = address_of(account);
        if (side == BUY) {
            // frozen is quote
            let orderbook = &mut pair.bids;
            let pos = rbtree::rb_find(orderbook, order_key);
            if (pos == 0) {
                return
            };
            let (_, order) = rbtree::rb_remove_by_pos(orderbook, pos);
            // quote
            // let vol = calc_quote_vol_for_buy(order.qty, price, pair.ratio);
            // let unfrozen = escrow::dec_escrow_coin<QuoteType>(account_addr, vol, true);
            let OrderEntity {
                    account_id: _,
                    grid_id: grid_id,
                    qty: _,
                    base_frozen: base_frozen,
                    quote_frozen: quote_frozen,
                } = order;
            return_coin_to_account<QuoteType>(account, account_addr, to_escrow, quote_frozen);
            if (grid_id > 0 && coin::value(&base_frozen) > 0) {
                return_coin_to_account<BaseType>(account, account_addr, to_escrow, base_frozen);
            } else {
                coin::destroy_zero(base_frozen);
            }
        } else {
            let orderbook = &mut pair.asks;
            let pos = rbtree::rb_find(orderbook, order_key);
            if (pos == 0) {
                return
            };
            let (_, order) = rbtree::rb_remove_by_pos(orderbook, pos);
            let OrderEntity {
                    account_id: _,
                    grid_id: grid_id,
                    qty: _,
                    base_frozen: base_frozen,
                    quote_frozen: quote_frozen,
                } = order;
            return_coin_to_account<BaseType>(account, account_addr, to_escrow, base_frozen);
            if (grid_id > 0 && coin::value(&quote_frozen) > 0) {
                return_coin_to_account<QuoteType>(account, account_addr, to_escrow, quote_frozen);
            } else {
                coin::destroy_zero(quote_frozen);
            }
        };
    }

    fun get_price_steps<BaseType, QuoteType>(
        tree: &RBTree<OrderEntity<BaseType, QuoteType>>
    ): vector<PriceStep> {
        let steps = vector::empty<PriceStep>();

        if (!rbtree::is_empty(tree)) {
            let (pos, key, item) = rbtree::get_leftmost_pos_key_val(tree);
            let price = price_from_key(key);
            let qty: u64 = item.qty;
            let orders: u64 = 1;
            while (true) {
                let (next_pos, next_key) = rbtree::get_next_pos_key(tree, pos);
                if (next_key == 0) {
                    vector::push_back(&mut steps, PriceStep{
                        price: price,
                        qty: qty,
                        orders: orders,
                    });
                    break
                };

                let next_price = price_from_key(next_key);
                let next_order = rbtree::borrow_by_pos<OrderEntity<BaseType, QuoteType>>(tree, next_pos);
                let next_qty = next_order.qty;
                if (price == next_price) {
                    qty = qty + next_qty;
                    orders = orders + 1;
                } else {
                    vector::push_back(&mut steps, PriceStep{
                        price: price,
                        qty: qty,
                        orders: orders,
                    });
                    qty = next_qty; //
                    orders = 1;
                };
                pos = next_pos;
            }
        };
        steps
    }

    // when we cancel an order, we need the key, not only the order_id
    fun get_order_key_qty_list<BaseType, QuoteType>(
        tree: &RBTree<OrderEntity<BaseType, QuoteType>>
    ): vector<OrderKeyQty> {
        let orders = vector::empty<OrderKeyQty>();

        if (!rbtree::is_empty(tree)) {
            let (pos, key, item) = rbtree::get_leftmost_pos_key_val(tree);
            let qty: u64 = item.qty;
            while (true) {
                vector::push_back(&mut orders, OrderKeyQty{
                    key: key,
                    qty: qty,
                });
                (pos, key) = rbtree::get_next_pos_key(tree, pos);
                if (key == 0) {
                    break
                };
            }
        };
        orders
    }

    // the left most key contains price
    fun get_best_price<V>(
        tree: &RBTree<V>
    ): u64 {
        let leftmmost = rbtree::get_leftmost_key(tree);
        price_from_key(leftmmost)
    }

    fun price_from_key(key: u128): u64 {
        ((key >> 64) as u64)
    }

    fun has_enough_asset<CoinType>(
        addr: address,
        amount: u64,
        from_escrow: bool
    ): bool {
        let avail = if (!from_escrow) {
            coin::balance<CoinType>(addr)
        } else {
            escrow::escrow_available<CoinType>(addr)
        };
        avail >= amount
    }

    // if taker's escrow accountAsset not exist, create it
    fun check_init_taker_escrow<BaseType, QuoteType>(
        account: &signer,
        side: u8
    ) {
        if (side == BUY) {
            // taker got Base
            escrow::check_init_account_escrow<BaseType>(account);
        } else {
            escrow::check_init_account_escrow<QuoteType>(account);
        }
    }

    /// match buy order, taker is buyer, maker is seller
    /// 
    fun match<BaseType, QuoteType, FeeRatio>(
        taker: &signer,
        price: u64,
        opts: &PlaceOrderOpts,
        order: OrderEntity<BaseType, QuoteType>
    ) acquires Pair {
        let taker_addr = address_of(taker);
        let pair = borrow_global_mut<Pair<BaseType, QuoteType, FeeRatio>>(@sea_spot);

        // let taker_account_id = if (to_escrow) {
        //     escrow::get_or_register_account_id(taker_addr)
        // } else 0;
        let completed = match_internal(
            taker,
            price,
            pair,
            &mut order,
            opts,
        );

        if ((!completed) && (!opts.is_market)) {
            // TODO make sure order qty >= lot_size
            // place order to orderbook
            let taker_account_id = escrow::get_or_register_account_id(taker_addr);
            order.account_id = taker_account_id;
            place_order(taker, opts.side, price, pair, order);
        } else {
            destroy_order(order);
        };
    }

    fun place_order<BaseType, QuoteType, FeeRatio>(
        account: &signer,
        // addr: address,
        side: u8,
        price: u64,
        pair: &mut Pair<BaseType, QuoteType, FeeRatio>,
        order: OrderEntity<BaseType, QuoteType>
    ) {
        // frozen
        if (side == SELL) {
            let qty = order.qty;
            // if (from_escrow) {
            //     coin::merge(&mut order.base_frozen, escrow::dec_escrow_coin<BaseType>(addr, qty));
            // } else {
                coin::merge(&mut order.base_frozen, coin::withdraw(account, qty));
                // escrow::deposit<BaseType>(account, order.qty, true);
            // };
            // init escrow QuoteType if not exist
            escrow::check_init_account_escrow<QuoteType>(account);
        } else {
            let vol = calc_quote_vol_for_buy(order.qty, price, pair.price_ratio);
            // debug::print(&pair.price_ratio);
            // debug::print(&vol);
            // if (from_escrow) {
            //     coin::merge(&mut order.quote_frozen, escrow::dec_escrow_coin<QuoteType>(addr, vol));
            // } else {
                coin::merge(&mut order.quote_frozen, coin::withdraw(account, vol));
                // escrow::deposit<QuoteType>(account, vol, true);
            // };
            // init escrow BaseType if not exist
            escrow::check_init_account_escrow<BaseType>(account);
        };

        let order_id = generate_order_id(pair);
        let orderbook = if (side == BUY) &mut pair.bids else &mut pair.asks;
        let key: u128 = generate_key(price, order_id);
        rbtree::rb_insert<OrderEntity<BaseType, QuoteType>>(orderbook, key, order);
    }

    fun generate_key(price: u64, order_id: u64): u128 {
        (((price as u128) << 64) | (order_id as u128))
    }

    fun generate_order_id<BaseType, QuoteType, FeeRatio>(
        pair: &mut Pair<BaseType, QuoteType, FeeRatio>,
        ): u64 {
        // first 24 bit is pair_id
        // left 40 bit is order_id
        let id = pair.pair_id << 40 | (pair.n_order & ORDER_ID_MASK);
        pair.n_order = pair.n_order + 1;
        id
    }

    fun match_internal<BaseType, QuoteType, FeeRatio>(
        taker: &signer,
        price: u64,
        pair: &mut Pair<BaseType, QuoteType, FeeRatio>,
        taker_order: &mut OrderEntity<BaseType, QuoteType>,
        taker_opts: &PlaceOrderOpts,
    ): bool {
        // does the taker order is total filled
        // let completed = false;
        let fee_ratio = pair.fee_ratio;
        let price_ratio = pair.price_ratio;
        let taker_side = taker_opts.side;
        let orderbook = if (taker_side == BUY) &mut pair.asks else &mut pair.bids;

        while (!rbtree::is_empty(orderbook)) {
            let (pos, key, order) = rbtree::borrow_leftmost_keyval_mut(orderbook);
            let (maker_price, _) = price::get_price_order_id(key);
            if ((!taker_opts.is_market) && 
                    ((taker_side == BUY && price < maker_price) ||
                     (taker_side == SELL && price >  maker_price))
             ) {
                break
            };

            let match_qty = taker_order.qty;
            let remove_order = false;
            if (order.qty <= taker_order.qty) {
                match_qty = order.qty;
                // remove this order from orderbook
                remove_order = true;
                // debug::print(&10000000000001);
                // if (order.qty == taker_order.qty) completed = true;
            };

            taker_order.qty = taker_order.qty - match_qty;
            order.qty = order.qty - match_qty;
            // debug::print(&order.qty);
            let (quote_vol, fee_amt) = calc_quote_vol(taker_side, match_qty, maker_price, price_ratio, fee_ratio);
            let (fee_maker, fee_plat) = fee::get_maker_fee_shares(fee_amt, order.grid_id > 0);

            swap_internal<BaseType, QuoteType, FeeRatio>(
                &mut pair.base_vault,
                &mut pair.quote_vault,
                taker,
                taker_opts,
                order,
                match_qty,
                quote_vol,
                fee_plat,
                fee_maker);
            if (remove_order) {
                // debug::print(&10000000000002);
                // debug::print(&pos);
                // TODO if is grid order, flip it
                if (order.grid_id > 0) {
                    flip_grid_order();
                };
                let (_, pop_order) = rbtree::rb_remove_by_pos(orderbook, pos);
                destroy_order<BaseType, QuoteType>(pop_order);
            };
            if (taker_order.qty == 0) {
                break
            }
        };

        taker_order.qty == 0
    }

    fun flip_grid_order() {}

    fun destroy_order<BaseType, QuoteType>(
        order: OrderEntity<BaseType, QuoteType>
    ) {
        let OrderEntity {
            qty: _,
            grid_id: _,
            account_id: account_id,
            base_frozen: base_frozen,
            quote_frozen: quote_frozen,
        } = order;
        if (coin::value(&base_frozen) > 0) {
            let addr = escrow::get_account_addr_by_id(account_id);
            escrow::incr_escrow_coin<BaseType>(addr, base_frozen);
        } else {
            coin::destroy_zero(base_frozen);
        };
        if (coin::value(&quote_frozen) > 0) {
            let addr = escrow::get_account_addr_by_id(account_id);
            escrow::incr_escrow_coin<QuoteType>(addr, quote_frozen);
        } else {
            coin::destroy_zero(quote_frozen);
        };
    }

    fun calc_quote_vol_for_buy(
        qty: u64,
        price: u64,
        price_ratio: u64
    ): u64 {
        let vol_orig: u128 = (qty as u128) * (price as u128);
        let vol: u128;

        vol = vol_orig / (price_ratio as u128);
        
        assert!(vol < MAX_U64, E_VOL_EXCEED_MAX_U64);
        (vol as u64)
    }

    // calculate quote volume: quote_vol = price * base_amt
    fun calc_quote_vol(
        taker_side: u8,
        qty: u64,
        price: u64,
        price_ratio: u64,
        fee_ratio: u64): (u64, u64) {
        let vol_orig: u128 = (qty as u128) * (price as u128);
        let vol: u128;

        vol = vol_orig / (price_ratio as u128);
        
        assert!(vol < MAX_U64, E_VOL_EXCEED_MAX_U64);
        let fee: u128 = (
            if (taker_side == BUY) {
                // buy, fee is base coin
                (qty as u128) * (fee_ratio as u128) / 1000000
            } else {
                vol * (fee_ratio as u128) / 1000000
            });
        assert!(fee < MAX_U64, E_VOL_EXCEED_MAX_U64);
        ((vol as u64), (fee as u64))
    }

    // direct transfer coin to taker account
    // increase maker escrow
    fun swap_internal<BaseType, QuoteType, FeeRatio>(
        pair_base_vault: &mut Coin<BaseType>,
        pair_quote_vault: &mut Coin<QuoteType>,
        taker: &signer,
        taker_opts: &PlaceOrderOpts,
        maker_order: &mut OrderEntity<BaseType, QuoteType>,
        base_qty: u64,
        quote_vol: u64,
        fee_plat_amt: u64,
        fee_maker_amt: u64,
    ) {
        let maker_addr = escrow::get_account_addr_by_id(maker_order.account_id);
        let taker_addr = taker_opts.addr;

        if (taker_opts.side == BUY) {
            // taker got base coin
            // let to_taker = escrow::dec_escrow_coin<BaseType>(maker_addr, base_qty);
            let to_taker = coin::extract<BaseType>(&mut maker_order.base_frozen, base_qty);
            let maker_fee_prop = coin::extract<BaseType>(&mut to_taker, fee_maker_amt);
            escrow::incr_escrow_coin<BaseType>(maker_addr, maker_fee_prop);
            if (fee_plat_amt > 0) {
                // platform vault
                let to_plat = coin::extract(&mut to_taker, fee_plat_amt);
                coin::merge(pair_base_vault, to_plat);
            };
            // if (taker_opts.to_escrow) {
            //     escrow::incr_escrow_coin<BaseType>(taker_addr, to_taker);
            // } else {
                // send to taker directly
                coin::deposit(taker_addr, to_taker);
            // };
            // maker got quote coin
            let quote = coin::withdraw<QuoteType>(taker, quote_vol);
            // if (taker_opts.from_escrow) {
            //         escrow::dec_escrow_coin<QuoteType>(taker_addr, quote_vol)
            //     } else {
            //         coin::withdraw<QuoteType>(taker, quote_vol)
            //     };
            // if the maker is grid
            if (maker_order.grid_id > 0) {
                coin::merge(&mut maker_order.quote_frozen, quote);
            } else {
                escrow::incr_escrow_coin<QuoteType>(maker_addr, quote);
            }
        } else {
            // taker got quote coin
            // let to_taker = escrow::dec_escrow_coin<QuoteType>(maker_addr, quote_vol);
            let to_taker = coin::extract<QuoteType>(&mut maker_order.quote_frozen, quote_vol);
            let maker_fee_prop = coin::extract<QuoteType>(&mut to_taker, fee_maker_amt);
            escrow::incr_escrow_coin<QuoteType>(maker_addr, maker_fee_prop);
            if (fee_plat_amt > 0) {
                // platform vault
                let to_plat = coin::extract(&mut to_taker, fee_plat_amt);
                coin::merge(pair_quote_vault, to_plat);
            };
            // if (taker_opts.to_escrow) {
            //     escrow::incr_escrow_coin<QuoteType>(taker_addr, to_taker);
            // } else {
                // send to taker directly
                coin::deposit(taker_addr, to_taker);
            // };
            // maker got base coin
            let base = coin::withdraw<BaseType>(taker, base_qty);
            // if (taker_opts.from_escrow) {
            //         escrow::dec_escrow_coin<BaseType>(taker_addr, base_qty)
            //     } else {
            //         coin::withdraw<BaseType>(taker, base_qty)
            //     };
            // if the maker is grid
            if (maker_order.grid_id > 0) {
                coin::merge(&mut maker_order.base_frozen, base);
            } else {
                escrow::incr_escrow_coin<BaseType>(maker_addr, base);
            }
        }
    }

    // Test-only functions ====================================================
    #[test_only]
    use sea::spot_account;
    #[test_only]
    use std::string;
    #[test_only]
    use aptos_framework::aptos_account;
    #[test_only]
    use std::debug;

    #[test_only]
    const T_USD_AMT: u64 = 10000000*100000000;
    #[test_only]
    const T_BTC_AMT: u64 = 100*100000000;
    #[test_only]
    const T_SEA_AMT: u64 = 100000000*1000000;
    #[test_only]
    const T_BAR_AMT: u64 = 10000000000*100000;
    #[test_only]
    const T_ETH_AMT: u64 = 10000*100000000;

    #[test_only]
    struct T_USD {}

    #[test_only]
    struct T_BTC {}

    #[test_only]
    struct T_SEA {}
    
    #[test_only]
    struct T_ETH {}

    #[test_only]
    struct T_BAR {}
    
    #[test_only]
    struct TPrice has copy, drop {
        side: u8,
        qty: u64,
        price: u64,
        price_ratio: u64
    }

    #[test_only]
    fun test_prepare_account_env(
        sea_admin: &signer
    ) {
        spot_account::initialize_spot_account(sea_admin);
        initialize(sea_admin);
        escrow::initialize(sea_admin);
        fee::initialize(sea_admin);
    }

    #[test_only]
    fun create_test_coins<T>(
        sea_admin: &signer,
        name: vector<u8>,
        decimals: u8,
        user_a: &signer,
        user_b: &signer,
        user_c: &signer,
        amt_a: u64,
        amt_b: u64,
        amt_c: u64,
    ) {
        let (bc, fc, mc) = coin::initialize<T>(sea_admin,
            string::utf8(name),
            string::utf8(name),
            decimals,
            false);
        coin::destroy_burn_cap(bc);
        coin::destroy_freeze_cap(fc);
        coin::register<T>(sea_admin);
        coin::register<T>(user_a);
        coin::register<T>(user_b);
        coin::register<T>(user_c);
        coin::deposit(address_of(user_a), coin::mint<T>(amt_a, &mc));
        coin::deposit(address_of(user_b), coin::mint<T>(amt_b, &mc));
        coin::deposit(address_of(user_c), coin::mint<T>(amt_c, &mc));
        coin::destroy_mint_cap(mc);
    }

    #[test_only]
    fun test_get_pair_price_steps<BaseType, QuoteType, FeeRatio>():
        (u64, vector<PriceStep>, vector<PriceStep>) acquires Pair {
        let pair = borrow_global<Pair<BaseType, QuoteType, FeeRatio>>(@sea_spot);
        let asks = get_price_steps(&pair.asks);
        let bids = get_price_steps(&pair.bids);

        (0, asks, bids)
    }
    #[test_only]
    fun test_init_coins_and_accounts(
        sea_admin: &signer,
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        aptos_account::create_account(address_of(sea_admin));
        aptos_account::create_account(address_of(user1));
        aptos_account::create_account(address_of(user2));
        aptos_account::create_account(address_of(user3));
        // T_USD T_BTC T_SEA T_BAR T_ETH
        create_test_coins<T_USD>(sea_admin, b"USD", 8, user1, user2, user3, T_USD_AMT, T_USD_AMT, T_USD_AMT);
        create_test_coins<T_BTC>(sea_admin, b"BTC", 8, user1, user2, user3, T_BTC_AMT, T_BTC_AMT, T_BTC_AMT);
        create_test_coins<T_SEA>(sea_admin, b"SEA", 6, user1, user2, user3, T_SEA_AMT, T_SEA_AMT, T_SEA_AMT);
        create_test_coins<T_BAR>(sea_admin, b"BAR", 5, user1, user2, user3, T_BAR_AMT, T_BAR_AMT, T_BAR_AMT);
        create_test_coins<T_ETH>(sea_admin, b"ETH", 8, user1, user2, user3, T_ETH_AMT, T_ETH_AMT, T_ETH_AMT);

        assert!(coin::balance<T_USD>(address_of(user1)) == T_USD_AMT, 1);
        assert!(coin::balance<T_USD>(address_of(user2)) == T_USD_AMT, 2);
        assert!(coin::balance<T_USD>(address_of(user3)) == T_USD_AMT, 3);

        assert!(coin::balance<T_BTC>(address_of(user1)) == T_BTC_AMT, 11);
        assert!(coin::balance<T_BTC>(address_of(user2)) == T_BTC_AMT, 12);
        assert!(coin::balance<T_BTC>(address_of(user3)) == T_BTC_AMT, 13);

        assert!(coin::balance<T_SEA>(address_of(user1)) == T_SEA_AMT, 21);
        assert!(coin::balance<T_SEA>(address_of(user2)) == T_SEA_AMT, 22);
        assert!(coin::balance<T_SEA>(address_of(user3)) == T_SEA_AMT, 23);

        assert!(coin::balance<T_BAR>(address_of(user1)) == T_BAR_AMT, 31);
        assert!(coin::balance<T_BAR>(address_of(user2)) == T_BAR_AMT, 32);
        assert!(coin::balance<T_BAR>(address_of(user3)) == T_BAR_AMT, 33);

        assert!(coin::balance<T_ETH>(address_of(user1)) == T_ETH_AMT, 41);
        assert!(coin::balance<T_ETH>(address_of(user2)) == T_ETH_AMT, 42);
        assert!(coin::balance<T_ETH>(address_of(user3)) == T_ETH_AMT, 43);
    }

    // check account asset as expect
    #[test_only]
    fun test_check_account_asset<CoinType>(
        addr: address,
        balance: u64,
        escrow_avail: u64,
        escrow_frozen: u64,
    ) {
        assert!(coin::balance<CoinType>(addr) == balance, 100);
        let avail = escrow::escrow_available<CoinType>(addr);
        // debug::print(&avail);
        assert!(avail == escrow_avail, 101);
        // let freeze = escrow::escrow_frozen<CoinType>(addr);
        // debug::print(&freeze);
        // assert!(freeze == escrow_frozen, 102);
        // let sep = string::utf8(b"------------");
        // debug::print(&sep);
    }

    // Tests ==================================================================
    #[test]
    fun test_calc_quote_volume() {
        let price = 152210000000; // 1500.1
        let price_ratio = 100000000;
        let qty = 150000; // 0.15, 6 decimals
        let fee_ratio = 1000; // 0.1%
        let (vol, fee) = calc_quote_vol(BUY, qty, price, price_ratio, fee_ratio);

        assert!(vol == 228315000, 100001);
        assert!(fee == 150, 100002);
    }

    #[test(
        sea_admin = @sea,
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_register_pair(
        sea_admin: &signer,
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ): u64 acquires NPair, Pair {
        test_prepare_account_env(sea_admin);
        test_init_coins_and_accounts(sea_admin, user1, user2, user3);
        // 1. register quote
        register_quote<T_USD>(sea_admin, 10, 10);
        // 2. 
        register_pair<T_BTC, T_USD, fee::FeeRatio200>(sea_admin, 10000000);

        let pair = borrow_global_mut<Pair<T_BTC, T_USD, fee::FeeRatio200>>(@sea_spot);
        pair.price_ratio
    }

    #[test(sea_admin = @sea)]
    fun test_register_quote(
        sea_admin: &signer
    ) {
        test_prepare_account_env(sea_admin);
        // 1. register quote
        register_quote<T_USD>(sea_admin, 10, 10);
    }

    #[test(sea_admin = @sea)]
    #[expected_failure(abort_code = 3)] // E_QUOTE_CONFIG_EXISTS
    fun test_register_quote_dup(
        sea_admin: &signer
    ) {
        test_prepare_account_env(sea_admin);
        // 1. register quote
        register_quote<T_USD>(sea_admin, 10, 10);
        // 2. 
        register_quote<T_USD>(sea_admin, 10, 10);
    }

    #[test(
        sea_admin = @sea,
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_place_limit_order_buy(
        sea_admin: &signer,
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair {
        let price_ratio = test_register_pair(sea_admin, user1, user2, user3);

        place_limit_order<T_BTC, T_USD, fee::FeeRatio200>(user1, BUY, 150130000000, 1500000, false, false);
        // check the user's asset OK
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT, 0, 0);
        let vol = calc_quote_vol_for_buy(150130000000, 1500000, price_ratio);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT-vol, 0, vol);

        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD, fee::FeeRatio200>();
        assert!(vector::length(&asks) == 0, 0);
        assert!(vector::length(&bids) == 1, 1);
        let step0 = vector::borrow(&bids, 0);
        assert!(step0.price == 150130000000, 2);
        assert!(step0.qty == 1500000, 2);
        
        place_limit_order<T_BTC, T_USD, fee::FeeRatio200>(user2, SELL, 150130000000, 1000000, false, false);
        // check maker user1 assets
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT, 1000000, 0);
        let vol1 = calc_quote_vol_for_buy(150130000000, 1000000, price_ratio);
        let fee1 = vol1 * 200/1000000;
        let fee1_maker = fee1 * 400/1000;
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT-vol, fee1_maker, vol-vol1);

        // check taker user2 assets
        test_check_account_asset<T_BTC>(address_of(user2), T_BTC_AMT-1000000, 0, 0);
        test_check_account_asset<T_USD>(address_of(user2), T_USD_AMT, vol1-fee1, 0);

        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD, fee::FeeRatio200>();
        assert!(vector::length(&asks) == 0, 0);
        assert!(vector::length(&bids) == 1, 1);
        let step0 = vector::borrow(&bids, 0);
        assert!(step0.price == 150130000000, 2);
        assert!(step0.qty == 500000, 2);

        place_limit_order<T_BTC, T_USD, fee::FeeRatio200>(user3, SELL, 150130000000, 500000, false, false);
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT, 1500000, 0);
        let vol2 = calc_quote_vol_for_buy(150130000000, 500000, price_ratio);
        let fee2 = vol2 * 200/1000000;
        let fee2_maker = fee2 * 400/1000;
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT-vol, fee1_maker+fee2_maker, vol-vol1-vol2);
        // check taker user3 assets
        test_check_account_asset<T_BTC>(address_of(user3), T_BTC_AMT-500000, 0, 0);
        // debug::print(&vol2);
        // debug::print(&fee2_maker);
        test_check_account_asset<T_USD>(address_of(user3), T_USD_AMT+vol2-fee2, 0, 0);

        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD, fee::FeeRatio200>();
        assert!(vector::length(&asks) == 0, 0);
        debug::print(&vector::length(&asks));
        assert!(vector::length(&bids) == 0, 1);
    }

    #[test(
        sea_admin = @sea,
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_place_limit_order_sell(
        sea_admin: &signer,
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair {
        let price_ratio = test_register_pair(sea_admin, user1, user2, user3);

        place_limit_order<T_BTC, T_USD, fee::FeeRatio200>(user1, SELL, 150130000000, 1500000, false, false);
        // check the user's asset OK
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000, 0, 1500000);
        // let vol = calc_quote_vol_for_buy(150130000000, 1500000, price_ratio);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT, 0, 0);
        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD, fee::FeeRatio200>();
        assert!(vector::length(&asks) == 1, 0);
        let ask0 = vector::borrow(&asks, 0);
        assert!(ask0.price == 150130000000, 1);
        assert!(ask0.qty == 1500000, 1);
        assert!(vector::length(&bids) == 0, 1);
        
        place_limit_order<T_BTC, T_USD, fee::FeeRatio200>(user2, BUY, 150130000000, 1000000, false, false);
        // check maker user1 assets
        let fee1 = 1000000 * 200/1000000;
        let fee1_maker = fee1 * 400/1000;
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000, fee1_maker, 500000);
        let vol1 = calc_quote_vol_for_buy(150130000000, 1000000, price_ratio);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT, vol1, 0);

        // check taker user2 assets
        test_check_account_asset<T_BTC>(address_of(user2), T_BTC_AMT, 1000000-fee1, 0);
        test_check_account_asset<T_USD>(address_of(user2), T_USD_AMT-vol1, 0, 0);
        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD, fee::FeeRatio200>();
        assert!(vector::length(&asks) == 1, 0);
        assert!(vector::length(&bids) == 0, 1);

        place_limit_order<T_BTC, T_USD, fee::FeeRatio200>(user3, BUY, 150230000000, 500000, false, false);
        let fee2 = 500000 * 200/1000000;
        let fee2_maker = fee2 * 400/1000;
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000, fee1_maker+fee2_maker, 0);
        let vol2 = calc_quote_vol_for_buy(150130000000, 500000, price_ratio);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT, vol1+vol2, 0);
        // check taker user3 assets
        test_check_account_asset<T_BTC>(address_of(user3), T_BTC_AMT+500000-fee2, 0, 0);
        test_check_account_asset<T_USD>(address_of(user3), T_USD_AMT-vol2, 0, 0);

        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD, fee::FeeRatio200>();
        assert!(vector::length(&asks) == 0, 0);
        assert!(vector::length(&bids) == 0, 1);
    }

    #[test(
        sea_admin = @sea,
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_place_limit_order_sell_2(
        sea_admin: &signer,
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair {
        let price_ratio = test_register_pair(sea_admin, user1, user2, user3);

        place_limit_order<T_BTC, T_USD, fee::FeeRatio200>(user1, SELL, 150130000000, 1500000, false, false);
        // check the user's asset OK
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000, 0, 1500000);
        // let vol = calc_quote_vol_for_buy(150130000000, 1500000, price_ratio);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT, 0, 0);
        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD, fee::FeeRatio200>();
        assert!(vector::length(&asks) == 1, 0);
        let ask0 = vector::borrow(&asks, 0);
        assert!(ask0.price == 150130000000, 1);
        assert!(ask0.qty == 1500000, 1);
        assert!(vector::length(&bids) == 0, 1);
        
        place_limit_order<T_BTC, T_USD, fee::FeeRatio200>(user2, BUY, 150130000000, 1000000, false, false);
        // check maker user1 assets
        let fee1 = 1000000 * 200/1000000;
        let fee1_maker = fee1 * 400/1000;
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000, fee1_maker, 500000);
        let vol1 = calc_quote_vol_for_buy(150130000000, 1000000, price_ratio);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT, vol1, 0);

        // check taker user2 assets
        test_check_account_asset<T_BTC>(address_of(user2), T_BTC_AMT, 1000000-fee1, 0);
        test_check_account_asset<T_USD>(address_of(user2), T_USD_AMT-vol1, 0, 0);
        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD, fee::FeeRatio200>();
        assert!(vector::length(&asks) == 1, 0);
        assert!(vector::length(&bids) == 0, 1);

        place_limit_order<T_BTC, T_USD, fee::FeeRatio200>(user3, BUY, 150230000000, 500010, false, false);
        let fee2 = 500000 * 200/1000000;
        let fee2_maker = fee2 * 400/1000;
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000, fee1_maker+fee2_maker, 0);
        let vol2 = calc_quote_vol_for_buy(150130000000, 500000, price_ratio);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT, vol1+vol2, 0);
        // check taker user3 assets
        test_check_account_asset<T_BTC>(address_of(user3), T_BTC_AMT+500000-fee2, 0, 0);
        debug::print(&222222222222);
        let vol = calc_quote_vol_for_buy(150230000000, 10, price_ratio);
        test_check_account_asset<T_USD>(address_of(user3), T_USD_AMT-vol2-vol, 0, vol);

        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD, fee::FeeRatio200>();
        assert!(vector::length(&asks) == 0, 0);
        assert!(vector::length(&bids) == 1, 1);
        let bid0 = vector::borrow(&bids, 0);
        assert!(bid0.price == 150230000000, 9);
        assert!(bid0.qty == 10, 9);
    }

    #[test(
        sea_admin = @sea,
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_place_postonly_order(
        sea_admin: &signer,
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair {
        test_register_pair(sea_admin, user1, user2, user3);

        place_postonly_order<T_BTC, T_USD, fee::FeeRatio200>(user1, BUY, 150130000000, 1500000);
        place_postonly_order<T_BTC, T_USD, fee::FeeRatio200>(user1, SELL, 150130000000, 1500000);
    }

    #[test(
        sea_admin = @sea,
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    #[expected_failure(abort_code = 13)] // E_PRICE_TOO_LOW
    fun test_e2e_place_postonly_order_failed(
        sea_admin: &signer,
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair {
        test_register_pair(sea_admin, user1, user2, user3);

        place_postonly_order<T_BTC, T_USD, fee::FeeRatio200>(user1, BUY, 150130000000, 1500000);
        place_postonly_order<T_BTC, T_USD, fee::FeeRatio200>(user1, SELL, 150100000000, 1500000);
    }

    #[test(
        sea_admin = @sea,
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    #[expected_failure(abort_code = 14)] // E_PRICE_TOO_HIGH
    fun test_e2e_place_postonly_order_failed2(
        sea_admin: &signer,
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair {
        test_register_pair(sea_admin, user1, user2, user3);

        place_postonly_order<T_BTC, T_USD, fee::FeeRatio200>(user1, SELL, 150130000000, 1500000);
        place_postonly_order<T_BTC, T_USD, fee::FeeRatio200>(user1, BUY, 150200000000, 1500000);
    }
}
