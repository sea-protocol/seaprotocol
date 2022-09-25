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
    use std::signer::{Self, address_of};
    // use std::vector;
    use aptos_framework::coin::{Self, Coin};
    // use aptos_std::table::{Self, Table};
    use aptos_framework::account::{Self, SignerCapability};
    use sea::rbtree::{Self, RBTree};
    use sea::price;
    use sea::utils;
    use sea::fee;
    use sea::math;
    use sea::spot_account;

    // Structs ====================================================

    /// OrderEntity order entity. price, pair_id is on OrderBook
    struct OrderEntity has store {
        // base coin amount
        // we use qty to indicate base amount, vol to indicate quote amount
        qty: u64,
        // the grid id or 0 if is not grid
        grid: u64,
        // user address
        // user: address,
        // escrow account id
        account_id: u64
    }

    struct Pair<phantom BaseType, phantom QuoteType, phantom FeeRatio> has key {
        fee: u64,
        // pair_id: u64,
        // quote_id: u64,
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
    }

    struct QuoteConfig<phantom QuoteType> has key {
        quote: Coin<QuoteType>,
        tick_size: u64,
        min_notional: u64,
    }

    // struct SpotMarket<phantom BaseType, phantom QuoteType, phantom FeeRatio> has key {
    //     fee: u64,
    //     n_pair: u64,
    //     n_quote: u64,
    //     quotes: Table<u64, QuoteConfig<QuoteType>>,
    //     pairs: Table<u64, Pair<BaseType, QuoteType, FeeRatio>>
    // }

    /// Stores resource account signer capability under Liquidswap account.
    struct SpotAccountCapability has key { signer_cap: SignerCapability }

    // Constants ====================================================
    const BUY: u8 = 1;
    const SELL: u8 = 2;
    const MAX_U64: u128 = 0xffffffffffffffff;

    const E_PAIR_NOT_EXIST:      u64 = 1;
    const E_NO_AUTH:             u64 = 2;
    const E_QUOTE_CONFIG_EXISTS: u64 = 3;
    const E_NO_SPOT_MARKET:      u64 = 4;
    const E_VOL_EXCEED_MAX_U64:  u64 = 5;
    const E_VOL_EXCEED_MAX_U128: u64 = 6;
    const E_PAIR_EXISTS:         u64 = 7;
    const E_PAIR_PRICE_INVALID:  u64 = 8;

    // Public functions ====================================================

    public entry fun initialize(sea_admin: &signer) {
        assert!(signer::address_of(sea_admin) == @sea, E_NO_AUTH);
        let signer_cap = spot_account::retrieve_signer_cap(sea_admin);
        move_to(sea_admin, SpotAccountCapability { signer_cap });
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
    ) acquires SpotAccountCapability {
        assert!(address_of(account) == @sea, E_NO_AUTH);
        assert!(!exists<QuoteConfig<QuoteType>>(@sea_spot), E_QUOTE_CONFIG_EXISTS);
        let spot_cap = borrow_global<SpotAccountCapability>(@sea);
        let pair_account = account::create_signer_with_capability(&spot_cap.signer_cap);

        move_to(&pair_account, QuoteConfig{
            quote: quote,
            tick_size: tick_size,
            min_notional: min_notional
        })
        // todo event
    }

    // register pair, quote should be one of the egliable quote
    public fun register_pair<BaseType, QuoteType, FeeRatio>(
        account: &signer,
        base: Coin<BaseType>,
        quote: Coin<QuoteType>,
        price_coefficient: u64
    ) acquires SpotAccountCapability {
        utils::assert_is_coin<BaseType>();
        utils::assert_is_coin<QuoteType>();
        // todo assert QuoteType is one of QuoteConfig
        assert!(!exists<Pair<BaseType, QuoteType, FeeRatio>>(@sea_spot), E_PAIR_EXISTS);

        let spot_cap = borrow_global<SpotAccountCapability>(@sea);
        let pair_account = account::create_signer_with_capability(&spot_cap.signer_cap);
        let fee = fee::get_fee_ratio<FeeRatio>();
        let base_scale = math::pow_10(coin::decimals<BaseType>());
        let quote_scale = math::pow_10(coin::decimals<QuoteType>());
        
        // todo validate the pow_10(base_decimals-quote_decimals) < price_coefficient
        let (ratio, ok) = price::calc_price_ratio(
            base_scale,
            quote_scale,
            price_coefficient);
        assert!(ok, E_PAIR_PRICE_INVALID);
        let pair: Pair<BaseType, QuoteType, FeeRatio> = Pair{
            fee: fee,
            lot_size: 0,
            price_ratio: ratio,       // price_coefficient*pow(10, base_precision-quote_precision)
            price_coefficient: price_coefficient, // price coefficient, from 10^1 to 10^12
            last_price: 0,        // last trade price
            last_timestamp: 0,    // last trade timestamp
            base: base,
            quote: quote,
            asks: rbtree::empty<OrderEntity>(true),  // less price is in left
            bids: rbtree::empty<OrderEntity>(false),
        };
        move_to(&pair_account, pair);
        // todo events
    }

    /// match buy order, taker is buyer, maker is seller
    /// 
    public fun match(
        pair_id: u64,
        side: bool,
        orderbook: &mut RBTree<OrderEntity>,
        taker: &mut OrderEntity
    ) {

    }


    // Private functions ====================================================

    fun match_internal(
        taker_side: u8,
        base_id: u64,
        quote_id: u64,
        price: u64,
        price_ratio: u64,
        taker_order: &mut OrderEntity,
        orderbook: &mut RBTree<OrderEntity>,
    ): bool {
        // does the taker order is total filled
        let completed = false;

        while (!rbtree::is_empty(orderbook)) {
            let (pos, key, order) = rbtree::borrow_leftmost_keyval_mut(orderbook);
            let (maker_price, maker_order_id) = price::get_price_order_id(key);
            if ((taker_side == BUY && price >= maker_price) ||
                 (taker_side == SELL && price <=  maker_price)) {
                break;
            };

            let match_qty = taker_order.qty;
            if (order.qty <= taker_order.qty) {
                match_qty = order.qty;
                // remove this order from orderbook
                let (_, pop_order) = rbtree::rb_remove_by_pos(orderbook, pos);
                let OrderEntity {qty: _, grid: _, account_id: _} = pop_order;
            } else {
                completed = true;
                // if the last maker order cannot match anymore
            };
            taker_order.qty = taker_order.qty - match_qty;
            order.qty = order.qty - match_qty;
            let quote_vol = calc_quote_vol(match_qty, maker_price, price_ratio);

            swap_internal(
                taker_side,
                base_id,
                quote_id,
                taker_order.account_id,
                order.account_id,
                match_qty,
                quote_vol);
            if (completed) {
                break
            }
        };

        completed
    }

    // calculate quote volume: quote_vol = price * base_amt
    fun calc_quote_vol(
        qty: u64,
        price: u64,
        price_ratio: u64): u64 {
        let vol_orig: u128 = (qty as u128) * (price as u128);
        let vol: u128;

        vol = vol_orig / (price_ratio as u128);
        
        assert!(vol < MAX_U64, E_VOL_EXCEED_MAX_U64);
        (vol as u64)
    }

    // direct transfer coin to taker account
    // increase maker escrow
    fun swap_internal(
        taker_side: u8,
        base_id: u64,
        quote_id: u64,
        taker: u64,
        maker: u64,
        base_qty: u64,
        quote_vol: u64
    ) {
        if (taker_side == BUY) {
            // taker got base coin
            // maker got quote coin
        } else {
            // taker got quote coin
            // maker got base coin
        }
    }

    fun swap_coin(
        step: &mut OrderEntity,
        ) {

    }
}
