/// # Module-level documentation sections
///
/// * [Background](#Background)
/// * [Implementation](#Implementation)
/// * [Basic public functions](#Basic-public-functions)
/// * [Traversal](#Traversal)
///
/// # Background
///
/// spot market
/// 
module sea::market {
    use std::signer::address_of;
    use std::vector;
    // use std::debug;

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use aptos_std::table::{Self, Table};
    use aptos_framework::account;

    use sealib::rbtree::{Self, RBTree};
    use sealib::math;

    use sea::grid;
    use sea::price;
    use sea::utils;
    use sea::fee;
    use sea::escrow;
    use sea::amm;
    use sea::events;
    use sea::mining;
    // use sea::spot_account;

    // Events ====================================================
    struct EventTrade has store, drop {
        taker_side: u8,
        qty: u64,
        quote_qty: u64,
        pair_id: u64,
        price: u64,
        fee_total: u64,
        fee_maker: u64,
        fee_dao: u64,
        taker_account_id: u64,
        maker_account_id: u64,
        maker_order_id: u64,
        timestamp: u64,
    }

    struct EventOrderComplete has store, drop {
        pair_id: u64,
        order_id: u64,
        price: u64,
        side: u8,
        grid_id: u64,
        account_id: u64,
    }

    // place order event
    struct EventOrderPlace has store, drop {
        qty: u64,
        pair_id: u64,
        order_id: u64,
        price: u64,
        side: u8,
        grid_id: u64,
        account_id: u64,
        is_flip: bool,
    }

    // cancel order event
    struct EventOrderCancel has store, drop {
        qty: u64,
        pair_id: u64,
        order_id: u64,
        price: u64,
        side: u8,
        grid_id: u64,
        account_id: u64,
    }

    // place grid order
    struct EventGrid has store, drop {
        qty: u64,
        grid_id: u64,
        pair_id: u64,
        account_id: u64,
        buy_price0: u64,
        buy_orders: u64,
        sell_price0: u64,
        sell_orders: u64,
        grid_arith: bool,
        grid_base_equal: bool,
    }

    // Structs ====================================================

    struct PlaceOrderOpts has copy, drop {
        addr: address,
        side: u8,
        post_only: bool,
        ioc: bool,
        fok: bool,
        // is_market: bool,
    }

    // OrderInfo order info
    struct OrderInfo has copy, drop {
        side: u8,
        qty: u64,
        price: u64,
        // the grid id or 0 if is not grid
        grid_id: u64,
        // account_id
        account_id: u64,
        order_id: u64,
        base_frozen: u64,
        quote_frozen: u64,
    }

    /// OrderEntity order entity. price, pair_id is on OrderBook
    struct OrderEntity<phantom B, phantom Q> has store {
        // base coin amount
        // we use qty to indicate base amount, vol to indicate quote amount
        qty: u64,
        // the grid id or 0 if is not grid
        grid_id: u64,
        // user address
        // user: address,
        // escrow account id
        account_id: u64,
        base_frozen: Coin<B>,
        quote_frozen: Coin<Q>,
    }

    struct Pair<phantom B, phantom Q> has key {
        paused: bool,
        n_order: u64,
        n_grid: u64,
        fee_ratio: u64,
        base_id: u64,
        quote_id: u64,
        pair_id: u64,
        lot_size: u64,
        min_notional: u64,
        mining_weight: u64,
        price_ratio: u64,       // price_coefficient*pow(10, base_precision-quote_precision)
        price_coefficient: u64, // price coefficient, from 10^1 to 10^12
        last_price: u64,        // last trade price
        last_timestamp: u64,    // last trade timestamp
        trades: u64,
        asks: RBTree<OrderEntity<B, Q>>,
        bids: RBTree<OrderEntity<B, Q>>,
        base_vault: Coin<B>,
        quote_vault: Coin<Q>,

        event_complete: event::EventHandle<EventOrderComplete>,
        event_trade: event::EventHandle<EventTrade>,
        event_place: event::EventHandle<EventOrderPlace>,
        event_cancel: event::EventHandle<EventOrderCancel>,
        event_grid: event::EventHandle<EventGrid>,
    }

    struct QuoteConfig<phantom QuoteType> has key {
        quote_id: u64,
        min_notional: u64,
        // tick_size: u64,
        // quote: Coin<QuoteType>,
    }

    // pairs count
    struct NPair has key {
        n_pair: u64,
        n_grid: u64,
    }

    // price step
    struct PriceStep has copy, drop {
        qty: u64,
        price: u64,
        orders: u64,
    }

    // order key, order qty
    // order_key = price << 64 | order_id
    struct OrderKeyQty has copy, drop {
        qty: u64,
        key: u128,
    }

    struct GridConfig has copy, drop, store {
        arithmetic: bool,
        delta_price_ratio: u64, // if is geometric, the price is ratio
        // qty: u64,
        // base_grid: bool,
        // total_flip: bool,
    }

    struct AccountGrids has key {
        grid_map: Table<u64, GridConfig>,
    }

    /// Stores resource account signer capability under Liquidswap account.
    // struct SpotAccountCapability has key { signer_cap: SignerCapability }

    // Constants ====================================================
    const BUY:                u8   = 1;
    const SELL:               u8   = 2;
    const MAX_PAIR_ID:        u64  = 0xffffff;
    const ORDER_ID_MASK:      u64  = 0xffffffffff; // 40 bit, generate order_id
    const MAX_U64:            u128 = 0xffffffffffffffff;
    const ORDER_ID_MASK_U128: u128 = 0xffffffffffffffff; // 64 bit

    const PRICE_DENOMINATE_64:  u64 = 100000;  // grid price ratio
    const PRICE_DENOMINATE_128: u128 = 100000; // grid price ratio

    // Errors ====================================================
    const E_NO_AUTH:                 u64 = 0x100;
    const E_PAIR_NOT_EXIST:          u64 = 0x101;
    const E_QUOTE_CONFIG_EXISTS:     u64 = 0x102;
    const E_NO_SPOT_MARKET:          u64 = 0x103;
    const E_VOL_EXCEED_MAX_U64:      u64 = 0x104;
    const E_VOL_EXCEED_MAX_U128:     u64 = 0x105;
    const E_PAIR_EXISTS:             u64 = 0x106;
    const E_PAIR_PRICE_INVALID:      u64 = 0x107;
    const E_NOT_QUOTE_COIN:          u64 = 0x108;
    const E_EXCEED_PAIR_COUNT:       u64 = 0x109;
    const E_BASE_NOT_ENOUGH:         u64 = 0x10A;
    const E_QUOTE_NOT_ENOUGH:        u64 = 0x10B;
    const E_PRICE_TOO_LOW:           u64 = 0x10C;
    const E_PRICE_TOO_HIGH:          u64 = 0x10D;
    const E_INITIALIZED:             u64 = 0x10E;
    const E_INVALID_GRID_PRICE:      u64 = 0x10F;
    const E_GRID_PRICE_BUY:          u64 = 0x110;
    const E_GRID_ORDER_COUNT:        u64 = 0x111;
    const E_PAIR_PAUSED:             u64 = 0x112;
    const E_LOT_SIZE:                u64 = 0x113;
    const E_MIN_NOTIONAL:            u64 = 0x114;
    const E_PAIR_PRIORITY:           u64 = 0x115;
    const E_INVALID_PARAM:           u64 = 0x116;
    const E_FOK_NOT_COMPLETE:        u64 = 0x117;
    const E_INVALID_PRICE_COEFF:     u64 = 0x118;
    const E_ORDER_ACCOUNT_NOT_EQUAL: u64 = 0x119;
    const E_ORDER_NOT_EXIST:         u64 = 0x120;
    const E_INVALID_QTY:             u64 = 0x121;
    const E_INVALID_ACCOUNT_ID:      u64 = 0x122;

    fun init_module(sea_admin: &signer) {
        initialize(sea_admin);
    }

    public fun initialize(sea_admin: &signer) {
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);
        assert!(!exists<NPair>(address_of(sea_admin)), E_INITIALIZED);
        // let signer_cap = spot_account::retrieve_signer_cap(sea_admin);
        // move_to(sea_admin, SpotAccountCapability { signer_cap });
        move_to(sea_admin, NPair {
            n_pair: 0,
            n_grid: 0,
        });
    }

    // Admin functions ====================================================
    /// register_quote only the admin can register quote coin
    public entry fun register_quote<QuoteType>(
        account: &signer,
        min_notional: u64,
    ) {
        assert!(address_of(account) == @sea, E_NO_AUTH);
        assert!(!exists<QuoteConfig<QuoteType>>(@sea), E_QUOTE_CONFIG_EXISTS);
        let quote_id = escrow::get_or_register_coin_id<QuoteType>(true);

        move_to(account, QuoteConfig<QuoteType>{
            quote_id: quote_id,
            // tick_size: tick_size,
            min_notional: min_notional,     
            // quote: quote,
        });
        // event
        events::emit_quote_event<QuoteType>(quote_id, min_notional);
    }

    // pause pair, need admin AUTH
    public entry fun pause_pair<B, Q>(
        sea_admin: &signer,
    ) acquires Pair {
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);
        let pair = borrow_global_mut<Pair<B, Q>>(@sea_spot);
        pair.paused = true;
    }

    // withdraw fee
    public entry fun withdraw_fee<B, Q>(
        sea_admin: &signer,
    ) acquires Pair {
        let account_addr = address_of(sea_admin);
        assert!(account_addr == @sea, E_NO_AUTH);
        let pair = borrow_global_mut<Pair<B, Q>>(@sea_spot);

        let base_fee = coin::value(&pair.base_vault);
        if (base_fee > 0) {
            utils::register_coin_if_not_exist<B>(sea_admin);
            coin::deposit<B>(account_addr, coin::extract(&mut pair.base_vault, base_fee));
        };

        let quote_fee = coin::value(&pair.quote_vault);
        if (quote_fee > 0) {
            utils::register_coin_if_not_exist<Q>(sea_admin);
            coin::deposit<Q>(account_addr, coin::extract(&mut pair.quote_vault, quote_fee));
        }
    }

    /// modify pair/pool trade fee
    /// need ADMIN authority
    public entry fun modify_pair_fee<B, Q>(
        sea_admin: &signer,
        fee_level: u64,
        include_amm: bool) acquires Pair {
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);  
        let pair = borrow_global_mut<Pair<B, Q>>(@sea_spot);

        fee::assert_fee_level_valid(fee_level);
        pair.fee_ratio = fee_level;
        if (include_amm) {
            amm::modify_pool_fee<B, Q>(sea_admin, fee_level);
        }
    }

    /// set pair/pool mining weight
    public entry fun set_pair_weight<B, Q>(
        sea_admin: &signer,
        weight: u64,
        include_amm: bool) acquires Pair {
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);  
        let pair = borrow_global_mut<Pair<B, Q>>(@sea_spot);

        pair.mining_weight = weight;
        if (include_amm) {
            amm::set_pool_weight<B, Q>(sea_admin, weight);
        }
    }

    // Public functions ====================================================
    // register pair, quote should be one of the egliable quote
    public entry fun register_pair<B, Q>(
        owner: &signer,
        fee_level: u64,
        price_coefficient: u64,
        lot_size: u64,
    ) acquires NPair, QuoteConfig {
        utils::assert_is_coin<B>();
        utils::assert_is_coin<Q>();
        assert!(escrow::is_quote_coin<Q>(), E_NOT_QUOTE_COIN);
        assert!(!exists<Pair<B, Q>>(@sea_spot), E_PAIR_EXISTS);
        fee::assert_fee_level_valid(fee_level);
        // assert!(price_coefficient == 1000000000 || price_coefficient == 1000000, E_INVALID_PRICE_COEFF);
        assert!(price_coefficient == 1000000000, E_INVALID_PRICE_COEFF);
        valid_lot_size(lot_size);

        let base_id = escrow::get_or_register_coin_id<B>(false);
        let quote_id = escrow::get_or_register_coin_id<Q>(true);
        if (escrow::is_quote_coin<B>()) {
            // if both base and quote is quotable
            assert!(base_id > quote_id, E_PAIR_PRIORITY);
        };
        let quote = borrow_global<QuoteConfig<Q>>(@sea);

        let pair_account = escrow::get_spot_account();
        let base_scale = math::pow_10(coin::decimals<B>());
        let quote_scale = math::pow_10(coin::decimals<Q>());
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
        let pair: Pair<B, Q> = Pair{
            paused: false,
            n_order: 0,
            n_grid: 0,
            fee_ratio: fee_level,
            base_id: base_id,
            quote_id: quote_id,
            pair_id: pair_id,
            lot_size: lot_size,
            min_notional: quote.min_notional,
            mining_weight: 0,
            price_ratio: ratio,       // price_coefficient*pow(10, base_precision-quote_precision)
            price_coefficient: price_coefficient, // price coefficient, from 10^1 to 10^12
            last_price: 0,        // last trade price
            last_timestamp: 0,    // last trade timestamp
            trades: 0,
            asks: rbtree::empty<OrderEntity<B, Q>>(true),  // less price is in left
            bids: rbtree::empty<OrderEntity<B, Q>>(false),
            base_vault: coin::zero(),
            quote_vault: coin::zero(),

            event_trade: account::new_event_handle<EventTrade>(owner),
            event_complete: account::new_event_handle<EventOrderComplete>(owner),
            event_place: account::new_event_handle<EventOrderPlace>(owner),
            event_cancel: account::new_event_handle<EventOrderCancel>(owner),
            event_grid: account::new_event_handle<EventGrid>(owner),
        };
        // create AMM pool
        amm::create_pool<B, Q>(&pair_account, base_id, quote_id, pair_id, fee_level);
        move_to(&pair_account, pair);

        events::emit_pair_event<B, Q>(
            fee_level,
            base_id,
            quote_id,
            pair_id,
            lot_size,
            ratio,
            price_coefficient,
        );
    }

    // place post only order
    public entry fun place_postonly_order<B, Q>(
        account: &signer,
        side: u8,
        price: u64,
        qty: u64,
    ) acquires Pair {
        place_postonly_order_return_id<B, Q>(account, side, price, qty);
    }

    public entry fun place_limit_order<B, Q>(
        account: &signer,
        side: u8,
        price: u64,
        qty: u64,
        ioc: bool,
        fok: bool,
    ) acquires Pair, AccountGrids {
        let pair = borrow_global_mut<Pair<B, Q>>(@sea_spot);
        if (fok) {
            // check this order can be filled
            assert!(fok_fill_complete<B, Q>(pair, side, price, qty), E_FOK_NOT_COMPLETE);
        };
        let taker_addr = address_of(account);
        let opts = &PlaceOrderOpts {
            addr: taker_addr,
            side: side,
            post_only: false,
            ioc: ioc,
            fok: fok,
            // is_market: false,
        };
        let order = new_order<B, Q>(
            account,
            side,
            qty,
            utils::calc_quote_qty(qty, price, pair.price_ratio),
            escrow::get_or_register_account_id(taker_addr),
            0,
        );

        match<B, Q>(account, pair, price, opts, order);
    }

    /*
    public entry fun place_market_order<B, Q>(
        account: &signer,
        side: u8,
        qty: u64,
    ) acquires Pair, AccountGrids {
        let pair = borrow_global_mut<Pair<B, Q>>(@sea_spot);
        let taker_addr = address_of(account);
        let opts = &PlaceOrderOpts {
            addr: taker_addr,
            side: side,
            post_only: false,
            ioc: false,
            fok: false,
            is_market: true,
        };
        let order = new_order<B, Q>(
            account,
            side,
            qty,
            utils::calc_quote_qty(qty, price, pair.price_ratio),
            escrow::get_or_register_account_id(taker_addr),
            0,
        );
        let order = OrderEntity{
            qty: qty,
            grid_id: 0,
            account_id: 0,
            base_frozen: coin::zero(),
            quote_frozen: coin::zero(),
        };

        // we don't check whether the account has enough asset just abort
        match<B, Q>(account, 0, opts, order);
    }
    */

    // param: buy_price0: the highest buy price
    // param: sell_price0: the lowest sell price
    // param: buy_orders: total buy orders
    // param: sell_orders: total sell orders
    // param: per_qty: the base qty of order
    // param: delta_price: 
    public entry fun place_grid_order<B, Q>(
        account: &signer,
        buy_price0: u64,
        sell_price0: u64,
        buy_orders: u64,
        sell_orders: u64,
        per_qty: u64,
        delta_price_ratio: u64,
        arithmetic: bool,
        base_equal: bool,
    ) acquires Pair, AccountGrids {
        if (buy_orders > 0 && sell_orders > 0) {
            assert!(buy_price0 < sell_price0, E_INVALID_GRID_PRICE);
        };
        assert!(buy_orders + sell_orders >= 2, E_GRID_ORDER_COUNT);
        // 
        let account_addr = address_of(account);
        let pair = borrow_global_mut<Pair<B, Q>>(@sea_spot);
        assert!(!pair.paused, E_PAIR_PAUSED);
        let account_id = escrow::get_or_register_account_id(account_addr);
        let grid_id = pair.n_grid + 1;

        pair.n_grid = grid_id;
        grid_id = (pair.pair_id << 40) | grid_id;
        if (!exists<AccountGrids>(account_addr)) {
            let map = table::new<u64, GridConfig>();
            table::add(&mut map, grid_id, GridConfig{
                    delta_price_ratio: delta_price_ratio,
                    arithmetic: arithmetic,
                });
            move_to(account, AccountGrids{ grid_map: map });
        } else {
            let grids = borrow_global_mut<AccountGrids>(account_addr);
            table::add(&mut grids.grid_map, grid_id, GridConfig{
                    arithmetic: arithmetic,
                    delta_price_ratio: delta_price_ratio,
                });
        };

        // event
        event::emit_event<EventGrid>(&mut pair.event_grid, EventGrid{
            qty: per_qty,
            grid_id: grid_id,
            pair_id: pair.pair_id,
            account_id: account_id,
            buy_price0: buy_price0,
            buy_orders: buy_orders,
            sell_price0: sell_price0,
            sell_orders: sell_orders,
            grid_arith: arithmetic,
            grid_base_equal: base_equal,
        });

        if (sell_orders > 0)  {
            let bids = &mut pair.bids;
            if (!rbtree::is_empty(bids)) {
                let bid0 = get_best_price(bids);
                assert!(sell_price0 >= bid0, E_PRICE_TOO_LOW);
            };
            let i = 0;
            let price = sell_price0;
            let qty;
            while (i < sell_orders) {
                qty = grid::next_level_qty(
                    base_equal,
                    per_qty,
                    price,
                    pair.price_ratio,
                    pair.lot_size,
                );

                let order = new_order<B, Q>(
                    account,
                    SELL,
                    qty,
                    0,
                    account_id,
                    grid_id,
                );
                validate_order_qty_price(pair, qty, price);
                place_order(SELL, price, pair, order);
                i = i + 1;
                price = grid::next_level_price(
                    SELL,
                    arithmetic,
                    price,
                    delta_price_ratio,
                );
            }
        };
        if (buy_orders > 0) {
            let asks = &mut pair.asks;
            if (!rbtree::is_empty(asks)) {
                let ask0 = get_best_price(asks);
                assert!(buy_price0 <= ask0, E_PRICE_TOO_HIGH);
            };
            let i = 0;
            let price = buy_price0;
            let qty;
            while (i < buy_orders) {
                qty = grid::next_level_qty(
                    base_equal,
                    per_qty,
                    price,
                    pair.price_ratio,
                    pair.lot_size,
                    );
                validate_order_qty_price(pair, qty, price);
                let order = new_order<B, Q>(
                    account,
                    BUY,
                    qty,
                    utils::calc_quote_qty(qty, price, pair.price_ratio),
                    account_id,
                    grid_id,
                );

                place_order(BUY, price, pair, order);
                price = grid::next_level_price(
                    BUY,
                    arithmetic,
                    price,
                    delta_price_ratio,
                );
                i = i + 1;
            }
        };
        pair.last_timestamp = timestamp::now_seconds();
    }

    // when cancel an order, we need order_key, not just order_id
    // order_key = order_price << 64 | order_id
    // FIXME: should we panic is the order_key not found
    public entry fun cancel_order<B, Q>(
        account: &signer,
        side: u8,
        order_key: u128,
        // to_escrow: bool
        ) acquires Pair {
        let pair = borrow_global_mut<Pair<B, Q>>(@sea_spot);
        let account_addr = address_of(account);

        if (!coin::is_account_registered<B>(account_addr)) {
            coin::register<B>(account);
        };
        if (!coin::is_account_registered<Q>(account_addr)) {
            coin::register<Q>(account);
        };
        cancel_order_by_key<B, Q>(account_addr, side, order_key, pair);

        pair.last_timestamp = timestamp::now_seconds();
    }

    public entry fun cancel_batch_orders<B, Q>(
        account: &signer,
        sides: vector<u8>,
        orders_key: vector<u128>) acquires Pair {
        let pair = borrow_global_mut<Pair<B, Q>>(@sea_spot);
        assert!(vector::length(&sides) == vector::length(&orders_key), E_INVALID_PARAM);

        let account_addr = address_of(account);
        if (!coin::is_account_registered<B>(account_addr)) {
            coin::register<B>(account);
        };
        if (!coin::is_account_registered<Q>(account_addr)) {
            coin::register<Q>(account);
        };

        let i = 0;
        while (i < vector::length(&sides)) {
            let side = vector::borrow(&sides, i);
            let order_key = vector::borrow(&orders_key, i);
            cancel_order_by_key<B, Q>(account_addr, *side, *order_key, pair);

            i = i + 1;
        };

        pair.last_timestamp = timestamp::now_seconds();
    }

    // Public functions ====================================================

    // return: account_id
    // return: grid_id
    // return: base_frozen
    // return: quote_frozen
    public fun get_order_info<B, Q>(
        account: &signer,
        side: u8,
        order_key: u128,
    ): (u64, u64, u64, u64, u64) acquires Pair {
        let account_addr = address_of(account);
        let pair = borrow_global<Pair<B, Q>>(@sea_spot);
        let tree = if (side == SELL) &pair.asks else &pair.bids;

        let pos = rbtree::rb_find(tree, order_key);
        if (pos == 0) {
            return (0, 0,  0, 0, 0)
        };
        let account_id = escrow::get_account_id(account_addr);
        let order = rbtree::borrow_by_pos(tree, pos);
        assert!(order.account_id == account_id, E_ORDER_ACCOUNT_NOT_EQUAL);

        (account_id, order.qty, order.grid_id, coin::value(&order.base_frozen), coin::value(&order.quote_frozen))
    }

    // get_account_pair_orders get account pair orders, both asks and bids
    // return: (bid orders, ask orders)
    public fun get_account_pair_orders<B, Q>(
        account: &signer,
    ): (vector<OrderInfo>, vector<OrderInfo>) acquires Pair {
        let account_addr = address_of(account);
        let account_id = escrow::get_account_id(account_addr);
        let pair = borrow_global<Pair<B, Q>>(@sea_spot);

        (
            get_account_side_orders(BUY, account_id, &pair.bids),
            get_account_side_orders(SELL, account_id, &pair.asks)
        )
    }

    public fun new_order<B, Q>(
        account: &signer,
        side: u8,
        base_qty: u64,
        quote_qty: u64,
        account_id: u64,
        grid_id: u64,
    ): OrderEntity<B, Q> {
        OrderEntity{
            qty: base_qty,
            grid_id: grid_id,
            account_id: account_id,
            base_frozen: if (side == BUY) coin::zero() else coin::withdraw(account, base_qty),
            quote_frozen: if (side == SELL) coin::zero() else coin::withdraw(account, quote_qty),
        }
    }

    public fun build_order<B, Q>(
        account_id: u64,
        grid_id: u64,
        base_qty: u64,
        base_frozen: Coin<B>,
        quote_frozen: Coin<Q>
    ): OrderEntity<B, Q> {
        OrderEntity{
            qty: base_qty,
            grid_id: grid_id,
            account_id: account_id,
            base_frozen: base_frozen,
            quote_frozen: quote_frozen,
        }
    }

    // extract order
    public fun extract_order<B, Q>(
        order: OrderEntity<B, Q>
    ): (Coin<B>, Coin<Q>) {
        let OrderEntity {
                    account_id: _,
                    grid_id: _,
                    qty: _,
                    base_frozen: base_frozen,
                    quote_frozen: quote_frozen,
        } = order;

        (base_frozen, quote_frozen)
    }
    
    public fun destroy_order<B, Q>(
        addr: address,
        order: OrderEntity<B, Q>
    ) {
        let OrderEntity {
            qty: _,
            grid_id: _,
            account_id: _,
            base_frozen: base_frozen,
            quote_frozen: quote_frozen,
        } = order;

        if (coin::value(&base_frozen) > 0) {
            coin::deposit(addr, base_frozen);
        } else {
            coin::destroy_zero(base_frozen);
        };
        if (coin::value(&quote_frozen) > 0) {
            coin::deposit(addr, quote_frozen);
        } else {
            coin::destroy_zero(quote_frozen);
        };
    }

    public fun place_postonly_order_return_id<B, Q>(
        account: &signer,
        side: u8,
        price: u64,
        qty: u64,
    ): u128 acquires Pair {
        let account_addr = address_of(account);
        let pair = borrow_global_mut<Pair<B, Q>>(@sea_spot);

        assert!(!pair.paused, E_PAIR_PAUSED);
        validate_order_qty_price(pair, qty, price);

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
                assert!(price <= ask0, E_PRICE_TOO_HIGH);
            }
        };
        // let order = OrderEntity{
        //     qty: qty,
        //     grid_id: 0,
        //     account_id: escrow::get_or_register_account_id(account_addr),
        //     base_frozen: coin::zero(),
        //     quote_frozen: coin::zero(),
        // };
        let quote_qty = utils::calc_quote_qty(qty, price, pair.price_ratio);
        let order = new_order(
            account,
            side,
            qty,
            quote_qty,
            escrow::get_or_register_account_id(account_addr),
            0,
        );
        pair.last_timestamp = timestamp::now_seconds();
        return place_order(side, price, pair, order)
    }

    // the caller should extract the left order after matching
    public fun match_order<B, Q>(
        taker_addr: address,
        side: u8,
        price: u64,
        order: OrderEntity<B, Q>,
    ): (bool, u64, OrderEntity<B, Q>) acquires Pair, AccountGrids {
        let pair = borrow_global_mut<Pair<B, Q>>(@sea_spot);
        assert!(!pair.paused, E_PAIR_PAUSED);
        validate_order(pair, side, price, &order);

        let (completed, filled) = match_internal(taker_addr, side, price, pair, &mut order);
        pair.last_timestamp = timestamp::now_seconds();

        (completed, filled, order)
    }

    // just place order, same as postonly.
    // for other module call
    public fun place_the_order<B, Q>(
        side: u8,
        price: u64,
        order: OrderEntity<B, Q>,
        ): u128 acquires Pair {
        let pair = borrow_global_mut<Pair<B, Q>>(@sea_spot);

        assert!(!pair.paused, E_PAIR_PAUSED);
        assert!(order.account_id > 0, E_INVALID_PARAM);
        let qty: u64;
        if (side == SELL) {
            let bids = &mut pair.bids;
            if (!rbtree::is_empty(bids)) {
                let bid0 = get_best_price(bids);
                assert!(price >= bid0, E_PRICE_TOO_LOW);
            };

            qty = coin::value(&order.base_frozen);
        } else {
            let asks = &mut pair.asks;
            if (!rbtree::is_empty(asks)) {
                let ask0 = get_best_price(asks);
                assert!(price <= ask0, E_PRICE_TOO_HIGH);
            };

            let quote_qty = coin::value(&order.quote_frozen);
            qty = utils::calc_base_qty(quote_qty, price, pair.price_ratio);
            if (pair.lot_size > 0) {
                qty = qty / pair.lot_size * pair.lot_size;
            };
            assert!(utils::calc_quote_qty(qty, price, pair.price_ratio) == quote_qty, E_INVALID_QTY);
        };
        validate_order_qty_price(pair, qty, price);

        place_order(side, price, pair, order)
    }

    // Private functions ====================================================

    fun incr_pair_grid_id<B, Q>(
        pair: &mut Pair<B, Q>
    ): u64 {
        let grid_id = pair.n_grid + 1;
        pair.n_grid = grid_id;
        (pair.pair_id << 40) | grid_id
    }

    fun cancel_order_by_key<B, Q>(
        account_addr: address,
        side: u8,
        order_key: u128,
        pair: &mut Pair<B, Q>,
    ) {
        let (price, order_id) = extract_order_key(order_key);

        if (side == BUY) {
            // frozen is quote
            let orderbook = &mut pair.bids;
            let pos = rbtree::rb_find(orderbook, order_key);
            assert!(pos != 0, E_ORDER_NOT_EXIST);
            let (_, order) = rbtree::rb_remove_by_pos(orderbook, pos);
            // quote
            let OrderEntity {
                    account_id: account_id,
                    grid_id: grid_id,
                    qty: qty,
                    base_frozen: base_frozen,
                    quote_frozen: quote_frozen,
                } = order;
            // event
            event::emit_event<EventOrderCancel>(&mut pair.event_cancel, EventOrderCancel{
                qty: qty,
                pair_id: pair.pair_id,
                order_id: order_id,
                price: price,
                side: side,
                grid_id: grid_id,
                account_id: account_id,
            });
            // return_coin_to_account<Q>(account, account_addr, quote_frozen);
            coin::deposit(account_addr, quote_frozen);
            if (grid_id > 0 && coin::value(&base_frozen) > 0) {
                // return_coin_to_account<B>(account, account_addr, base_frozen);
                coin::deposit(account_addr, base_frozen);
            } else {
                coin::destroy_zero(base_frozen);
            }
        } else {
            let orderbook = &mut pair.asks;
            let pos = rbtree::rb_find(orderbook, order_key);
            assert!(pos != 0, E_ORDER_NOT_EXIST);

            let (_, order) = rbtree::rb_remove_by_pos(orderbook, pos);
            let OrderEntity {
                    account_id: account_id,
                    grid_id: grid_id,
                    qty: qty,
                    base_frozen: base_frozen,
                    quote_frozen: quote_frozen,
                } = order;
            // event
            event::emit_event<EventOrderCancel>(&mut pair.event_cancel, EventOrderCancel{
                qty: qty,
                pair_id: pair.pair_id,
                order_id: order_id,
                price: price,
                side: side,
                grid_id: grid_id,
                account_id: account_id,
            });
            
            // return_coin_to_account<B>(account, account_addr, base_frozen);
            coin::deposit(account_addr, base_frozen);
            if (grid_id > 0 && coin::value(&quote_frozen) > 0) {
                // return_coin_to_account<Q>(account, account_addr, quote_frozen);
                coin::deposit(account_addr, quote_frozen);
            } else {
                coin::destroy_zero(quote_frozen);
            }
        };
    }

    fun get_account_side_orders<B, Q>(
        side: u8,
        account_id: u64,
        tree: &RBTree<OrderEntity<B, Q>>,
    ): vector<OrderInfo> {
        let orders = vector::empty<OrderInfo>();

        if (!rbtree::is_empty(tree)) {
            let (pos, key, item) = rbtree::get_leftmost_pos_key_val(tree);
            push_order(&mut orders, side, account_id, key, item);
            while (true) {
                let (next_pos, next_key) = rbtree::get_next_pos_key(tree, pos);
                if (next_key == 0) {
                    break
                };
                pos  = next_pos;
                key = next_key;
                item = rbtree::borrow_by_pos<OrderEntity<B, Q>>(tree, next_pos);
                push_order(&mut orders, side, account_id, key, item);
            }
        };

        orders
    }

    fun validate_order<B, Q>(
        pair: &Pair<B, Q>,
        side: u8,
        price: u64,
        order: &OrderEntity<B, Q>
    ) {
        let qty = order.qty;
        if (side == SELL) {
            assert!(coin::value(&order.base_frozen) == qty, E_BASE_NOT_ENOUGH);
        } else {
            let quote_qty = utils::calc_quote_qty(qty, price, pair.price_ratio);
            assert!(coin::value(&order.quote_frozen) == quote_qty, E_QUOTE_NOT_ENOUGH);
        };

        validate_order_qty_price(pair, qty, price);
    }

    // validate order qty, price, min_notional
    fun validate_order_qty_price<B, Q>(
        pair: &Pair<B, Q>,
        qty: u64,
        price: u64,
    ) {
        assert!(qty >= pair.lot_size, E_LOT_SIZE);
        assert!(price::is_valid_price(price), E_PAIR_PRICE_INVALID);
        assert!(filter_lot_size(qty, pair.lot_size), E_LOT_SIZE);
        assert!(filter_min_notional(pair, qty, price), E_MIN_NOTIONAL);
    }

    fun filter_lot_size(qty: u64, lot_size: u64): bool {
        (qty / lot_size) * lot_size == qty
    }

    fun valid_lot_size(lot_size: u64) {
        assert!(lot_size == 1 || lot_size == 10 || lot_size == 100 ||
            lot_size == 1000 || lot_size == 10000 || lot_size == 100000 ||
            lot_size == 1000000 || lot_size == 10000000 || lot_size == 100000000, E_LOT_SIZE)
    }

    fun filter_min_notional<B, Q>(
        pair: &Pair<B, Q>,
        qty: u64,
        price: u64,
    ): bool {
        let vol = calc_quote_vol_for_buy(qty, price, pair.price_ratio);
        vol >= pair.min_notional
    }

    fun push_order<B, Q>(
        orders: &mut vector<OrderInfo>,
        side: u8,
        account_id: u64,
        key: u128,
        item: &OrderEntity<B, Q>,
    ) {
        let (price, order_id) = extract_order_key(key);
        if (item.account_id == account_id) {
            vector::push_back(orders, OrderInfo {
                account_id: account_id,
                grid_id: item.grid_id,
                order_id: order_id,
                price: price,
                qty: item.qty,
                side: side,
                base_frozen: coin::value(&item.base_frozen),
                quote_frozen: coin::value(&item.quote_frozen),
            });
        };
    }

    fun get_price_steps<B, Q>(
        tree: &RBTree<OrderEntity<B, Q>>
    ): vector<PriceStep> {
        let steps = vector::empty<PriceStep>();

        if (!rbtree::is_empty(tree)) {
            let (pos, key, item) = rbtree::get_leftmost_pos_key_val(tree);
            let price = price_from_key(key);
            let next_price;
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

                next_price = price_from_key(next_key);
                let next_order = rbtree::borrow_by_pos<OrderEntity<B, Q>>(tree, next_pos);
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
                price = next_price;
            }
        };
        steps
    }

    // when we cancel an order, we need the key, not only the order_id
    fun get_order_key_qty_list<B, Q>(
        tree: &RBTree<OrderEntity<B, Q>>
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

    fun extract_order_key(key: u128): (u64, u64) {
        (((key >> 64) as u64), ((key & ORDER_ID_MASK_U128) as u64))
    }

    /// match buy order, taker is buyer, maker is seller
    /// 
    fun match<B, Q>(
        taker: &signer,
        pair: &mut Pair<B, Q>,
        price: u64,
        opts: &PlaceOrderOpts,
        taker_order: OrderEntity<B, Q>
    ): u128 acquires AccountGrids {
        let taker_addr = address_of(taker);

        assert!(!pair.paused, E_PAIR_PAUSED);
        validate_order(pair, opts.side, price, &taker_order);

        let (completed, base_filled) = match_internal(
            taker_addr,
            opts.side,
            price,
            pair,
            &mut taker_order,
        );

        pair.last_timestamp = timestamp::now_seconds();
        if ((!completed) && (!opts.ioc)) {
            // make sure order qty >= lot_size
            // place order to orderbook
            if (pair.lot_size > 0 && taker_order.qty >= pair.lot_size) {
                let nqty = taker_order.qty / pair.lot_size * pair.lot_size;
                if (opts.side == BUY) {
                    //
                    let nquote_qty = utils::calc_quote_qty(nqty, price, pair.price_ratio);
                    let quote_left = coin::value(&taker_order.quote_frozen) - nquote_qty;
                    if (quote_left > 0) {
                        coin::deposit(taker_addr, coin::extract(&mut taker_order.quote_frozen, quote_left));
                    };
                    if (base_filled > 0) {
                        // coin::value(&taker_order.base_frozen) + fee = base_filled
                        coin::deposit(taker_addr, coin::extract_all(&mut taker_order.base_frozen));
                    }
                } else {
                    let base_left = taker_order.qty-nqty;
                    if (base_left > 0) {
                        coin::deposit(taker_addr, coin::extract(&mut taker_order.base_frozen, base_left));
                    }
                };
                place_order(opts.side, price, pair, taker_order)
            } else {
                destroy_order(taker_addr, taker_order);

                0
            }
        } else {
            destroy_order(taker_addr, taker_order);

            0
        }
    }

    fun place_order<B, Q>(
        // account: &signer,
        side: u8,
        price: u64,
        pair: &mut Pair<B, Q>,
        order: OrderEntity<B, Q>
    ): u128 {
        let qty = order.qty;

        assert!(order.account_id > 0, E_INVALID_ACCOUNT_ID);
        let order_id = generate_order_id(pair);
        let orderbook = if (side == BUY) &mut pair.bids else &mut pair.asks;
        let key: u128 = generate_key(price, order_id);

        // event
        event::emit_event<EventOrderPlace>(&mut pair.event_place, EventOrderPlace{
            qty: qty,
            pair_id: pair.pair_id,
            order_id: order_id,
            price: price,
            side: side,
            grid_id: order.grid_id,
            account_id: order.account_id,
            is_flip: false,
        });
        rbtree::rb_insert<OrderEntity<B, Q>>(orderbook, key, order);

        key
    }

    fun generate_key(price: u64, order_id: u64): u128 {
        (((price as u128) << 64) | (order_id as u128))
    }

    fun generate_order_id<B, Q>(
        pair: &mut Pair<B, Q>,
        ): u64 {
        // first 24 bit is pair_id
        // left 40 bit is order_id
        let id = pair.pair_id << 40 | (pair.n_order & ORDER_ID_MASK);
        pair.n_order = pair.n_order + 1;
        id
    }

    fun fok_fill_complete<B, Q>(
        pair: &mut Pair<B, Q>,
        taker_side: u8,
        price: u64,
        qty: u64,
    ): bool {
        let orderbook = if (taker_side == BUY) &mut pair.asks else &mut pair.bids;
        let completed = false;

        while (!rbtree::is_empty(orderbook)) {
            let (_, key, order) = rbtree::borrow_leftmost_keyval_mut(orderbook);
            let (maker_price, _) = price::get_price_order_id(key);
            if (((taker_side == BUY && price < maker_price) ||
                    (taker_side == SELL && price >  maker_price))
             ) {
                break
            };
            if (order.qty >= qty) {
                completed = true;
                break
            } else {
                qty = qty - order.qty;
            }
        };

        completed
    }

    // return: bool: if the taker order has completed
    // return: u64: the filled base qty
    fun match_internal<B, Q>(
        taker_addr: address,
        taker_side: u8,
        price: u64,
        pair: &mut Pair<B, Q>,
        taker_order: &mut OrderEntity<B, Q>,
    ): (bool, u64) acquires AccountGrids {
        let last_price = 0;
        let trades = 0;

        let (orderbook, peer_tree) = if (taker_side == BUY) {
                (&mut pair.asks, &mut pair.bids)
            } else { (&mut pair.bids, &mut pair.asks ) };
        let event_complete = &mut pair.event_complete;
        let event_place = &mut pair.event_place;
        let base_fee = coin::zero<B>();
        let quote_fee = coin::zero<Q>();
        let pair_id = pair.pair_id;
        let total_filled = 0;
        let taker_completed: bool = false;

        while (!rbtree::is_empty(orderbook)) {
            let (pos, key, order) = rbtree::borrow_leftmost_keyval_mut(orderbook);
            let (maker_price, maker_order_id) = price::get_price_order_id(key);
            if (
                ((taker_side == BUY && price < maker_price) ||
                (taker_side == SELL && price >  maker_price))
             ) {
                break
            };

            let maker_addr = escrow::get_account_addr_by_id(order.account_id);
            let (taker_complete, maker_complete, trade_event) = swap_order(
                taker_side,
                pair.price_ratio,
                pair.fee_ratio,
                maker_price,
                maker_addr,
                taker_order,
                order,
                &mut base_fee,
                &mut quote_fee,
            );
            if (pair.mining_weight > 0) {
                // mining
                mining::on_trade(taker_addr, maker_addr, pair.mining_weight * trade_event.quote_qty);
            };
            total_filled = total_filled + trade_event.qty;
            trade_event.pair_id = pair_id;
            trade_event.maker_order_id = maker_order_id;
            event::emit_event(&mut pair.event_trade, trade_event);

            if (maker_complete) {
                let (_, pop_order) = rbtree::rb_remove_by_pos(orderbook, pos);
                let maker_side = if (taker_side == BUY) SELL else BUY;
                // let (_, maker_order_id) = extract_order_key(pop_order_key);
                event::emit_event<EventOrderComplete>(event_complete, EventOrderComplete{
                    pair_id: pair_id,
                    order_id: maker_order_id,
                    price: maker_price,
                    side: maker_side,
                    grid_id: pop_order.grid_id,
                    account_id: pop_order.account_id,
                });

                // if is grid order, flip it
                if (pop_order.grid_id > 0) {
                    let grid_id = pop_order.grid_id;
                    let account_id = pop_order.account_id;
                    let n_order_id = pair_id << 40 | (pair.n_order & ORDER_ID_MASK);
                    pair.n_order = pair.n_order + 1;
                    let (nprice, n_qty) = flip_grid_order(taker_side,
                        maker_price,
                        n_order_id,
                        pair.price_ratio,
                        pair.lot_size,
                        peer_tree,
                        pop_order,
                        );

                    event::emit_event<EventOrderPlace>(event_place, EventOrderPlace{
                        qty: n_qty,
                        pair_id: pair_id,
                        order_id: n_order_id,
                        price: nprice,
                        side: taker_side,
                        grid_id: grid_id,
                        account_id: account_id,
                        is_flip: true
                    });
                } else {
                    let addr = escrow::get_account_addr_by_id(pop_order.account_id);
                    destroy_order<B, Q>(addr, pop_order);
                };
            };
            last_price = maker_price;
            trades = trades + 1;
            if (taker_complete) {
                taker_completed = true;
                break
            }
        };
        if (last_price > 0) {
            pair.last_price = last_price;
            pair.trades = pair.trades + trades
        };

        coin::merge(&mut pair.base_vault, base_fee);
        coin::merge(&mut pair.quote_vault, quote_fee);

        // if order is match completed
        (taker_completed, total_filled)
    }

    fun get_grid_config(
        account_addr: address,
        grid_id: u64
    ): (bool, u64) acquires AccountGrids {
        let grids = borrow_global<AccountGrids>(account_addr);
        let gc = table::borrow(&grids.grid_map, grid_id);
        (gc.arithmetic, gc.delta_price_ratio)
    }

    // side: the next fliped order's side
    // return: (nprice, base_qty)
    fun flip_grid_order<B, Q>(
        side: u8,
        maker_price: u64,
        order_id: u64,
        price_ratio: u64,
        lot_size: u64,
        tree: &mut RBTree<OrderEntity<B, Q>>,
        order: OrderEntity<B, Q>,
        // pair: &Pair<B, Q>,
    ): (u64, u64) acquires AccountGrids {
        let OrderEntity {
            qty: _,
            grid_id: grid_id,
            account_id: account_id,
            base_frozen: base_frozen,
            quote_frozen: quote_frozen,
        } = order;
        let addr = escrow::get_account_addr_by_id(account_id);
        let (grid_arith, delta_price) = get_grid_config(addr, grid_id);

        if (side == SELL) {
            // fliped order is SELL order
            let qty = coin::value(&base_frozen);
            let (nprice, nqty, _) = grid::calc_grid_order_price_qty(
                side,
                grid_arith,
                maker_price,
                delta_price,
                qty,
                price_ratio,
                lot_size,
                );
            let n_base_frozen = coin::extract(&mut base_frozen, nqty);
            let filp_order = OrderEntity<B, Q> {
                qty: nqty,
                grid_id: grid_id,
                account_id: account_id,
                base_frozen: n_base_frozen,
                quote_frozen: coin::zero(),
            };
            if (coin::value(&base_frozen) > 0) {
                coin::deposit<B>(addr, base_frozen);
            } else {
                coin::destroy_zero(base_frozen);
            };
            if (coin::value(&quote_frozen) > 0) {
                // escrow::incr_escrow_coin<QuoteType>(addr, quote_frozen);
                coin::deposit<Q>(addr, quote_frozen);
            } else {
                coin::destroy_zero(quote_frozen);
            };
            
            rbtree::rb_insert(tree, generate_key(nprice, order_id), filp_order);

            (nprice, nqty)
        } else {
            // flip order is BUY order
            // let (qty, remnant) = calc_base_qty_can_buy(coin::value(&quote_frozen), price, price_ratio);
            // let quote_needed = calc_quote_vol_for_buy(grid_qty, price, price_ratio);
            let quote_qty = coin::value(&quote_frozen);
            let (nprice, nqty, nquote_qty) = grid::calc_grid_order_price_qty(
                side,
                grid_arith,
                maker_price,
                delta_price,
                quote_qty,
                price_ratio,
                lot_size,
                );
            let n_quote_frozen = coin::extract(&mut quote_frozen, nquote_qty);
            let filp_order = OrderEntity<B, Q> {
                qty: nqty,
                grid_id: grid_id,
                account_id: account_id,
                base_frozen: coin::zero(),
                quote_frozen: n_quote_frozen,
            };
            if (coin::value(&base_frozen) > 0) {
                coin::deposit<B>(addr, base_frozen);
            } else {
                coin::destroy_zero(base_frozen);
            };
            if (coin::value(&quote_frozen) > 0) {
                coin::deposit<Q>(addr, quote_frozen);
            } else {
                coin::destroy_zero(quote_frozen);
            };

            rbtree::rb_insert(tree, generate_key(nprice, order_id), filp_order);
            (nprice, nqty)
        }
    }


    // how many quote is need when buy qty base
    // return: the quote volume needed
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

    // return: how many base can buy
    // return: how many quote left
    fun calc_base_qty_can_buy(
        vol: u64,
        price: u64,
        price_ratio: u64
    ): (u64, u64) {
        let vol_ampl = (vol as u128) * (price_ratio as u128);
        let qty = ((vol_ampl / (price as u128)) as u64);
        let left = vol - calc_quote_vol_for_buy(qty, price, price_ratio);
        (qty, left)
    }

    // calculate quote volume: quote_vol = price * base_amt
    // return: the quote needed
    // return: the trade fee
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
                (qty as u128) * (fee_ratio as u128) / (fee::get_fee_denominate() as u128) // 1000000
            } else {
                vol * (fee_ratio as u128) / (fee::get_fee_denominate() as u128)
            });
        assert!(fee < MAX_U64, E_VOL_EXCEED_MAX_U64);
        ((vol as u64), (fee as u64))
    }

    // return: (taker_complete, maker_complete)
    fun swap_order<B, Q>(
        taker_side: u8, // taker side
        price_ratio: u64,
        fee_ratio: u64,
        maker_price: u64,
        maker_addr: address,
        taker_order: &mut OrderEntity<B, Q>,
        maker_order: &mut OrderEntity<B, Q>,
        base_fee: &mut Coin<B>,
        quote_fee: &mut Coin<Q>,
    ):(bool, bool, EventTrade) {
        let (match_qty, taker_complete, maker_complete) = 
            if (taker_order.qty >= maker_order.qty) {
                if (taker_order.qty == maker_order.qty) {
                    (taker_order.qty, true, true)
                } else {
                    (maker_order.qty, false, true)
                }
            } else {
                (taker_order.qty, true, false)
            };

        let (quote_vol, fee_amt) = calc_quote_vol(taker_side, match_qty, maker_price, price_ratio, fee_ratio);
        let (fee_maker, fee_plat) = fee::get_maker_fee_shares(fee_amt, maker_order.grid_id > 0);

        taker_order.qty = taker_order.qty - match_qty;
        maker_order.qty = maker_order.qty - match_qty;
        if (taker_side == BUY) {
            let to_taker = coin::extract<B>(&mut maker_order.base_frozen, match_qty);
            let maker_fee_prop = coin::extract<B>(&mut to_taker, fee_maker);
            coin::deposit<B>(maker_addr, maker_fee_prop);
            if (fee_plat > 0) {
                // platform vault
                let to_plat = coin::extract(&mut to_taker, fee_plat);
                coin::merge(base_fee, to_plat);
            };

            coin::merge(&mut taker_order.base_frozen, to_taker);
            // maker got quote coin
            let quote = coin::extract<Q>(&mut taker_order.quote_frozen, quote_vol);

            // if the maker is grid
            if (maker_order.grid_id > 0) {
                coin::merge(&mut maker_order.quote_frozen, quote);
            } else {
                coin::deposit<Q>(maker_addr, quote);
            }
        } else {
            // taker got quote coin
            let to_taker = coin::extract<Q>(&mut maker_order.quote_frozen, quote_vol);
            let maker_fee_prop = coin::extract<Q>(&mut to_taker, fee_maker);
            coin::deposit<Q>(maker_addr, maker_fee_prop);
            if (fee_plat > 0) {
                // platform vault
                let to_plat = coin::extract(&mut to_taker, fee_plat);
                coin::merge(quote_fee, to_plat);
            };
            coin::merge(&mut taker_order.quote_frozen, to_taker);

            // maker got base coin
            let base = coin::extract<B>(&mut taker_order.base_frozen, match_qty);

            // if the maker is grid
            if (maker_order.grid_id > 0) {
                coin::merge(&mut maker_order.base_frozen, base);
            } else {
                coin::deposit<B>(maker_addr, base);
            }
        };

        let trade_event = EventTrade{
            taker_side: taker_side,
            qty: match_qty,
            quote_qty: quote_vol,
            pair_id: 0,
            price: maker_price,
            fee_total: fee_amt,
            fee_maker: fee_maker,
            fee_dao: fee_plat,
            taker_account_id: taker_order.account_id,
            maker_account_id: maker_order.account_id,
            maker_order_id: 0,
            timestamp: timestamp::now_seconds(),
        };

        (taker_complete, maker_complete, trade_event)
    }

    /*
    // direct transfer coin to taker account
    // increase maker escrow
    fun swap_internal<B, Q>(
        pair_base_vault: &mut Coin<B>,
        pair_quote_vault: &mut Coin<Q>,
        taker: &signer,
        taker_opts: &PlaceOrderOpts,
        maker_order: &mut OrderEntity<B, Q>,
        base_qty: u64,
        quote_vol: u64,
        fee_plat_amt: u64,
        fee_maker_amt: u64,
    ) {
        let maker_addr = escrow::get_account_addr_by_id(maker_order.account_id);
        let taker_addr = taker_opts.addr;

        if (taker_opts.side == BUY) {
            // taker got base coin
            // let to_taker = escrow::dec_escrow_coin<B>(maker_addr, base_qty);
            let to_taker = coin::extract<B>(&mut maker_order.base_frozen, base_qty);
            let maker_fee_prop = coin::extract<B>(&mut to_taker, fee_maker_amt);
            // escrow::incr_escrow_coin<B>(maker_addr, maker_fee_prop);
            coin::deposit<B>(maker_addr, maker_fee_prop);
            if (fee_plat_amt > 0) {
                // platform vault
                let to_plat = coin::extract(&mut to_taker, fee_plat_amt);
                coin::merge(pair_base_vault, to_plat);
            };

            coin::deposit(taker_addr, to_taker);
            // maker got quote coin
            let quote = coin::withdraw<Q>(taker, quote_vol);

            // if the maker is grid
            if (maker_order.grid_id > 0) {
                coin::merge(&mut maker_order.quote_frozen, quote);
            } else {
                // escrow::incr_escrow_coin<Q>(maker_addr, quote);
                coin::deposit<Q>(maker_addr, quote);
            }
        } else {
            // taker got quote coin
            // let to_taker = escrow::dec_escrow_coin<Q>(maker_addr, quote_vol);
            let to_taker = coin::extract<Q>(&mut maker_order.quote_frozen, quote_vol);
            let maker_fee_prop = coin::extract<Q>(&mut to_taker, fee_maker_amt);
            // escrow::incr_escrow_coin<Q>(maker_addr, maker_fee_prop);
            coin::deposit<Q>(maker_addr, maker_fee_prop);
            if (fee_plat_amt > 0) {
                // platform vault
                let to_plat = coin::extract(&mut to_taker, fee_plat_amt);
                coin::merge(pair_quote_vault, to_plat);
            };
            coin::deposit(taker_addr, to_taker);

            // maker got base coin
            let base = coin::withdraw<B>(taker, base_qty);

            // if the maker is grid
            if (maker_order.grid_id > 0) {
                coin::merge(&mut maker_order.base_frozen, base);
            } else {
                // escrow::incr_escrow_coin<B>(maker_addr, base);
                coin::deposit<B>(maker_addr, base);
            }
        }
    }
    */

    // Test-only functions ====================================================
    #[test_only]
    use sea::spot_account;
    #[test_only]
    use std::string;
    #[test_only]
    use aptos_framework::aptos_account;
    #[test_only]
    use aptos_framework::genesis;
    // #[test_only]
    // use aptos_framework::account;
    // #[test_only]
    // use std::debug;

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
    fun test_prepare_account_env(): signer {
        genesis::setup();
        account::create_account_for_test(@sea_spot);
        let sea_admin = account::create_account_for_test(@sea);

        spot_account::initialize_spot_account(&sea_admin);
        events::initialize(&sea_admin);
        initialize(&sea_admin);
        escrow::initialize(&sea_admin);
        fee::initialize(&sea_admin);

        sea_admin
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
    fun test_get_pair_price_steps<B, Q>():
        (u64, vector<PriceStep>, vector<PriceStep>) acquires Pair {
        let pair = borrow_global<Pair<B, Q>>(@sea_spot);
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
        // aptos_account::create_account(address_of(sea_admin));
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
        // escrow_avail: u64,
        idx: u64,
        // escrow_frozen: u64,
    ) {
        assert!(coin::balance<CoinType>(addr) == balance, 100+idx);
    }

    #[test_only]
    fun test_get_order_key(
        price: u64,
        pair_id: u64,
        order_id: u64,
    ): u128 {
        generate_key(price, (pair_id << 40) | order_id)
    }

    #[test_only]
    fun test_check_orders<B, Q>(
        ask_steps: vector<PriceStep>,
        bid_steps: vector<PriceStep>,
    ) acquires Pair {
        // use std::debug;
        let (_, asks, bids) = test_get_pair_price_steps<B, Q>();

        assert!(vector::length(&asks) == vector::length(&ask_steps), 1000);
        assert!(vector::length(&bids) == vector::length(&bid_steps), 1001);
        let i = 0;
        while(i < vector::length(&asks)) {
            let ask = vector::borrow(&asks, i);
            let ask_step = vector::borrow(&ask_steps, i);

            assert!(ask.qty == ask_step.qty, 2000+i);
            assert!(ask.price == ask_step.price, 3000+i);
            assert!(ask.orders == ask_step.orders, 4000+i);
            i = i + 1;
        };

        i = 0;
        while(i < vector::length(&bids)) {
            let bid = vector::borrow(&bids, i);
            let bid_step = vector::borrow(&bid_steps, i);

            assert!(bid.qty == bid_step.qty, 5000+i);
            assert!(bid.price == bid_step.price, 6000+i);
            assert!(bid.orders == bid_step.orders, 7000+i);
            i = i + 1;
        };
    }

    #[test_only]
    fun test_get_orderbook_keys<B, Q>(
        tree: &RBTree<OrderEntity<B, Q>>
    ): vector<u128> {
        let keys = vector::empty<u128>();

        if (!rbtree::is_empty(tree)) {
            let (pos, key, _) = rbtree::get_leftmost_pos_key_val(tree);
            // let price = price_from_key(key);
            // let qty: u64 = item.qty;
            // let orders: u64 = 1;
            while (true) {
                vector::push_back(&mut keys, key);
                let (next_pos, next_key) = rbtree::get_next_pos_key(tree, pos);

                if (next_key == 0) {
                    // vector::push_back(&mut keys, next_key);
                    break
                };

                key = next_key;
                pos = next_pos;
            }
        };
        keys
    }

    #[test_only]
    fun test_get_pair_order_key<B, Q>(): vector<u128> acquires Pair {
        let pair = borrow_global<Pair<B, Q>>(@sea_spot);
        let ask_orders = test_get_orderbook_keys<B, Q>(&pair.asks);
        let bid_orders = test_get_orderbook_keys<B, Q>(&pair.bids);

        vector::append(&mut ask_orders, bid_orders);

        ask_orders
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
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_register_pair(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ): u64 acquires NPair, Pair, QuoteConfig {
        // block::initialize_for_test(sea_admin, 1);
        let sea_admin = test_prepare_account_env();
        test_init_coins_and_accounts(&sea_admin, user1, user2, user3);
        // 1. register quote
        register_quote<T_USD>(&sea_admin, 10000);
        // 2. 
        register_pair<T_BTC, T_USD>(&sea_admin, 500, 1000000000, 10);

        let pair = borrow_global_mut<Pair<T_BTC, T_USD>>(@sea_spot);
        pair.price_ratio
    }

    #[test]
    fun test_register_quote() {
        let sea_admin = test_prepare_account_env();
        let (bc, fc, mc) = coin::initialize<T_USD>(&sea_admin,
            string::utf8(b"USD"),
            string::utf8(b"USD"),
            6,
            false);
        coin::destroy_burn_cap(bc);
        coin::destroy_freeze_cap(fc);
        coin::register<T_USD>(&sea_admin);
        // 1. register quote
        register_quote<T_USD>(&sea_admin, 10);
        coin::destroy_mint_cap(mc);
    }

    #[test]
    #[expected_failure(abort_code = 0x102)] // E_QUOTE_CONFIG_EXISTS
    fun test_register_quote_dup() {
        let sea_admin = test_prepare_account_env();
        let (bc, fc, mc) = coin::initialize<T_USD>(&sea_admin,
            string::utf8(b"USD"),
            string::utf8(b"USD"),
            6,
            false);
        coin::destroy_burn_cap(bc);
        coin::destroy_freeze_cap(fc);
        coin::destroy_mint_cap(mc);
        coin::register<T_USD>(&sea_admin);
        // 1. register quote
        register_quote<T_USD>(&sea_admin, 10);
        // 2. 
        register_quote<T_USD>(&sea_admin, 10);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_place_limit_order_buy(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        let price_ratio = test_register_pair(user1, user2, user3);

        place_limit_order<T_BTC, T_USD>(user1, BUY, 150130000000, 1500000, false, false);
        // check the user's asset OK
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT, 0);
        let vol = calc_quote_vol_for_buy(150130000000, 1500000, price_ratio);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT-vol, 1);

        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD>();
        assert!(vector::length(&asks) == 0, 0);
        assert!(vector::length(&bids) == 1, 1);
        let step0 = vector::borrow(&bids, 0);
        assert!(step0.price == 150130000000, 2);
        assert!(step0.qty == 1500000, 2);
        
        place_limit_order<T_BTC, T_USD>(user2, SELL, 150130000000, 1000000, false, false);
        // check maker user1 assets
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT + 1000000, 2);
        let vol1 = calc_quote_vol_for_buy(150130000000, 1000000, price_ratio);
        let fee1 = vol1 * 500/1000000;
        let fee1_maker = fee1 * 50/1000;
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT-vol + fee1_maker, 3); // , vol-vol1);

        // check taker user2 assets
        test_check_account_asset<T_BTC>(address_of(user2), T_BTC_AMT-1000000, 4);
        test_check_account_asset<T_USD>(address_of(user2), T_USD_AMT+ vol1-fee1, 5);

        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD>();
        assert!(vector::length(&asks) == 0, 0);
        assert!(vector::length(&bids) == 1, 1);
        let step0 = vector::borrow(&bids, 0);
        assert!(step0.price == 150130000000, 2);
        assert!(step0.qty == 500000, 2);

        place_limit_order<T_BTC, T_USD>(user3, SELL, 150130000000, 500000, false, false);
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT + 1500000, 6);
        let vol2 = calc_quote_vol_for_buy(150130000000, 500000, price_ratio);
        let fee2 = vol2 * 500/1000000;
        let fee2_maker = fee2 * 50/1000;
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT-vol+fee1_maker+fee2_maker, 7); // , vol-vol1-vol2);
        // check taker user3 assets
        test_check_account_asset<T_BTC>(address_of(user3), T_BTC_AMT-500000, 8);
        // debug::print(&vol2);
        // debug::print(&fee2_maker);
        test_check_account_asset<T_USD>(address_of(user3), T_USD_AMT+vol2-fee2, 9);

        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD>();
        assert!(vector::length(&asks) == 0, 0);
        // debug::print(&vector::length(&asks));
        assert!(vector::length(&bids) == 0, 1);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_place_limit_order_sell(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        let price_ratio = test_register_pair(user1, user2, user3);

        place_limit_order<T_BTC, T_USD>(user1, SELL, 150130000000, 1500000, false, false);
        // check the user's asset OK
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000, 1000);
        // let vol = calc_quote_vol_for_buy(150130000000, 1500000, price_ratio);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT, 1001);
        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD>();
        assert!(vector::length(&asks) == 1, 0);
        let ask0 = vector::borrow(&asks, 0);
        assert!(ask0.price == 150130000000, 1);
        assert!(ask0.qty == 1500000, 1);
        assert!(vector::length(&bids) == 0, 1);
        
        place_limit_order<T_BTC, T_USD>(user2, BUY, 150130000000, 1000000, false, false);
        // check maker user1 assets
        let fee1 = 1000000 * 500/1000000;
        let fee1_maker = fee1 * 50/1000;
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000+fee1_maker, 1002);
        let vol1 = calc_quote_vol_for_buy(150130000000, 1000000, price_ratio);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT+ vol1, 1003);

        // check taker user2 assets
        test_check_account_asset<T_BTC>(address_of(user2), T_BTC_AMT + 1000000-fee1, 1004);
        test_check_account_asset<T_USD>(address_of(user2), T_USD_AMT-vol1, 1005);
        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD>();
        assert!(vector::length(&asks) == 1, 0);
        assert!(vector::length(&bids) == 0, 1);

        place_limit_order<T_BTC, T_USD>(user3, BUY, 150230000000, 500000, false, false);
        let fee2 = 500000 * 500/1000000;
        let fee2_maker = fee2 * 50/1000;
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000+fee1_maker+fee2_maker, 1006);
        let vol2 = calc_quote_vol_for_buy(150130000000, 500000, price_ratio);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT+ vol1+vol2, 1007);
        // check taker user3 assets
        test_check_account_asset<T_BTC>(address_of(user3), T_BTC_AMT+500000-fee2, 1008);
        test_check_account_asset<T_USD>(address_of(user3), T_USD_AMT-vol2, 1009);

        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD>();
        assert!(vector::length(&asks) == 0, 0);
        assert!(vector::length(&bids) == 0, 1);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_place_limit_order_sell_2(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        // use std::debug;

        let price_ratio = test_register_pair(user1, user2, user3);

        place_limit_order<T_BTC, T_USD>(user1, SELL, 150130000000, 1500000, false, false);
        // check the user's asset OK
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000, 2000);
        // let vol = calc_quote_vol_for_buy(150130000000, 1500000, price_ratio);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT, 2001);
        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD>();
        assert!(vector::length(&asks) == 1, 0);
        let ask0 = vector::borrow(&asks, 0);
        assert!(ask0.price == 150130000000, 1);
        assert!(ask0.qty == 1500000, 1);
        assert!(vector::length(&bids) == 0, 1);
        
        place_limit_order<T_BTC, T_USD>(user2, BUY, 150130000000, 1000000, false, false);
        // check maker user1 assets
        let fee1 = 1000000 * 500/1000000;
        let fee1_maker = fee1 * 50/1000;
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000+ fee1_maker, 2002);
        let vol1 = calc_quote_vol_for_buy(150130000000, 1000000, price_ratio);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT+ vol1, 2003);

        // check taker user2 assets
        test_check_account_asset<T_BTC>(address_of(user2), T_BTC_AMT+ 1000000-fee1, 2004);
        test_check_account_asset<T_USD>(address_of(user2), T_USD_AMT-vol1, 2005);
        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD>();
        assert!(vector::length(&asks) == 1, 0);
        assert!(vector::length(&bids) == 0, 1);

        place_limit_order<T_BTC, T_USD>(user3, BUY, 150230000000, 500010, false, false);
        let fee2 = 500000 * 500/1000000;
        let fee2_maker = fee2 * 50/1000;
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000+ fee1_maker+fee2_maker, 2006);
        let vol2 = calc_quote_vol_for_buy(150130000000, 500000, price_ratio);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT+ vol1+vol2, 2007);
        // check taker user3 assets
        // debug::print(&coin::balance<T_BTC>(address_of(user3)));
        // debug::print(&(T_BTC_AMT+500000-fee2));
        test_check_account_asset<T_BTC>(address_of(user3), T_BTC_AMT+500000-fee2, 2008);

        let vol = calc_quote_vol_for_buy(150230000000, 10, price_ratio);
        // debug::print(&coin::balance<T_USD>(address_of(user3)));
        // debug::print(&(T_USD_AMT-vol2-vol));
        // debug::print(&(T_USD_AMT));
        // debug::print(&(vol2));
        // debug::print(&(vol));
        test_check_account_asset<T_USD>(address_of(user3), T_USD_AMT-vol2-vol, 2009);

        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD>();
        assert!(vector::length(&asks) == 0, 0);
        assert!(vector::length(&bids) == 1, 1);
        let bid0 = vector::borrow(&bids, 0);
        assert!(bid0.price == 150230000000, 9);
        assert!(bid0.qty == 10, 9);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_place_limit_order_fill_3(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        let price_ratio = test_register_pair(user1, user2, user3);
        _ = price_ratio;

        place_limit_order<T_BTC, T_USD>(user1, SELL, 15013000000000, 1500000, false, false);
        place_limit_order<T_BTC, T_USD>(user2, SELL, 15012000000000, 1000000, false, false);
        place_limit_order<T_BTC, T_USD>(user3, BUY,  15023000000000, 2400000, false, false);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_place_postonly_order(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, QuoteConfig {
        test_register_pair(user1, user2, user3);

        place_postonly_order<T_BTC, T_USD>(user1, BUY, 150130000000, 1500000);
        place_postonly_order<T_BTC, T_USD>(user1, SELL, 150130000000, 1500000);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    #[expected_failure(abort_code = 0x10C)] // E_PRICE_TOO_LOW
    fun test_e2e_place_postonly_order_failed(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, QuoteConfig {
        test_register_pair(user1, user2, user3);

        place_postonly_order<T_BTC, T_USD>(user1, BUY, 150130000000, 1500000);
        place_postonly_order<T_BTC, T_USD>(user1, SELL, 150100000000, 1500000);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    #[expected_failure(abort_code = 0x10D)] // E_PRICE_TOO_HIGH
    fun test_e2e_place_postonly_order_failed2(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, QuoteConfig {
        test_register_pair(user1, user2, user3);

        place_postonly_order<T_BTC, T_USD>(user1, SELL, 150130000000, 1500000);
        place_postonly_order<T_BTC, T_USD>(user1, BUY, 150200000000, 1500000);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_place_cancel_order(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, QuoteConfig {
        test_register_pair(user1, user2, user3);

        let order_key = place_postonly_order_return_id<T_BTC, T_USD>(user1, SELL, 15013000000000, 1500000);
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000, 10);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT, 11);
        
        cancel_order<T_BTC, T_USD>(user1, SELL, order_key);
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT, 20);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT, 21);

        let order_key = place_postonly_order_return_id<T_BTC, T_USD>(user1, BUY, 15013000000000, 1500000);
        let usd = calc_quote_vol_for_buy(15013000000000, 1500000, 1000000000);
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT, 30);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT-usd, 31);
        
        cancel_order<T_BTC, T_USD>(user1, BUY, order_key);
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT, 40);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT, 41);
    }
    
    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_place_cancel_buy_partial_filled_order(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        test_register_pair(user1, user2, user3);

        let maker_order_key = place_postonly_order_return_id<T_BTC, T_USD>(user1, BUY, 15013000000000, 1500000);

        // partial filled
        place_limit_order<T_BTC, T_USD>(user2, SELL, 15013000000000, 1000000, false, false);

        let (usd, total_fee) = calc_quote_vol(SELL, 1000000, 15013000000000, 1000000000, 500);
        cancel_order<T_BTC, T_USD>(user1, BUY, maker_order_key);
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT+1000000, 40);
        // taker got USD, trade fee is USD, the maker got some trade fee
        //
        let (maker_shares, _) = fee::get_maker_fee_shares(total_fee, false);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT-usd+maker_shares, 41);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_place_cancel_sell_partial_filled_order(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        test_register_pair(user1, user2, user3);

        let maker_order_key = place_postonly_order_return_id<T_BTC, T_USD>(user1, SELL, 15013000000000, 1500000);

        // partial filled
        place_limit_order<T_BTC, T_USD>(user2, BUY, 15013000000000, 1000000, false, false);

        let (usd, total_fee) = calc_quote_vol(BUY, 1000000, 15013000000000, 1000000000, 500);

        cancel_order<T_BTC, T_USD>(user1, SELL, maker_order_key);

        let (maker_shares, _) = fee::get_maker_fee_shares(total_fee, false);
        // debug::print(&total_fee);
        // debug::print(&maker_shares);
        // let btc_bal = coin::balance<T_BTC>(address_of(user1));
        // debug::print(&btc_bal);
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1000000+maker_shares, 40);
        // taker got USD, trade fee is USD, the maker got some trade fee
        //
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT+usd, 41);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_place_grid_order(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        // use std::debug;

        test_register_pair(user1, user2, user3);

        place_grid_order<T_BTC, T_USD>(user1, 15013000000000, 15015000000000,
            5, 5, 1500000, 1000000000, true, true);

        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000*5, 50);
        let usd = calc_quote_vol_for_buy(15013000000000, 1500000, 1000000000) +
                calc_quote_vol_for_buy(15012000000000, 1500000, 1000000000) +
                calc_quote_vol_for_buy(15011000000000, 1500000, 1000000000) +
                calc_quote_vol_for_buy(15010000000000, 1500000, 1000000000) +
                calc_quote_vol_for_buy(15009000000000, 1500000, 1000000000);

        // debug::print(&coin::balance<T_USD>(address_of(user1)));
        // debug::print(&(T_USD_AMT-usd));
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT-usd, 51);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_flip_grid_order_sell_side(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        // use std::debug;
        test_register_pair(user1, user2, user3);

        place_grid_order<T_BTC, T_USD>(user1, 15013000000000, 15015000000000,
            2, 2, 1500000, 1000000000, true, true);
        // sell orders
        // 150160000000 1500000 s1
        // 150150000000 1500000 s0
        // buy orders
        // 150130000000 1500000 s2
        // 150120000000 1500000 s3
        let flip_order_key = test_get_order_key(15014000000000, 1, 4);
        let (_, qty, grid_id, base_frozen, quote_frozen) = get_order_info<T_BTC, T_USD>(user1, BUY, flip_order_key);
        assert!(qty == 0, 1);
        assert!(grid_id == 0, 1);
        assert!(base_frozen == 0, 1);
        assert!(quote_frozen == 0, 1);
        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD>();
        assert!(vector::length(&asks) == 2, 2);
        assert!(vector::length(&bids) == 2, 3);
        
        // s0 is filled, s1 is partial filled
        place_limit_order<T_BTC, T_USD>(user2, BUY, 15017000000000, 1500000+1000000, false, false);

        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD>();
        assert!(vector::length(&asks) == 1, 4);
        assert!(vector::length(&bids) == 3, 5);
        // 150160000000 1500000 s1
        // buy orders
        // 150140000000 1500000 s0
        // 150130000000 1500000
        // 150120000000 1500000
        let (usd1, fee1) = calc_quote_vol(BUY, 1500000, 15015000000000, 1000000000, 500);
        let (usd2, fee2) = calc_quote_vol(BUY, 1000000, 15016000000000, 1000000000, 500);

        test_check_account_asset<T_BTC>(address_of(user2), T_BTC_AMT+2500000-fee1-fee2, 60);
        test_check_account_asset<T_USD>(address_of(user2), T_USD_AMT-usd1-usd2, 61);

        let vol = utils::calc_quote_qty(1500000, 15015000000000, 1000000000);
        let (flip_price, flip_qty, _) = grid::calc_grid_order_price_qty(
            BUY,
            true,
            15015000000000,
            1000000000,
            vol,
            1000000000,
            10,
        );
        // debug::print(&flip_price);
        // debug::print(&flip_qty);
        assert!(flip_price == 15014000000000, 169);

        let usd_frozen = 150140000000*flip_qty/10000000 + 150130000000*1500000/10000000 +
            150120000000*1500000/10000000 + 150160000000*1000000/10000000;
        let usd_got = 150150000000*1500000/10000000 + 150160000000*1000000/10000000;

        let (maker_fee, _) = fee::get_maker_fee_shares(fee1+fee2, true);
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-3000000+maker_fee, 70);
        // let btc_bal = coin::balance<T_USD>(address_of(user1));
        // debug::print(&btc_bal);
        // debug::print(&(T_USD_AMT-usd_frozen+usd_got));
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT-usd_frozen+usd_got, 71);

        // the order_key flipped
        let flip_order_key = test_get_order_key(15014000000000, 1, 4);
        let (_, qty, grid_id, base_frozen, quote_frozen) = get_order_info<T_BTC, T_USD>(user1, BUY, flip_order_key);
        assert!(grid_id == ((1<<40)+1), 110);
        assert!(base_frozen == 0, 111);
        assert!(qty == 1500090, 113); // 1500090
        assert!(quote_frozen == (((15014000000000 as u128)*(qty as u128)/(1000000000 as u128)) as u64), 112);
        // TODO flip twice
        // TODO cancel grid orders
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_flip_grid_order_buy_side(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        test_register_pair(user1, user2, user3);

        place_grid_order<T_BTC, T_USD>(user1, 15013000000000, 15015000000000,
            2, 2, 1500000, 1000000000, true, true);
        // sell orders
        // 150160000000 1500000
        // 150150000000 1500000
        // buy orders
        // 150130000000 1500000
        // 150120000000 1500000
        
        // partial filled
        place_limit_order<T_BTC, T_USD>(user2, SELL, 15012000000000, 1500000+1000000, false, false);
        let (_, asks, bids) = test_get_pair_price_steps<T_BTC, T_USD>();

        assert!(vector::length(&asks) == 3, 4);
        assert!(vector::length(&bids) == 1, 5);

        let (usd1, fee1) = calc_quote_vol(SELL, 1500000, 15013000000000, 1000000000, 500);
        let (usd2, fee2) = calc_quote_vol(SELL, 1000000, 15012000000000, 1000000000, 500);
        let (usd3, _) = calc_quote_vol(SELL, 1500000, 15012000000000, 1000000000, 500);

        test_check_account_asset<T_BTC>(address_of(user2), T_BTC_AMT-2500000, 60);
        test_check_account_asset<T_USD>(address_of(user2), T_USD_AMT+usd1+usd2-fee1-fee2, 61);

        // sell orders
        // 150160000000 1500000
        // 150150000000 1500000
        // 150140000000 1500000
        // buy orders
        // 150120000000 1500000
        
        let (maker_fee, _) = fee::get_maker_fee_shares(fee1+fee2, true);

        // 1500000 * 2 + 1500000 - 1500000
        test_check_account_asset<T_BTC>(address_of(user1), T_BTC_AMT-1500000*2, 70);
        test_check_account_asset<T_USD>(address_of(user1), T_USD_AMT-usd1-usd3+maker_fee, 71);

        // the order_key flipped
        let flip_order_key = test_get_order_key(15014000000000, 1, 4);
        let (_, qty, grid_id, base_frozen, quote_frozen) = get_order_info<T_BTC, T_USD>(user1, SELL, flip_order_key);
        assert!(grid_id == ((1<<40)+1), 110);
        assert!(base_frozen == 1500000, 111);
        assert!(qty == 1500000, 113);
        assert!(quote_frozen == 0, 112);

        // TODO flip twice
        // TODO cancel grid orders
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_e2e_get_open_orders(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        test_register_pair(user1, user2, user3);

        place_limit_order<T_BTC, T_USD>(user1, BUY, 150120000000, 1000000, false, false);
        place_limit_order<T_BTC, T_USD>(user1, BUY, 150020000000, 1100000, false, false);
        place_limit_order<T_BTC, T_USD>(user1, BUY, 149020000000, 1200000, false, false);
        place_limit_order<T_BTC, T_USD>(user1, BUY, 148020000000, 1300000, false, false);
        place_limit_order<T_BTC, T_USD>(user1, BUY, 147020000000, 1400000, false, false);

        place_limit_order<T_BTC, T_USD>(user1, SELL, 151120000000, 1000000, false, false);
        place_limit_order<T_BTC, T_USD>(user1, SELL, 152020000000, 1100000, false, false);
        place_limit_order<T_BTC, T_USD>(user1, SELL, 152200000000, 1200000, false, false);
        place_limit_order<T_BTC, T_USD>(user1, SELL, 153020000000, 1300000, false, false);
        place_limit_order<T_BTC, T_USD>(user1, SELL, 156020000000, 1400000, false, false);

        let (bid_orders, ask_orders) = get_account_pair_orders<T_BTC, T_USD>(user1);

        assert!(vector::length(&bid_orders) == 5, 1);
        let bid0 = vector::borrow(&bid_orders, 0);
        assert!(bid0.qty == 1000000, 11);
        let bid1 = vector::borrow(&bid_orders, 1);
        assert!(bid1.qty == 1100000, 12);
        let bid2 = vector::borrow(&bid_orders, 2);
        assert!(bid2.qty == 1200000, 12);
        let bid3 = vector::borrow(&bid_orders, 3);
        assert!(bid3.qty == 1300000, 12);
        let bid4 = vector::borrow(&bid_orders, 4);
        assert!(bid4.qty == 1400000, 12);

        assert!(vector::length(&ask_orders) == 5, 2);
        let ask0 = vector::borrow(&ask_orders, 0);
        assert!(ask0.qty == 1000000, 11);
        let ask1 = vector::borrow(&ask_orders, 1);
        assert!(ask1.qty == 1100000, 12);
        let ask2 = vector::borrow(&ask_orders, 2);
        assert!(ask2.qty == 1200000, 12);
        let ask3 = vector::borrow(&ask_orders, 3);
        assert!(ask3.qty == 1300000, 12);
        let ask4 = vector::borrow(&ask_orders, 4);
        assert!(ask4.qty == 1400000, 12);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    #[expected_failure(abort_code = 0x113)]
    fun test_place_invalid_order_qty(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        test_register_pair(user1, user2, user3);
        place_limit_order<T_BTC, T_USD>(user1, BUY, 150120000000, 1000005, false, false);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    #[expected_failure(abort_code = 0x107)]
    fun test_place_invalid_order_price(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        test_register_pair(user1, user2, user3);
        place_limit_order<T_BTC, T_USD>(user1, BUY, 1501210000000, 1000000, false, false);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    #[expected_failure(abort_code = 0x114)]
    fun test_place_invalid_order_min_notional(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        test_register_pair(user1, user2, user3);
        place_limit_order<T_BTC, T_USD>(user1, BUY, 150120000000, 10, false, false);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_place_the_order_buy(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, QuoteConfig {
        test_register_pair(user1, user2, user3);
        let account_id = escrow::get_or_register_account_id(address_of(user1));
        let quote_qty = utils::calc_quote_qty(10000, 150120000000, 1000000000);
        let order = new_order<T_BTC, T_USD>(user1, BUY, 10000, quote_qty,account_id, 0);
        place_the_order<T_BTC, T_USD>(BUY, 150120000000, order);

        test_check_orders<T_BTC, T_USD>(vector[
        ], vector[
            // 5000000000 / 15012 = 333066.8798294698
            PriceStep{qty: 10000, price: 150120000000, orders: 1},
            // 15012000000000 * 10 / 11 = 13647272727272.727
            // 5000000000 / 13647 = 302773
            // PriceStep{qty: 366380, price: 13647000000000, orders: 1},
        ]);

        let order2 = new_order<T_BTC, T_USD>(user1, BUY, 34000, quote_qty,account_id, 0);
        place_the_order<T_BTC, T_USD>(BUY, 150120000000, order2);
        test_check_orders<T_BTC, T_USD>(vector[
        ], vector[
            // 5000000000 / 15012 = 333066.8798294698
            PriceStep{qty: 44000, price: 150120000000, orders: 2},
            // 15012000000000 * 10 / 11 = 13647272727272.727
            // 5000000000 / 13647 = 302773
            // PriceStep{qty: 366380, price: 13647000000000, orders: 1},
        ]);

    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_place_the_order_sell(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, QuoteConfig {
        test_register_pair(user1, user2, user3);
        let account_id = escrow::get_or_register_account_id(address_of(user1));
        let quote_qty = utils::calc_quote_qty(10000, 150120000000, 1000000000);
        let order = new_order<T_BTC, T_USD>(user1, SELL, 10000, quote_qty,account_id, 0);
        place_the_order<T_BTC, T_USD>(SELL, 150120000000, order);

        test_check_orders<T_BTC, T_USD>(vector[
            PriceStep{qty: 10000, price: 150120000000, orders: 1},
        ], vector[
            // 5000000000 / 15012 = 333066.8798294698
            // 15012000000000 * 10 / 11 = 13647272727272.727
            // 5000000000 / 13647 = 302773
            // PriceStep{qty: 366380, price: 13647000000000, orders: 1},
        ]);

        let order2 = new_order<T_BTC, T_USD>(user1, SELL, 20000, quote_qty,account_id, 0);
        place_the_order<T_BTC, T_USD>(SELL, 150120000000, order2);
        test_check_orders<T_BTC, T_USD>(vector[
            PriceStep{qty: 30000, price: 150120000000, orders: 2},
        ], vector[
            // 5000000000 / 15012 = 333066.8798294698
            // 15012000000000 * 10 / 11 = 13647272727272.727
            // 5000000000 / 13647 = 302773
            // PriceStep{qty: 366380, price: 13647000000000, orders: 1},
        ]);

        let order3 = new_order<T_BTC, T_USD>(user1, SELL, 30000, quote_qty,account_id, 0);
        place_the_order<T_BTC, T_USD>(SELL, 150120000000, order3);
        test_check_orders<T_BTC, T_USD>(vector[
            PriceStep{qty: 60000, price: 150120000000, orders: 3},
        ], vector[
            // 5000000000 / 15012 = 333066.8798294698
            // 15012000000000 * 10 / 11 = 13647272727272.727
            // 5000000000 / 13647 = 302773
            // PriceStep{qty: 366380, price: 13647000000000, orders: 1},
        ]);

        let order4 = new_order<T_BTC, T_USD>(user1, SELL, 25000, quote_qty,account_id, 0);
        place_the_order<T_BTC, T_USD>(SELL, 150120000000, order4);
        test_check_orders<T_BTC, T_USD>(vector[
            PriceStep{qty: 85000, price: 150120000000, orders: 4},
        ], vector[
            // 5000000000 / 15012 = 333066.8798294698
            // 15012000000000 * 10 / 11 = 13647272727272.727
            // 5000000000 / 13647 = 302773
            // PriceStep{qty: 366380, price: 13647000000000, orders: 1},
        ]);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    #[expected_failure]
    fun test_place_the_order_buy_failed(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, QuoteConfig {
        test_register_pair(user1, user2, user3);
        let account_id = escrow::get_or_register_account_id(address_of(user1));
        let quote_qty = utils::calc_quote_qty(10000, 150120000000, 1000000000);
        let order = new_order<T_BTC, T_USD>(user2, SELL, 10000, quote_qty,account_id, 0);
        place_the_order<T_BTC, T_USD>(SELL, 150120000000, order);


        let order = new_order<T_BTC, T_USD>(user1, BUY, 10000, quote_qty,account_id, 0);
        place_the_order<T_BTC, T_USD>(BUY, 150130000000, order);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    #[expected_failure]
    fun test_place_the_order_sell_failed(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) acquires NPair, Pair, QuoteConfig {
        test_register_pair(user1, user2, user3);
        let account_id = escrow::get_or_register_account_id(address_of(user1));
        let quote_qty = utils::calc_quote_qty(10000, 150120000000, 1000000000);
        let order = new_order<T_BTC, T_USD>(user1, BUY, 10000, quote_qty,account_id, 0);
        place_the_order<T_BTC, T_USD>(BUY, 150130000000, order);

        let order = new_order<T_BTC, T_USD>(user2, SELL, 10000, quote_qty,account_id, 0);
        place_the_order<T_BTC, T_USD>(SELL, 150120000000, order);
    }

    ////////////////////////////////////////////////////////////////////////////
    // geometric grid orders
    ////////////////////////////////////////////////////////////////////////////

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_buy_grid_geometric(
        user1: &signer,
        user2: &signer,
        user3: &signer
        ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        test_register_pair(user1, user2, user3);

        // place grid
        place_grid_order<T_BTC, T_USD>(user1, 15013000000000, 0,
            3, 0, 1500000, 10000, false, true);
        test_check_orders<T_BTC, T_USD>(vector[], vector[
            PriceStep{qty: 1500000, price: 15013000000000, orders: 1},
            // 15013000000000 * 10 / 11 = 
            PriceStep{qty: 1500000, price: 13648000000000, orders: 1},
            // 13648000000000 * 10 / 11 = 
            PriceStep{qty: 1500000, price: 12407000000000, orders: 1},
        ]);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_buy_grid_geometric_quote(
        user1: &signer,
        user2: &signer,
        user3: &signer
        ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        test_register_pair(user1, user2, user3);

        // place grid
        place_grid_order<T_BTC, T_USD>(user1, 15013000000000, 0,
            3, 0, 5000000000, 10000, false, false);
        test_check_orders<T_BTC, T_USD>(vector[], vector[
            // 5000000000 / 15013000000000 = 333044
            PriceStep{qty: 333040, price: 15013000000000, orders: 1},
            // 5000000000 / 13648000000000 = 366354
            PriceStep{qty: 366350, price: 13648000000000, orders: 1},
            // 5000000000 / 12407000000000 = 402998
            PriceStep{qty: 402990, price: 12407000000000, orders: 1},
        ]);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_sell_grid_geometric(
        user1: &signer,
        user2: &signer,
        user3: &signer
        ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        test_register_pair(user1, user2, user3);

        // place grid
        place_grid_order<T_BTC, T_USD>(user1, 0, 15013000000000,
            0, 3, 1500000, 10000, false, true);
        test_check_orders<T_BTC, T_USD>(vector[
            PriceStep{qty: 1500000, price: 15013000000000, orders: 1},
            // 15013000000000 * 11 / 10 = 16514300000000
            PriceStep{qty: 1500000, price: 16514000000000, orders: 1},
            // 16514000000000 * 10 / 11 = 18165400000000
            PriceStep{qty: 1500000, price: 18165000000000, orders: 1},
        ], vector[]);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_sell_grid_geometric_quote(
        user1: &signer,
        user2: &signer,
        user3: &signer
        ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        test_register_pair(user1, user2, user3);

        // place grid
        place_grid_order<T_BTC, T_USD>(user1, 0, 15013000000000,
            0, 3, 5000000000, 10000, false, false);
        test_check_orders<T_BTC, T_USD>(vector[
            PriceStep{qty: 333040, price: 15013000000000, orders: 1},
            // 15013000000000 * 11 / 10 = 16514300000000
            // 5000000000 / 16514 = 302773
            PriceStep{qty: 302770, price: 16514000000000, orders: 1},
            // 16514000000000 * 10 / 11 = 18165400000000
            // 5000000000 / 18165 = 275254
            PriceStep{qty: 275250, price: 18165000000000, orders: 1},
        ], vector[]);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_buy_sell_grid_geometric(
        user1: &signer,
        user2: &signer,
        user3: &signer
        ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        test_register_pair(user1, user2, user3);

        // place grid
        place_grid_order<T_BTC, T_USD>(user1, 15012000000000, 15013000000000,
            2, 3, 5000000000, 10000, false, false);
        test_check_orders<T_BTC, T_USD>(vector[
            PriceStep{qty: 333040, price: 15013000000000, orders: 1},
            // 15013000000000 * 11 / 10 = 16514300000000
            // 5000000000 / 16514 = 302773
            PriceStep{qty: 302770, price: 16514000000000, orders: 1},
            // 16514000000000 * 10 / 11 = 18165400000000
            // 5000000000 / 18165 = 275254
            PriceStep{qty: 275250, price: 18165000000000, orders: 1},
        ], vector[
            // 5000000000 / 15012 = 333066.8798294698
            PriceStep{qty: 333060, price: 15012000000000, orders: 1},
            // 15012000000000 * 10 / 11 = 13647272727272.727
            // 5000000000 / 13647 = 302773
            PriceStep{qty: 366380, price: 13647000000000, orders: 1},
        ]);
    }

    // geometric, quote equal grids
    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_flip_grid_geometric_quote_equal(
        user1: &signer,
        user2: &signer,
        user3: &signer
        ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        // use std::debug;
        test_register_pair(user1, user2, user3);

        // place grid
        place_grid_order<T_BTC, T_USD>(user1, 15012000000000, 15013000000000,
            2, 3, 5000000000, 10000, false, false);

        let btc_pair = borrow_global<Pair<T_BTC, T_USD>>(@sea_spot);
        let btc_price_ratio = btc_pair.price_ratio;
        let btc_fee_ratio = btc_pair.fee_ratio;

        // user2 buy first sell order
        let addr2 = address_of(user2);
        let account2_id = escrow::get_or_register_account_id(addr2);
        let (_, _, order_buy1) = match_order<T_BTC, T_USD>(
            addr2,
            BUY,
            15015000000000,
            new_order<T_BTC, T_USD>(user2, BUY, 400000,
            utils::calc_quote_qty(400000, 15015000000000, btc_price_ratio),
            account2_id,
            0));

        let fee_deno = fee::get_fee_denominate();
        let fee1 = 333040 * (btc_fee_ratio) / fee_deno;
        let net_buy1 = 333040 - fee1;
        let quote_usd1 = 333040 * 15013;
        assert!(coin::value(&order_buy1.base_frozen) == net_buy1, 2900);
        destroy_order(addr2, order_buy1);

        assert!(coin::balance<T_BTC>(addr2) == T_BTC_AMT+net_buy1, 2901);
        assert!(coin::balance<T_USD>(addr2) == T_USD_AMT-quote_usd1, 2902);

        // the sell1 order has flipped to bid
        test_check_orders<T_BTC, T_USD>(vector[
            // 15013000000000 * 11 / 10 = 16514300000000
            // 5000000000 / 16514 = 302773
            PriceStep{qty: 302770, price: 16514000000000, orders: 1},
            // 16514000000000 * 10 / 11 = 18165400000000
            // 5000000000 / 18165 = 275254
            PriceStep{qty: 275250, price: 18165000000000, orders: 1},
        ], vector[
            // 5000000000 / 15012 = 333066.8798294698
            PriceStep{qty: 333060, price: 15012000000000, orders: 1},
            // 15013000000000 * 10 / 11 = 13648181818181
            // 333040 * 15013000000000 / 13648000000000 = 366348.88042203983
            PriceStep{qty: 366340, price: 13648000000000, orders: 1},
            // 15012000000000 * 10 / 11 = 13647272727272.727
            // 5000000000 / 13647 = 302773
            PriceStep{qty: 366380, price: 13647000000000, orders: 1},
        ]);

        // user3 buy left two sell orders
        let addr3 = address_of(user3);
        let account3_id = escrow::get_or_register_account_id(addr3);
        let (_, _, order_buy2) = match_order<T_BTC, T_USD>(
            addr3,
            BUY,
            18265000000000,
            new_order<T_BTC, T_USD>(user3, BUY, 800000,
            utils::calc_quote_qty(800000, 18265000000000, btc_price_ratio),
            account3_id,
            0));

        // 302770 * 16514000000000 
        // 275250 * 18165000000000
        let fee21 = 302770 * (btc_fee_ratio) / fee_deno;
        let fee22 = 275250 * (btc_fee_ratio) / fee_deno;
        let net_buy2 = 302770 - fee21 + 275250 - fee22;
        let quote_usd2 = 302770 * 16514 + 275250 * 18165;
        assert!(coin::value(&order_buy2.base_frozen) == net_buy2, 3900);
        destroy_order(addr3, order_buy2);

        assert!(coin::balance<T_BTC>(addr3) == T_BTC_AMT+net_buy2, 3901);
        assert!(coin::balance<T_USD>(addr3) == T_USD_AMT-quote_usd2, 3902);

        // all grid buy orders
        test_check_orders<T_BTC, T_USD>(vector[
            // 15013000000000 * 11 / 10 = 16514300000000
            // 5000000000 / 16514 = 302773
        ], vector[
            // 18165000000000 * 10 / 11 = 16513636363636.363
            // 18165000000000 * 275250 / 16514000000000 = 302768.3329296355
            PriceStep{qty: 302760, price: 16514000000000, orders: 1},
            // 
            // 16514000000000 * 10 / 11 = 15012727272727.273
            // 16514000000000 * 302770 / 15013000000000 = 333040.949843469
            PriceStep{qty: 333040, price: 15013000000000, orders: 1},

            // 5000000000 / 15012 = 333066.8798294698
            PriceStep{qty: 333060, price: 15012000000000, orders: 1},
            // 15013000000000 * 10 / 11 = 13648181818181
            // 333040 * 15013000000000 / 13648000000000 = 366348.88042203983
            PriceStep{qty: 366340, price: 13648000000000, orders: 1},
            // 15012000000000 * 10 / 11 = 13647272727272.727
            // 5000000000 / 13647 = 302773
            PriceStep{qty: 366380, price: 13647000000000, orders: 1},
        ]);

        // user2 fill buy orders
        let (_, _, order_sell1) = match_order<T_BTC, T_USD>(
            addr2,
            SELL,
            15013000000000,
            new_order<T_BTC, T_USD>(user2, SELL, 400000,
            0,
            account2_id,
            0));
        destroy_order(addr2, order_sell1);
        let user2_btc_balance = coin::balance<T_BTC>(addr2);
        assert!(user2_btc_balance == T_BTC_AMT+net_buy1-400000, 4901);
        let sell1_quote = (302760 * 16514 + (400000-302760) * 15013);
        let sell1_fee = sell1_quote * (btc_fee_ratio) / fee_deno; // usd
        let net_sell1 = sell1_quote - sell1_fee;
        let user2_usd_balance = coin::balance<T_USD>(addr2);
        assert!(user2_usd_balance == T_USD_AMT-quote_usd1+net_sell1, 4902);
        // all grid buy orders
        test_check_orders<T_BTC, T_USD>(vector[
            // 15013000000000 * 11 / 10 = 16514300000000
            // 5000000000 / 16514 = 302773
            // 16514000000000 * 11 * 10 = 1816540000000000
            //
            PriceStep{qty: 302760, price: 18165000000000, orders: 1},
        ], vector[
            // 18165000000000 * 10 / 11 = 16513636363636.363
            // 18165000000000 * 275250 / 16514000000000 = 302768.3329296355
            // 
            // 16514000000000 * 10 / 11 = 15012727272727.273
            // 16514000000000 * 302770 / 15013000000000 = 333040.949843469
            // 333040 - (400000 - 302760) = 235800
            PriceStep{qty: 235800, price: 15013000000000, orders: 1},

            // 5000000000 / 15012 = 333066.8798294698
            PriceStep{qty: 333060, price: 15012000000000, orders: 1},
            // 15013000000000 * 10 / 11 = 13648181818181
            // 333040 * 15013000000000 / 13648000000000 = 366348.88042203983
            PriceStep{qty: 366340, price: 13648000000000, orders: 1},
            // 15012000000000 * 10 / 11 = 13647272727272.727
            // 5000000000 / 13647 = 302773
            PriceStep{qty: 366380, price: 13647000000000, orders: 1},
        ]);

        // user3 fill buy orders
        let (_, _, order_sell2) = match_order<T_BTC, T_USD>(
            addr3,
            SELL,
            15012000000000,
            new_order<T_BTC, T_USD>(user3, SELL, 400000,
            0,
            account3_id,
            0));
        destroy_order(addr3, order_sell2);
        let user3_btc_balance = coin::balance<T_BTC>(addr3);
        assert!(user3_btc_balance == T_BTC_AMT+net_buy2-400000, 5901);
        let sell2_quote = (235800 * 15013 + (400000 - 235800) * 15012);
        let sell2_fee = sell2_quote * (btc_fee_ratio) / fee_deno;
        let net_sell2 = sell2_quote - sell2_fee;
        let user3_usd_balance = coin::balance<T_USD>(addr3);
        assert!(user3_usd_balance == T_USD_AMT-quote_usd2+net_sell2, 5902);
        test_check_orders<T_BTC, T_USD>(vector[
                    // 18165000000000 * 10 / 11 = 16513636363636.363
                    // 18165000000000 * 275250 / 16514000000000 = 302768.3329296355
                    // 
                    // 16514000000000 * 10 / 11 = 15012727272727.273
                    // 16514000000000 * 302770 / 15013000000000 = 333040.949843469
                    // 333040 - (400000 - 302760) = 235800
                    // 15013000000000 * 11 * 10 = 1651430000000000
                    PriceStep{qty: 333040, price: 16514000000000, orders: 1},
                    // 15013000000000 * 11 / 10 = 16514300000000
                    // 5000000000 / 16514 = 302773
                    // 16514000000000 * 11 * 10 = 1816540000000000
                    //
                    PriceStep{qty: 302760, price: 18165000000000, orders: 1},
                ], vector[
                    // 5000000000 / 15012 = 333066.8798294698
                    // 333060 - (400000 - 235800)
                    PriceStep{qty: 168860, price: 15012000000000, orders: 1},
                    // 15013000000000 * 10 / 11 = 13648181818181
                    // 333040 * 15013000000000 / 13648000000000 = 366348.88042203983
                    PriceStep{qty: 366340, price: 13648000000000, orders: 1},
                    // 15012000000000 * 10 / 11 = 13647272727272.727
                    // 5000000000 / 13647 = 302773
                    PriceStep{qty: 366380, price: 13647000000000, orders: 1},
                ]);

        // user1 cancel all grid orders
        let grid_orders = test_get_pair_order_key<T_BTC, T_USD>();
        assert!(vector::length(&grid_orders) == 5, 5);
        cancel_batch_orders<T_BTC, T_USD>(user1, vector<u8>[SELL, SELL, BUY, BUY, BUY], grid_orders);

        // user1 balance
        // pair fee
        // let quote_vault = &btc_pair.quote_vault;
        // let base_vault = &btc_pair.base_vault;
        let (usd_grid_fee1, usd_plat_fee1) = fee::get_maker_fee_shares(sell1_fee, true);
        let (usd_grid_fee2, usd_plat_fee2) = fee::get_maker_fee_shares(sell2_fee, true);
        let (btc_grid_fee1, btc_plat_fee1) = fee::get_maker_fee_shares(fee1, true);
        let (btc_grid_fee2, btc_plat_fee2) = fee::get_maker_fee_shares(fee21 + fee22, true);

        usd_grid_fee1;
        usd_grid_fee2;
        btc_grid_fee1;
        btc_grid_fee2;
        let usd_plat_fee = usd_plat_fee1 + usd_plat_fee2 + 1; // maker fee truncated 1
        let btc_plat_fee = btc_plat_fee1 + btc_plat_fee2 + 1; // maker fee truncated 1
        let user1_btc_balance = coin::balance<T_BTC>(address_of(user1));
        assert!(user1_btc_balance == T_BTC_AMT * 3 - user3_btc_balance - user2_btc_balance - btc_plat_fee, 7);
        let user1_usd_balance = coin::balance<T_USD>(address_of(user1));
        assert!(user1_usd_balance == T_USD_AMT * 3 - user3_usd_balance - user2_usd_balance - usd_plat_fee, 8);
        // assert!(coin::value<T_USD>(quote_vault) == usd_plat_fee, 8);
        // let btc_fee = fee1 + fee21 + fee22;
    }

    // geometric, quote equal grids
    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_flip_grid_geometric_base_equal(
        user1: &signer,
        user2: &signer,
        user3: &signer
        ) acquires NPair, Pair, AccountGrids, QuoteConfig {
        // use std::debug;
        test_register_pair(user1, user2, user3);

        // place grid
        // base equal
        place_grid_order<T_BTC, T_USD>(user1, 15012000000000, 15013000000000,
            2, 3, 350000, 10000, false, true);

        let btc_pair = borrow_global<Pair<T_BTC, T_USD>>(@sea_spot);
        let btc_price_ratio = btc_pair.price_ratio;
        let btc_fee_ratio = btc_pair.fee_ratio;

        // user2 buy first sell order
        let addr2 = address_of(user2);
        let account2_id = escrow::get_or_register_account_id(addr2);
        let (_, _, order_buy1) = match_order<T_BTC, T_USD>(
            addr2,
            BUY,
            15015000000000,
            new_order<T_BTC, T_USD>(user2, BUY, 400000,
            utils::calc_quote_qty(400000, 15015000000000, btc_price_ratio),
            account2_id,
            0));

        let fee_deno = fee::get_fee_denominate();
        let fee1 = 350000 * (btc_fee_ratio) / fee_deno;
        let net_buy1 = 350000 - fee1;
        let quote_usd1 = 350000 * 15013;
        assert!(coin::value(&order_buy1.base_frozen) == net_buy1, 2900);
        destroy_order(addr2, order_buy1);

        assert!(coin::balance<T_BTC>(addr2) == T_BTC_AMT+net_buy1, 2901);
        assert!(coin::balance<T_USD>(addr2) == T_USD_AMT-quote_usd1, 2902);

        // the sell1 order has flipped to bid
        test_check_orders<T_BTC, T_USD>(vector[
            // 15013000000000 * 11 / 10 = 16514300000000
            // 5000000000 / 16514 = 302773
            PriceStep{qty: 350000, price: 16514000000000, orders: 1},
            // 16514000000000 * 10 / 11 = 18165400000000
            // 5000000000 / 18165 = 275254
            PriceStep{qty: 350000, price: 18165000000000, orders: 1},
        ], vector[
            // 5000000000 / 15012 = 333066.8798294698
            PriceStep{qty: 350000, price: 15012000000000, orders: 1},
            // 15013000000000 * 10 / 11 = 13648181818181
            // 350000 * 15013000000000 / 13648000000000 = 385005.12895662367
            PriceStep{qty: 385000, price: 13648000000000, orders: 1},
            // 15012000000000 * 10 / 11 = 13647272727272.727
            // 5000000000 / 13647 = 302773
            PriceStep{qty: 350000, price: 13647000000000, orders: 1},
        ]);

        // user3 buy left two sell orders
        let addr3 = address_of(user3);
        let account3_id = escrow::get_or_register_account_id(addr3);
        let (_, _, order_buy2) = match_order<T_BTC, T_USD>(
            addr3,
            BUY,
            18265000000000,
            new_order<T_BTC, T_USD>(user3, BUY, 800000,
            utils::calc_quote_qty(800000, 18265000000000, btc_price_ratio),
            account3_id,
            0));

        // 350000 * 16514000000000 
        // 350000 * 18165000000000
        let fee21 = 350000 * (btc_fee_ratio) / fee_deno;
        let fee22 = 350000 * (btc_fee_ratio) / fee_deno;
        let net_buy2 = 350000 - fee21 + 350000 - fee22;
        let quote_usd2 = 350000 * 16514 + 350000 * 18165;
        assert!(coin::value(&order_buy2.base_frozen) == net_buy2, 3900);
        destroy_order(addr3, order_buy2);

        assert!(coin::balance<T_BTC>(addr3) == T_BTC_AMT+net_buy2, 3901);
        assert!(coin::balance<T_USD>(addr3) == T_USD_AMT-quote_usd2, 3902);

        // all grid buy orders
        test_check_orders<T_BTC, T_USD>(vector[
            // 15013000000000 * 11 / 10 = 16514300000000
            // 5000000000 / 16514 = 302773
        ], vector[
            // 18165000000000 * 10 / 11 = 16513636363636.363
            // 18165000000000 * 350000 / 16514000000000 = 384991.52234467724
            PriceStep{qty: 384990, price: 16514000000000, orders: 1},
            // 
            // 16514000000000 * 10 / 11 = 15012727272727.273
            // 16514000000000 * 350000 / 15013000000000 = 384993.00606141344
            PriceStep{qty: 384990, price: 15013000000000, orders: 1},

            // 5000000000 / 15012 = 333066.8798294698
            PriceStep{qty: 350000, price: 15012000000000, orders: 1},
            // 15013000000000 * 10 / 11 = 13648181818181
            // 333040 * 15013000000000 / 13648000000000 = 366348.88042203983
            PriceStep{qty: 385000, price: 13648000000000, orders: 1},
            // 15012000000000 * 10 / 11 = 13647272727272.727
            // 5000000000 / 13647 = 302773
            PriceStep{qty: 350000, price: 13647000000000, orders: 1},
        ]);

        // user2 fill buy orders
        let (_, _, order_sell1) = match_order<T_BTC, T_USD>(
            addr2,
            SELL,
            15013000000000,
            new_order<T_BTC, T_USD>(user2, SELL, 400000,
            0,
            account2_id,
            0));
        destroy_order(addr2, order_sell1);
        let user2_btc_balance = coin::balance<T_BTC>(addr2);
        assert!(user2_btc_balance == T_BTC_AMT+net_buy1-400000, 4901);
        let sell1_quote = (384990 * 16514 + (400000-384990) * 15013);
        let sell1_fee = sell1_quote * (btc_fee_ratio) / fee_deno; // usd
        let net_sell1 = sell1_quote - sell1_fee;
        let user2_usd_balance = coin::balance<T_USD>(addr2);
        assert!(user2_usd_balance == T_USD_AMT-quote_usd1+net_sell1, 4902);
        // all grid buy orders
        test_check_orders<T_BTC, T_USD>(vector[
            // 15013000000000 * 11 / 10 = 16514300000000
            // 5000000000 / 16514 = 302773
            // 16514000000000 * 11 * 10 = 1816540000000000
            //
            PriceStep{qty: 384990, price: 18165000000000, orders: 1},
        ], vector[
            // 18165000000000 * 10 / 11 = 16513636363636.363
            // 18165000000000 * 275250 / 16514000000000 = 302768.3329296355
            // 
            // 16514000000000 * 10 / 11 = 15012727272727.273
            // 16514000000000 * 302770 / 15013000000000 = 333040.949843469
            // 384990 - (400000-384990) = 369980
            PriceStep{qty: 369980, price: 15013000000000, orders: 1},

            // 5000000000 / 15012 = 333066.8798294698
            PriceStep{qty: 350000, price: 15012000000000, orders: 1},
            // 15013000000000 * 10 / 11 = 13648181818181
            // 333040 * 15013000000000 / 13648000000000 = 366348.88042203983
            PriceStep{qty: 385000, price: 13648000000000, orders: 1},
            // 15012000000000 * 10 / 11 = 13647272727272.727
            // 5000000000 / 13647 = 302773
            PriceStep{qty: 350000, price: 13647000000000, orders: 1},
        ]);

        // user3 fill buy orders
        let (_, _, order_sell2) = match_order<T_BTC, T_USD>(
            addr3,
            SELL,
            15012000000000,
            new_order<T_BTC, T_USD>(user3, SELL, 400000,
            0,
            account3_id,
            0));
        destroy_order(addr3, order_sell2);
        let user3_btc_balance = coin::balance<T_BTC>(addr3);
        assert!(user3_btc_balance == T_BTC_AMT+net_buy2-400000, 5901);
        let sell2_quote = (369980 * 15013 + (400000 - 369980) * 15012);
        let sell2_fee = sell2_quote * (btc_fee_ratio) / fee_deno;
        let net_sell2 = sell2_quote - sell2_fee;
        let user3_usd_balance = coin::balance<T_USD>(addr3);
        assert!(user3_usd_balance == T_USD_AMT-quote_usd2+net_sell2, 5902);
        test_check_orders<T_BTC, T_USD>(vector[
                    // 18165000000000 * 10 / 11 = 16513636363636.363
                    // 18165000000000 * 275250 / 16514000000000 = 302768.3329296355
                    // 
                    // 16514000000000 * 10 / 11 = 15012727272727.273
                    // 16514000000000 * 302770 / 15013000000000 = 333040.949843469
                    // 333040 - (400000 - 302760) = 235800
                    // 15013000000000 * 11 * 10 = 1651430000000000
                    PriceStep{qty: 384990, price: 16514000000000, orders: 1},
                    // 15013000000000 * 11 / 10 = 16514300000000
                    // 5000000000 / 16514 = 302773
                    // 16514000000000 * 11 * 10 = 1816540000000000
                    //
                    PriceStep{qty: 384990, price: 18165000000000, orders: 1},
                ], vector[
                    // 5000000000 / 15012 = 333066.8798294698
                    // 350000 - (400000 - 369980)
                    PriceStep{qty: 319980, price: 15012000000000, orders: 1},
                    // 15013000000000 * 10 / 11 = 13648181818181
                    // 333040 * 15013000000000 / 13648000000000 = 366348.88042203983
                    PriceStep{qty: 385000, price: 13648000000000, orders: 1},
                    // 15012000000000 * 10 / 11 = 13647272727272.727
                    // 5000000000 / 13647 = 302773
                    PriceStep{qty: 350000, price: 13647000000000, orders: 1},
                ]);

        // user1 cancel all grid orders
        let grid_orders = test_get_pair_order_key<T_BTC, T_USD>();
        assert!(vector::length(&grid_orders) == 5, 5);
        cancel_batch_orders<T_BTC, T_USD>(user1, vector<u8>[SELL, SELL, BUY, BUY, BUY], grid_orders);

        // user1 balance
        // pair fee
        // let quote_vault = &btc_pair.quote_vault;
        // let base_vault = &btc_pair.base_vault;
        let (usd_grid_fee1, usd_plat_fee1) = fee::get_maker_fee_shares(sell1_fee, true);
        let (usd_grid_fee2, usd_plat_fee2) = fee::get_maker_fee_shares(sell2_fee, true);
        let (btc_grid_fee1, btc_plat_fee1) = fee::get_maker_fee_shares(fee1, true);
        let (btc_grid_fee2, btc_plat_fee2) = fee::get_maker_fee_shares(fee21 + fee22, true);

        usd_grid_fee1;
        usd_grid_fee2;
        btc_grid_fee1;
        btc_grid_fee2;
        let usd_plat_fee = usd_plat_fee1 + usd_plat_fee2 + 1; // maker fee truncated 1
        let btc_plat_fee = btc_plat_fee1 + btc_plat_fee2; // maker fee truncated 1
        let user1_btc_balance = coin::balance<T_BTC>(address_of(user1));
        assert!(user1_btc_balance == T_BTC_AMT * 3 - user3_btc_balance - user2_btc_balance - btc_plat_fee, 7);
        let user1_usd_balance = coin::balance<T_USD>(address_of(user1));
        assert!(user1_usd_balance == T_USD_AMT * 3 - user3_usd_balance - user2_usd_balance - usd_plat_fee, 8);
        // assert!(coin::value<T_USD>(quote_vault) == usd_plat_fee, 8);
        // let btc_fee = fee1 + fee21 + fee22;
    }

}
