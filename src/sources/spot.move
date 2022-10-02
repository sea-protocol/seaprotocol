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
    // use std::vector;
    use aptos_framework::coin::{Self, Coin};
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
        from_escrow: bool,
        to_escrow: bool,
        post_only: bool,
        ioc: bool,
        fok: bool,
        is_market: bool,
    }

    /// OrderEntity order entity. price, pair_id is on OrderBook
    struct OrderEntity has copy, drop, store {
        // base coin amount
        // we use qty to indicate base amount, vol to indicate quote amount
        qty: u64,
        // the grid id or 0 if is not grid
        grid_id: u64,
        // user address
        // user: address,
        // escrow account id
        account_id: u64
    }

    struct Pair<phantom BaseType, phantom QuoteType, phantom FeeRatio> has key {
        n_order: u64,
        fee_ratio: u64,
        base_id: u64,
        quote_id: u64,
        pair_id: u64,
        lot_size: u64,
        // multiply: bool,         // price_ratio is multiply or divided
        price_ratio: u64,       // price_coefficient*pow(10, base_precision-quote_precision)
        price_coefficient: u64, // price coefficient, from 10^1 to 10^12
        last_price: u64,        // last trade price
        last_timestamp: u64,    // last trade timestamp
        base: Coin<BaseType>,
        quote: Coin<QuoteType>,
        asks: RBTree<OrderEntity>,
        bids: RBTree<OrderEntity>,
        base_vault: Coin<BaseType>,
        quote_vault: Coin<QuoteType>,
    }

    struct QuoteConfig<phantom QuoteType> has key {
        quote_id: u64,
        tick_size: u64,
        min_notional: u64,
        quote: Coin<QuoteType>,
    }

    // pairs count
    struct NPair has key {
        n_pair: u64
    }

    // struct SpotMarket<phantom BaseType, phantom QuoteType, phantom FeeRatio> has key {
    //     fee: u64,
    //     n_pair: u64,
    //     n_quote: u64,
    //     quotes: Table<u64, QuoteConfig<QuoteType>>,
    //     pairs: Table<u64, Pair<BaseType, QuoteType, FeeRatio>>
    // }
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

    // Public functions ====================================================

    public entry fun initialize(sea_admin: &signer) {
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);
        // let signer_cap = spot_account::retrieve_signer_cap(sea_admin);
        // move_to(sea_admin, SpotAccountCapability { signer_cap });
        move_to(sea_admin, NPair {
            n_pair: 0,
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
        quote: Coin<QuoteType>,
        tick_size: u64,
        min_notional: u64,
    ) {
        assert!(address_of(account) == @sea, E_NO_AUTH);
        assert!(!exists<QuoteConfig<QuoteType>>(@sea), E_QUOTE_CONFIG_EXISTS);
        let quote_id = escrow::get_or_register_coin_id<QuoteType>(true);

        move_to(account, QuoteConfig{
            quote_id: quote_id,
            tick_size: tick_size,
            min_notional: min_notional,
            quote: quote,
        })
        // todo event
    }

    // register pair, quote should be one of the egliable quote
    public fun register_pair<BaseType, QuoteType, FeeRatio>(
        _owner: &signer,
        base: Coin<BaseType>,
        quote: Coin<QuoteType>,
        price_coefficient: u64
    ) acquires NPair {
        utils::assert_is_coin<BaseType>();
        utils::assert_is_coin<QuoteType>();
        assert!(escrow::is_quote_coin<QuoteType>(), E_NOT_QUOTE_COIN);
        assert!(!exists<Pair<BaseType, QuoteType, FeeRatio>>(@sea_spot), E_PAIR_EXISTS);

        let base_id = escrow::get_or_register_coin_id<BaseType>(false);
        let quote_id = escrow::get_or_register_coin_id<QuoteType>(true);
        // let spot_cap = borrow_global<SpotAccountCapability>(@sea);
        // let pair_account = account::create_signer_with_capability(&spot_cap.signer_cap);
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
            fee_ratio: fee_ratio,
            base_id: base_id,
            quote_id: quote_id,
            pair_id: pair_id,
            lot_size: 0,
            price_ratio: ratio,       // price_coefficient*pow(10, base_precision-quote_precision)
            price_coefficient: price_coefficient, // price coefficient, from 10^1 to 10^12
            last_price: 0,        // last trade price
            last_timestamp: 0,    // last trade timestamp
            base: base,
            quote: quote,
            asks: rbtree::empty<OrderEntity>(true),  // less price is in left
            bids: rbtree::empty<OrderEntity>(false),
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
        from_escrow: bool,
    ) acquires Pair {
        let account_addr = address_of(account);
        let pair = borrow_global_mut<Pair<BaseType, QuoteType, FeeRatio>>(@sea_spot);

        if (side == SELL)  {
            let bids = &mut pair.bids;
            let bid0 = get_best_price(bids);
            assert!(has_enough_asset<BaseType>(account_addr, qty, from_escrow), E_BASE_NOT_ENOUGH);
            assert!(price >= bid0, E_PRICE_TOO_LOW);
        } else {
            let asks = &mut pair.asks;
            let ask0 = get_best_price(asks);
            assert!(price <= ask0, E_PRICE_TOO_HIGH);
            let vol = calc_quote_vol_for_buy(qty, price, pair.price_ratio);
            assert!(has_enough_asset<QuoteType>(account_addr, vol, from_escrow), E_BASE_NOT_ENOUGH);
        };
        let order = &mut OrderEntity{
            qty: qty,
            grid_id: 0,
            account_id: escrow::get_or_register_account_id(address_of(account)), // lazy set. if the order is to be insert into orderbook, we will set it
        };
        place_order(account, side, price, pair, order)
    }

    public entry fun place_limit_order<BaseType, QuoteType, FeeRatio>(
        account: &signer,
        side: u8,
        price: u64,
        qty: u64,
        ioc: bool,
        fok: bool,
        from_escrow: bool,
        to_escrow: bool,
    ) acquires Pair {
        if (fok) {
            // TODO check this order can be filled
        };
        let taker_addr = address_of(account);
        let opts = &PlaceOrderOpts {
            addr: taker_addr,
            side: side,
            from_escrow: from_escrow,
            to_escrow: to_escrow,
            post_only: false,
            ioc: ioc,
            fok: fok,
            is_market: false,
        };
        let order = &mut OrderEntity{
            qty: qty,
            grid_id: 0,
            account_id: 0,
        };
        // we don't check whether the account has enough asset just abort
        match<BaseType, QuoteType, FeeRatio>(account, price, opts, order);
    }

    public entry fun place_market_order<BaseType, QuoteType, FeeRatio>(
        account: &signer,
        side: u8,
        qty: u64,
        from_escrow: bool,
        to_escrow: bool,
    ) acquires Pair {
        let taker_addr = address_of(account);
        let opts = &PlaceOrderOpts {
            addr: taker_addr,
            side: side,
            from_escrow: from_escrow,
            to_escrow: to_escrow,
            post_only: false,
            ioc: false,
            fok: false,
            is_market: true,
        };
        let order = &mut OrderEntity{
            qty: qty,
            grid_id: 0,
            account_id: 0,
        };
        // we don't check whether the account has enough asset just abort
        match<BaseType, QuoteType, FeeRatio>(account, 0, opts, order);
    }

    // public entry fun place_grid_order<BaseType, QuoteType, FeeRatio>(
    //     account: &signer,
    //     price: u64,
    //     per_qty: u64,
    //     from_escrow: bool,
    // ) acquires Pair {

    // }

    // Private functions ====================================================

    fun get_best_price<V>(
        tree: &RBTree<V>
    ): u64 {
        let leftmmost = rbtree::get_leftmost_key(tree);
        ((leftmmost >> 64) as u64)
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

    /// match buy order, taker is buyer, maker is seller
    /// 
    fun match<BaseType, QuoteType, FeeRatio>(
        taker: &signer,
        price: u64,
        opts: &PlaceOrderOpts,
        order: &mut OrderEntity
    ) acquires Pair {
        let taker_addr = address_of(taker);
        let pair = borrow_global_mut<Pair<BaseType, QuoteType, FeeRatio>>(@sea_spot);

        if (opts.fok) {
            // TODO judge can fill taker order totally
        };

        // let taker_account_id = if (to_escrow) {
        //     escrow::get_or_register_account_id(taker_addr)
        // } else 0;
        let completed = match_internal(
            taker,
            price,
            pair,
            order,
            opts,
        );

        if ((!completed) && (!opts.is_market)) {
            // TODO make sure order qty >= lot_size
            // place order to orderbook
            let taker_account_id = escrow::get_or_register_account_id(taker_addr);
            order.account_id = taker_account_id;
            place_order(taker, opts.side, price, pair, order);
        }
    }

    fun place_order<BaseType, QuoteType, FeeRatio>(
        account: &signer,
        side: u8,
        price: u64,
        pair: &mut Pair<BaseType, QuoteType, FeeRatio>,
        order: &mut OrderEntity
    ) {
        // frozen
        if (side == SELL) {
            escrow::deposit<BaseType>(account, order.qty, true);
        } else {
            let vol = calc_quote_vol_for_buy(order.qty, price, pair.price_ratio);
            escrow::deposit<QuoteType>(account, vol, true);
        };

        let order_id = generate_order_id(pair);
        let orderbook = if (side == BUY) &mut pair.asks else &mut pair.bids;
        let key: u128 = generate_key(price, order_id);
        rbtree::rb_insert<OrderEntity>(orderbook, key, *order);
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
        taker_order: &mut OrderEntity,
        taker_opts: &PlaceOrderOpts,
    ): bool {
        // does the taker order is total filled
        let completed = false;
        let fee_ratio = pair.fee_ratio;
        let price_ratio = pair.price_ratio;
        let taker_side = taker_opts.side;
        let orderbook = if (taker_side == BUY) &mut pair.asks else &mut pair.bids;

        while (!rbtree::is_empty(orderbook)) {
            let (pos, key, order) = rbtree::borrow_leftmost_keyval_mut(orderbook);
            let (maker_price, _) = price::get_price_order_id(key);
            if ((!taker_opts.is_market) && 
                    ((taker_side == BUY && price >= maker_price) ||
                     (taker_side == SELL && price <=  maker_price))
             ) {
                break
            };

            let match_qty = taker_order.qty;
            let remove_order = false;
            if (order.qty <= taker_order.qty) {
                match_qty = order.qty;
                // remove this order from orderbook
                remove_order = true;
            } else {
                completed = true;
                // if the last maker order cannot match anymore
            };
            taker_order.qty = taker_order.qty - match_qty;
            order.qty = order.qty - match_qty;
            let (quote_vol, fee_amt) = calc_quote_vol(taker_side, match_qty, maker_price, price_ratio, fee_ratio);
            let (fee_plat, fee_maker) = fee::get_maker_fee_shares(fee_amt, fee_ratio);

            swap_internal<BaseType, QuoteType, FeeRatio>(
                &mut pair.base_vault,
                &mut pair.quote_vault,
                taker,
                taker_opts,
                order.account_id,
                match_qty,
                quote_vol,
                fee_plat,
                fee_maker);
            if (remove_order) {
                let (_, pop_order) = rbtree::rb_remove_by_pos(orderbook, pos);
                let OrderEntity {qty: _, grid_id: _, account_id: _} = pop_order;
            };
            if (completed) {
                break
            }
        };

        completed
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
        maker_id: u64,
        base_qty: u64,
        quote_vol: u64,
        fee_plat_amt: u64,
        fee_maker_amt: u64,
    ) {
        let maker_addr = escrow::get_account_addr_by_id(maker_id);
        let taker_addr = taker_opts.addr;

        if (taker_opts.side == BUY) {
            // taker got base coin
            let to_taker = escrow::dec_escrow_coin<BaseType>(maker_addr, base_qty-fee_maker_amt, true);
            if (fee_plat_amt > 0) {
                // platform vault
                let to_plat = coin::extract(&mut to_taker, fee_plat_amt);
                coin::merge(pair_base_vault, to_plat);
            };
            if (taker_opts.to_escrow) {
                escrow::incr_escrow_coin<BaseType>(taker_addr, to_taker, false);
            } else {
                // send to taker directly
                coin::deposit(taker_addr, to_taker);
            };
            // maker got quote coin
            let quote = if (taker_opts.from_escrow) {
                    escrow::dec_escrow_coin<QuoteType>(taker_addr, quote_vol, false)
                } else {
                    coin::withdraw<QuoteType>(taker, quote_vol)
                };
            escrow::incr_escrow_coin<QuoteType>(maker_addr, quote, false);
        } else {
            // taker got quote coin
            let to_taker = escrow::dec_escrow_coin<QuoteType>(maker_addr, quote_vol-fee_maker_amt, true);
            if (fee_plat_amt > 0) {
                // todo platform vault
                let to_plat = coin::extract(&mut to_taker, fee_plat_amt);
                coin::merge(pair_quote_vault, to_plat);
            };
            if (taker_opts.to_escrow) {
                escrow::incr_escrow_coin<QuoteType>(taker_addr, to_taker, false);
            } else {
                // send to taker directly
                coin::deposit(taker_addr, to_taker);
            };
            // maker got base coin
            let base = if (taker_opts.from_escrow) {
                    escrow::dec_escrow_coin<BaseType>(taker_addr, base_qty, false)
                } else {
                    coin::withdraw<BaseType>(taker, base_qty)
                };
            escrow::incr_escrow_coin<BaseType>(maker_addr, base, false);
        }
    }

    fun swap_coin(
        _step: &mut OrderEntity,
        ) {

    }
}
