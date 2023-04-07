/// # Module-level documentation sections
///
/// * [Background](#Background)
/// * [Implementation](#Implementation)
/// * [Basic public functions](#Basic-public-functions)
/// * [Traversal](#Traversal)
///
/// # Background
///
/// aggregator for orderbook and AMM
/// 

module sea::aggregator {
    // use std::vector;
    use std::signer::address_of;
    use aptos_framework::coin::{Self, Coin};
    
    // use sea::amm;
    use sea::market;
    use sea::utils;
    // use sea::fee;
    use sea::router;

    const BUY:                u8   = 1;
    const SELL:               u8   = 2;
    const SIDE_ALL:           u8   = 3;

    const E_INSUFFICIENT_BASE_RESERVE:            u64 = 7008;
    const E_INSUFFICIENT_AMOUNT_OUT:              u64 = 7009;
    const E_NON_ZERO_COIN:                        u64 = 7010;
    const E_EMPTY_POOL:                           u64 = 7011;
    const E_INVALID_CLAC_QTY:                     u64 = 7012;

    // hybrid swap
    public entry fun hybrid_swap_entry<B, Q>(
        account: &signer,
        side: u8,
        amm_base_qty: u64,  // buy: this is amm base out; sell: is is amm base in
        amm_quote_vol: u64, // buy: this is quote in; sell: this is amm quote out
        ob_base_qty: u64,   // order book base qty
        ob_quote_vol: u64,  // order book quote qty
        min_out: u64,       // slippage min out quote volume
    ) {
        let addr = address_of(account);

        let (base_out, quote_out) = if (side == BUY) {
            hybrid_swap<B, Q>(
                addr,
                side,
                amm_base_qty,
                amm_quote_vol,
                coin::zero(),
                coin::withdraw(account, amm_quote_vol),
                market::new_order<B, Q>(account, side, ob_base_qty, ob_quote_vol, 0, 0),
            )
        } else {
            hybrid_swap<B, Q>(
                addr,
                side,
                amm_base_qty,
                amm_quote_vol,
                coin::withdraw(account, amm_base_qty),
                coin::zero(),
                market::new_order<B, Q>(account, side, ob_base_qty, ob_quote_vol, 0, 0),
            )
        };

        if (side == BUY) {
            // taker got base
            assert!(coin::value(&base_out) >= min_out, E_INSUFFICIENT_AMOUNT_OUT);
            utils::register_coin_if_not_exist<B>(account);
        } else {
            // taker got quote
            assert!(coin::value(&quote_out) >= min_out, E_INSUFFICIENT_AMOUNT_OUT);
            utils::register_coin_if_not_exist<Q>(account);
        };

        let addr = address_of(account);
        coin::deposit(addr, base_out);
        coin::deposit(addr, quote_out);
    }

    /*
    // hybrid swap
    public entry fun hybrid_swap_auto_entry<B, Q>(
        account: &signer,
        side: u8,
        qty: u64,     // if side is BUY, this is quote amount; if side is SELL, this is base amoount
        min_out: u64, // slippage min out quote volume
    ) {
        let steps = market::get_pair_side_steps<B, Q>(SIDE_ALL - side);
        let (base_reserve, quote_reserve, amm_fee_ratio) = amm::get_pool_reserve_fee_u128<B, Q>();
        let (
            amm_base_qty,
            amm_quote_qty,
            ob_base_qty,
            ob_quote_vol
        ) = calc_hybrid_partial<B, Q>(side, qty, base_reserve, quote_reserve, amm_fee_ratio, &steps);

        hybrid_swap_entry<B, Q>(account, side, amm_base_qty, amm_quote_qty, ob_base_qty, ob_quote_vol, min_out);
    }
    */

    ////////////////////////////////////////////////////////////////////////////
    /// PUBLIC FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////
    
    /*
    // calc how many amm_qty, ob_qty under price
    // amm_base_qty amm_quote_vol ob_base_qty ob_quote_vol
    public fun calc_hybrid_qty_under_price<B, Q>(
        _side: u8,
        _price: u64,
    ) {

    }

    // use orderbook match price better than amm, until end
    // side: the taker side
    // qty: qty the taker want to sell/buy
    // return: amm_base_qty amm_quote_vol ob_base_qty ob_quote_vol
    public fun calc_pair_hybrid_partial<B, Q>(
        side: u8,
        qty: u64,
    ): (u64, u64, u64, u64) {
        let steps = market::get_pair_side_steps<B, Q>(SIDE_ALL - side);
        let (base_reserve, quote_reserve, amm_fee_ratio) = amm::get_pool_reserve_fee_u128<B, Q>();

        calc_hybrid_partial<B, Q>(side, qty, base_reserve, quote_reserve, amm_fee_ratio, &steps)
    }

    // use orderbook match price better than amm, until end
    // side: the taker side
    // qty: qty the taker want to sell/buy
    // return: amm_base_qty amm_quote_vol ob_base_qty ob_quote_vol
    public fun calc_hybrid_partial<B, Q>(
        side: u8,
        qty: u64,
        base_reserve: u128,
        quote_reserve: u128,
        amm_fee_ratio: u128,
        steps: &vector<market::PriceStep>,
    ): (u64, u64, u64, u64) {
        // first, check the orderbook's price is 
        if (vector::length(steps) == 0) {
            // all use amm
            if (side == BUY) {
                return (router::get_amount_out<B, Q>(qty, false), qty, 0, 0)
            } else {
                return (qty, router::get_amount_out<B, Q>(qty, true), 0, 0)
            }
        };

        let (price_ratio, _, lot_size) = market::get_pair_info_u128<B, Q>();
        // assert!(base_reserve > 0 && quote_reserve > 0, E_EMPTY_POOL);
        let min_liq = (amm::get_min_liquidity() as u128);
        if (base_reserve == 0 || quote_reserve == 0 || base_reserve * quote_reserve < min_liq * min_liq) {
            // no amm
            return get_all_step_qty(steps, qty, (price_ratio as u64))
        };

        let amm_fee_deno = (fee::get_fee_denominate() as u128);
        let i = 0;
        let ob_base_qty = 0u128;
        let ob_quote_vol = 0u128;
        let amm_base_qty = 0u128;
        let amm_quote_vol = 0u128;
        let qty_u128 = (qty as u128); // total base qty
        let left_qty = (qty as u128);
        let amm_best_price: u128 = quote_reserve * price_ratio / base_reserve;
        let amm_worst_price = get_amm_price(
            side,
            qty_u128,
            price_ratio,
            base_reserve,
            quote_reserve,
            amm_fee_ratio,
            amm_fee_deno,
        );

        while(i < vector::length(steps)) {
            let step = vector::borrow(steps, i);
            let (step_price, step_qty) = market::get_price_step_u128(step);

            if (side == BUY) {
                if (step_price < amm_worst_price) {
                    if (step_qty + ob_base_qty >= qty_u128)
                        step_qty = (qty_u128 - ob_base_qty) / lot_size * lot_size;
                    if (step_price < amm_best_price) {
                        i = i + 1;
                        ob_base_qty = ob_base_qty + step_qty;
                        ob_quote_vol = ob_quote_vol + utils::calc_quote_qty_u128(step_qty, step_price, price_ratio);
                        continue
                    };
                };
            } else if (side == SELL) {
                if (step_price > amm_worst_price) {
                    if (step_qty + ob_base_qty >= qty_u128)
                        step_qty = (qty_u128 - ob_base_qty) / lot_size * lot_size;
                    if (step_price >= amm_best_price) {
                        i = i + 1;
                        ob_base_qty = ob_base_qty + step_qty;
                        ob_quote_vol = ob_quote_vol + utils::calc_quote_qty_u128(step_qty, step_price, price_ratio);
                        continue
                    };
                };
            };

            if (ob_base_qty == qty_u128) break;
            // if (step_qty == 0) break;
            // step_quote = utils::calc_quote_qty_u128(step_qty, (step_price as u128), price_ratio);

            let step_base_qty;
            let step_quote_vol;
            (amm_base_qty, amm_quote_vol, step_base_qty, step_quote_vol) = get_clob_qty(
                side,
                step_price,
                qty_u128,
                ob_base_qty,
                lot_size,
                step_qty,
                price_ratio,
                base_reserve,
                quote_reserve,
                amm_fee_ratio,
                amm_fee_deno,
            );
            ob_base_qty = ob_base_qty + step_base_qty;
            ob_quote_vol = ob_quote_vol + step_quote_vol;
            i = i + 1;
        };

        assert!(amm_base_qty + ob_base_qty == qty_u128, E_INVALID_CLAC_QTY);
        ((amm_base_qty as u64), (amm_quote_vol as u64), (ob_base_qty as u64), (ob_quote_vol as u64))
    }

    // side: swap side
    // qty: base qty
    public fun get_amm_price(
        side: u8,
        qty: u128,
        price_ratio: u128,
        base_reserve: u128,
        quote_reserve: u128,
        fee_ratio: u128,
        fee_deno: u128,
    ): u128 {
        let amount_in_with_fee = qty * (fee_deno - fee_ratio);
        if (side == SELL) {
            // quote_qty: get amount out
            // uint amountInWithFee = amountIn.mul(997);
            // uint numerator = amountInWithFee.mul(reserveOut);
            // uint denominator = reserveIn.mul(1000).add(amountInWithFee);
            // amountOut = numerator / denominator;
            let numerator = amount_in_with_fee * base_reserve;
            let denominator = quote_reserve * fee_deno + amount_in_with_fee;
            let base_out = numerator / denominator;
            (qty * price_ratio) / base_out
            // (base_out, qty, ((qty * price_ratio) / base_out))
        } else {
            // quote_qty: get amount in
            // buy qty base
            // first check if there has enough base
            assert!(base_reserve > qty, E_INSUFFICIENT_BASE_RESERVE);
            let numerator = amount_in_with_fee * quote_reserve;
            let denominator = base_reserve * fee_deno + amount_in_with_fee;
            let quote_out = numerator / denominator;
            (quote_out * price_ratio) / qty
            // (qty, quote_out, ((quote_out * price_ratio) / qty))
        }
    }

    fun get_all_step_qty(
        steps: &vector<market::PriceStep>,
        qty: u64,
        price_ratio: u64,
        ): (u64, u64, u64, u64) {
        let i = 0;
        let ob_qty = 0;
        let ob_vol = 0;

        while(i < vector::length(steps)) {
            let step = vector::borrow(steps, i);
            let (step_price, step_qty, _) = market::get_price_step(step);

            if (step_qty + ob_qty >= qty) {
                let left_qty = qty - ob_qty;
                ob_qty = qty;
                ob_vol = ob_vol + utils::calc_quote_qty(left_qty, step_price, price_ratio);
                break
            } else {
                ob_qty = ob_qty + step_qty;
                ob_vol = ob_vol + utils::calc_quote_qty(step_qty, step_price, price_ratio);
            }
        };

        (0, 0, ob_qty, ob_vol)
    }

    // compare whether amm price is better than orderbook price
    // price is orderbook maker price
    // return: step_base_qty, step_quote_vol, step_amm_price
    fun get_clob_qty(
        side: u8,
        price: u128,
        qty: u128,
        total_ob_qty: u128,
        lot_size: u128,
        step_base_qty: u128,    // order book step base qty
        price_ratio: u128,
        base_reserve: u128,
        quote_reserve: u128,
        amm_fee_ratio: u128,
        amm_fee_deno: u128,
    ): (u128, u128, u128, u128) {
        let amm_base_qty: u128;
        let amm_quote_vol: u128;
        let amm_step_price: u128;
        let step_quote_vol: u128;

        loop {
            amm_base_qty = (qty - total_ob_qty - step_base_qty);
            if (side == BUY) {
                // qty is base out, how many quote should pay for
                // get_amount_out
                // step_quote_vol = utils::calc_quote_qty_u128(step_base_qty, price, price_ratio);
                // amm_quote_vol = (qty - total_ob_qty - step_quote_vol);
                // let amount_in_with_fee = amm_quote_vol * (amm_fee_deno - amm_fee_ratio);
                // let numerator = amount_in_with_fee * base_reserve;
                // let denominator = quote_reserve * amm_fee_deno + amount_in_with_fee;
                let numerator = (quote_reserve as u128) * (amm_base_qty as u128) * (amm_fee_deno);
                let denominator = (base_reserve - amm_base_qty) * (amm_fee_deno - amm_fee_ratio);
                amm_quote_vol = numerator / denominator + 1;
                amm_step_price = ((amm_base_qty * price_ratio) / amm_quote_vol);

                step_quote_vol = utils::calc_quote_qty_u128(step_base_qty, (price as u128), price_ratio);
                // amm price is better, stop
                if (amm_step_price <= price) break;
            } else {
                // qty is base in
                // amm_base_qty = (qty - total_ob_qty - step_base_qty);
                let amount_in_with_fee = amm_base_qty * (amm_fee_deno - amm_fee_ratio);
                let numerator = amount_in_with_fee * quote_reserve;
                let denominator = base_reserve * amm_fee_deno + amount_in_with_fee;
                amm_quote_vol = numerator / denominator;
                amm_step_price = ((amm_quote_vol * price_ratio) / amm_base_qty);

                step_quote_vol = utils::calc_quote_qty_u128(step_base_qty, (price as u128), price_ratio);
                if (amm_step_price >= price) break;
            };

            step_base_qty = (step_base_qty / 2) / lot_size * lot_size;
            if (step_base_qty == 0) break;
        };

        (amm_base_qty, amm_quote_vol, step_base_qty, step_quote_vol)
    }
    */

    public fun hybrid_swap<B, Q>(
        addr: address,
        side: u8,
        amm_base_qty: u64,
        amm_quote_vol: u64,
        amm_base: Coin<B>,
        amm_quote: Coin<Q>,  // buy: this is quote in; sell: this is amm base in
        order: market::OrderEntity<B, Q>,   // order book quote qty
    ): (Coin<B>, Coin<Q>) {
        let base_out = coin::zero<B>();
        let quote_out = coin::zero<Q>();

        if (!market::is_empty_order<B, Q>(&order)) {
            let (_, _, order_left) = market::match_order(addr, side, 0, order, true);
            let (order_base, order_quote) = market::extract_order(order_left);
            coin::merge(&mut base_out, order_base);
            coin::merge(&mut quote_out, order_quote);
        } else {
            market::destroy_order(addr, order);
        };

        if (amm_base_qty > 0 || amm_quote_vol > 0) {
            if (side == BUY) {
                // buy exact base
                // let coin_in = coin::withdraw<Q>(account, amm_quote_vol);
                let coin_out = router::swap_quote_for_base<B, Q>(amm_quote, amm_base_qty);
                coin::merge(&mut base_out, coin_out);
                coin::merge(&mut base_out, amm_base);
            } else {
                // sell exact base
                // let coin_in = coin::withdraw<B>(account, amm_base_qty);
                let coin_out  = router::swap_base_for_quote<B, Q>(amm_base, amm_quote_vol);
                coin::merge(&mut quote_out, coin_out);
                coin::merge(&mut quote_out, amm_quote);
            };
        } else {
            assert!(coin::value(&amm_base) == 0, E_NON_ZERO_COIN);
            assert!(coin::value(&amm_quote) == 0, E_NON_ZERO_COIN);
            coin::destroy_zero(amm_base);
            coin::destroy_zero(amm_quote);
        };

        (base_out, quote_out)
    }

    // Tests ==================================================================
    #[test_only]
    use sea::escrow;
    #[test_only]
    use sea::router::add_liquidity;
    // #[test_only]
    // use sea_spot::lp::{LP};
    // #[test_only]
    // use std::debug;

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_hybrid_swap_buy_entry(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        market::test_register_pair(user1, user2, user3);

        add_liquidity<market::T_BTC, market::T_USD>(user1, 100000, 100000 * 15120, 0, 0);
        add_liquidity<market::T_BTC, market::T_USD>(user1, 200000, 200000 * 15120, 0, 0);

        let addr2 = address_of(user2);
        let account_id2 = escrow::get_or_register_account_id(addr2);
        market::do_place_postonly_order<market::T_BTC, market::T_USD>(
            2, // sell
            15120 * 1000000000,
            market::build_order<market::T_BTC, market::T_USD>(
                account_id2,
                0,
                120000,
                coin::withdraw(user2, 120000),
                coin::zero(),
            ),
        );

        let quote_in = router::get_amount_in<market::T_BTC, market::T_USD>(215000, true);
        // buy
        hybrid_swap_entry<market::T_BTC, market::T_USD>(
            user3,
            1,
            215000,
            quote_in,
            120000,
            120000 * 15120,
            215000+(120000-120000*5/10000),
        );
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_hybrid_swap_buy(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        market::test_register_pair(user1, user2, user3);

        add_liquidity<market::T_BTC, market::T_USD>(user1, 100000, 100000 * 15120, 0, 0);
        add_liquidity<market::T_BTC, market::T_USD>(user1, 200000, 200000 * 15120, 0, 0);

        let addr2 = address_of(user2);
        let account_id2 = escrow::get_or_register_account_id(addr2);
        market::do_place_postonly_order<market::T_BTC, market::T_USD>(
            2, // sell
            15120 * 1000000000,
            market::build_order<market::T_BTC, market::T_USD>(
                account_id2,
                0,
                120000,
                coin::withdraw(user2, 120000),
                coin::zero(),
            ),
        );

        let quote_in_vol = router::get_amount_in<market::T_BTC, market::T_USD>(215000, true);
        let addr3 = address_of(user3);
        let taker_order = market::new_order(
            user3,
            1, // buy
            0,
            120000 * 15120,
            0,
            0,
        );
        // buy
        let (base_out, quote_out) = hybrid_swap<market::T_BTC, market::T_USD>(
            addr3,
            1,
            215000,
            quote_in_vol,
            coin::zero(),
            coin::withdraw(user3, quote_in_vol),
            // 120000,
            // 120000 * 15120,
            taker_order,
            // 215000,
            // quote_in,
            // 120000,
            // 120000 * 15120,
            // 215000+(120000-120000*5/10000),
        );
        assert!(coin::value(&quote_out) == 0, 11);
        coin::destroy_zero(quote_out);
        // debug::print(&coin::value(&base_out));
        assert!(coin::value(&base_out) == 215000 + (120000 - 120000*5/10000), 12);
        coin::deposit(addr3, base_out);
    }

    // swap just use orderbook, taker complete filled
    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_hybrid_swap_buy_only_orderbook_filled(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        market::test_register_pair(user1, user2, user3);

        add_liquidity<market::T_BTC, market::T_USD>(user1, 100000, 100000 * 15120, 0, 0);
        add_liquidity<market::T_BTC, market::T_USD>(user1, 200000, 200000 * 15120, 0, 0);

        let addr2 = address_of(user2);
        let account_id2 = escrow::get_or_register_account_id(addr2);
        market::do_place_postonly_order<market::T_BTC, market::T_USD>(
            2, // sell
            15120 * 1000000000,
            market::build_order<market::T_BTC, market::T_USD>(
                account_id2,
                0,
                120000,
                coin::withdraw(user2, 120000),
                coin::zero(),
            ),
        );

        // let quote_in_vol = get_amount_in<market::T_BTC, market::T_USD>(215000, true);
        let addr3 = address_of(user3);
        let taker_order = market::new_order(
            user3,
            1, // buy
            0,
            100000 * 15120,
            0,
            0,
        );
        // buy
        let (base_out, quote_out) = hybrid_swap<market::T_BTC, market::T_USD>(
            addr3,
            1,
            0,
            0,
            coin::zero(),
            coin::zero(),
            // 120000,
            // 120000 * 15120,
            taker_order,
            // 215000,
            // quote_in,
            // 120000,
            // 120000 * 15120,
            // 215000+(120000-120000*5/10000),
        );
        assert!(coin::value(&quote_out) == 0, 11);
        coin::destroy_zero(quote_out);
        // debug::print(&coin::value(&base_out));
        assert!(coin::value(&base_out) == (100000 - 100000*5/10000), 12);
        coin::deposit(addr3, base_out);
    }

    // swap just use orderbook, taker partial filled
    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_hybrid_swap_buy_only_orderbook_partial(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        market::test_register_pair(user1, user2, user3);

        add_liquidity<market::T_BTC, market::T_USD>(user1, 100000, 100000 * 15120, 0, 0);
        add_liquidity<market::T_BTC, market::T_USD>(user1, 200000, 200000 * 15120, 0, 0);

        let addr2 = address_of(user2);
        let account_id2 = escrow::get_or_register_account_id(addr2);
        market::do_place_postonly_order<market::T_BTC, market::T_USD>(
            2, // sell
            15120 * 1000000000,
            market::build_order<market::T_BTC, market::T_USD>(
                account_id2,
                0,
                120000,
                coin::withdraw(user2, 120000),
                coin::zero(),
            ),
        );

        // let quote_in_vol = get_amount_in<market::T_BTC, market::T_USD>(215000, true);
        let addr3 = address_of(user3);
        let taker_order = market::new_order(
            user3,
            1, // buy
            0,
            200000 * 15120,
            0,
            0,
        );
        // buy
        let (base_out, quote_out) = hybrid_swap<market::T_BTC, market::T_USD>(
            addr3,
            1,
            0,
            0,
            coin::zero(),
            coin::zero(),
            // 120000,
            // 120000 * 15120,
            taker_order,
            // 215000,
            // quote_in,
            // 120000,
            // 120000 * 15120,
            // 215000+(120000-120000*5/10000),
        );
        assert!(coin::value(&quote_out) == 80000 * 15120, 11);
        coin::deposit(addr3, quote_out);
        // debug::print(&coin::value(&base_out));
        assert!(coin::value(&base_out) == (120000 - 120000*5/10000), 12);
        coin::deposit(addr3, base_out);
    }

    // swap just use amm
    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_hybrid_swap_buy_only_amm(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        market::test_register_pair(user1, user2, user3);

        add_liquidity<market::T_BTC, market::T_USD>(user1, 100000, 100000 * 15120, 0, 0);
        add_liquidity<market::T_BTC, market::T_USD>(user1, 200000, 200000 * 15120, 0, 0);

        let addr2 = address_of(user2);
        let account_id2 = escrow::get_or_register_account_id(addr2);
        market::do_place_postonly_order<market::T_BTC, market::T_USD>(
            2, // sell
            15120 * 1000000000,
            market::build_order<market::T_BTC, market::T_USD>(
                account_id2,
                0,
                120000,
                coin::withdraw(user2, 120000),
                coin::zero(),
            ),
        );

        let quote_in_vol = router::get_amount_in<market::T_BTC, market::T_USD>(215000, true);
        let addr3 = address_of(user3);
        let taker_order = market::new_order(
            user3,
            1, // buy
            0,
            0,
            0,
            0,
        );
        // buy
        let (base_out, quote_out) = hybrid_swap<market::T_BTC, market::T_USD>(
            addr3,
            1,
            215000,
            quote_in_vol,
            coin::zero(),
            coin::withdraw(user3, quote_in_vol),
            // 120000,
            // 120000 * 15120,
            taker_order,
            // 215000,
            // quote_in,
            // 120000,
            // 120000 * 15120,
            // 215000+(120000-120000*5/10000),
        );
        assert!(coin::value(&quote_out) == 0, 11);
        coin::destroy_zero(quote_out);
        // debug::print(&coin::value(&base_out));
        assert!(coin::value(&base_out) == 215000, 12);
        coin::deposit(addr3, base_out);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_hybrid_swap_sell_entry(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        market::test_register_pair(user1, user2, user3);

        add_liquidity<market::T_BTC, market::T_USD>(user1, 100000, 100000 * 15120, 0, 0);
        add_liquidity<market::T_BTC, market::T_USD>(user1, 200000, 200000 * 15120, 0, 0);

        let addr2 = address_of(user2);
        let account_id2 = escrow::get_or_register_account_id(addr2);
        market::do_place_postonly_order<market::T_BTC, market::T_USD>(
            1, // buy
            15120 * 1000000000,
            market::build_order<market::T_BTC, market::T_USD>(
                account_id2,
                0,
                120000,
                coin::zero(),
                coin::withdraw(user2, 120000*15120),
            ),
        );

        let quote_out = router::get_amount_out<market::T_BTC, market::T_USD>(215000, true);
        // debug::print(&quote_out);
        // sell
        hybrid_swap_entry<market::T_BTC, market::T_USD>(
            user3,
            2,
            215000,
            quote_out,
            120000,
            120000 * 15120,
            quote_out+(120000-120000*5/10000)*15120,
        );
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_hybrid_swap_sell(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        market::test_register_pair(user1, user2, user3);

        add_liquidity<market::T_BTC, market::T_USD>(user1, 100000, 100000 * 15120, 0, 0);
        add_liquidity<market::T_BTC, market::T_USD>(user1, 200000, 200000 * 15120, 0, 0);

        let addr2 = address_of(user2);
        let account_id2 = escrow::get_or_register_account_id(addr2);
        market::do_place_postonly_order<market::T_BTC, market::T_USD>(
            1, // buy
            15120 * 1000000000,
            market::build_order<market::T_BTC, market::T_USD>(
                account_id2,
                0,
                120000,
                coin::zero(),
                coin::withdraw(user2, 120000*15120),
            ),
        );

        let quote_out_vol = router::get_amount_out<market::T_BTC, market::T_USD>(215000, true);
        let addr3 = address_of(user3);
        let taker_order = market::new_order(
            user3,
            2, // sell
            120000,
            0,
            0,
            0,
        );
        // quote_out+(120000-120000*5/10000)*15120);
        // debug::print(&quote_out);
        // sell
        let (base_out, quote_out) = hybrid_swap<market::T_BTC, market::T_USD>(
            addr3,
            2,
            215000,
            quote_out_vol,
            coin::withdraw(user3, 215000),
            coin::zero(),
            // 120000,
            // 120000 * 15120,
            taker_order,
        );
        assert!(coin::value(&base_out) == 0, 1);
        coin::destroy_zero(base_out);
        let quote_ob_vol = 120000 * 15120;
        let ob_fee = quote_ob_vol * 5 / 10000;
        let quote_ob_net = quote_ob_vol - ob_fee;
        // debug::print(&quote_ob_net);
        // debug::print(&coin::value(&quote_out));
        assert!(coin::value(&quote_out) == quote_out_vol + quote_ob_net, 2);
        coin::deposit(addr3, quote_out);
    }

    // swap just use orderbook
    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_hybrid_swap_sell_only_orderbook_filled(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        market::test_register_pair(user1, user2, user3);

        add_liquidity<market::T_BTC, market::T_USD>(user1, 100000, 100000 * 15120, 0, 0);
        add_liquidity<market::T_BTC, market::T_USD>(user1, 200000, 200000 * 15120, 0, 0);

        let addr2 = address_of(user2);
        let account_id2 = escrow::get_or_register_account_id(addr2);
        market::do_place_postonly_order<market::T_BTC, market::T_USD>(
            1, // buy
            15120 * 1000000000,
            market::build_order<market::T_BTC, market::T_USD>(
                account_id2,
                0,
                120000,
                coin::zero(),
                coin::withdraw(user2, 120000*15120),
            ),
        );

        // let quote_out_vol = get_amount_out<market::T_BTC, market::T_USD>(215000, true);
        let addr3 = address_of(user3);
        let taker_order = market::new_order(
            user3,
            2, // sell
            100000,
            0,
            0,
            0,
        );
            // quote_out+(120000-120000*5/10000)*15120);
        // debug::print(&quote_out);
        // sell
        let (base_out, quote_out) = hybrid_swap<market::T_BTC, market::T_USD>(
            addr3,
            2,
            0,
            0,
            coin::zero(),
            coin::zero(),
            // 120000,
            // 120000 * 15120,
            taker_order,
        );
        assert!(coin::value(&base_out) == 0, 1);
        coin::destroy_zero(base_out);
        let quote_ob_vol = 100000 * 15120;
        let ob_fee = quote_ob_vol * 5 / 10000;
        let quote_ob_net = quote_ob_vol - ob_fee;
        // debug::print(&quote_ob_net);
        // debug::print(&coin::value(&quote_out));
        assert!(coin::value(&quote_out) == quote_ob_net, 2);
        coin::deposit(addr3, quote_out);
    }

    // swap just use orderbook, taker partial filled
    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_hybrid_swap_sell_only_orderbook_partial(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        market::test_register_pair(user1, user2, user3);

        add_liquidity<market::T_BTC, market::T_USD>(user1, 100000, 100000 * 15120, 0, 0);
        add_liquidity<market::T_BTC, market::T_USD>(user1, 200000, 200000 * 15120, 0, 0);

        let addr2 = address_of(user2);
        let account_id2 = escrow::get_or_register_account_id(addr2);
        market::do_place_postonly_order<market::T_BTC, market::T_USD>(
            1, // buy
            15120 * 1000000000,
            market::build_order<market::T_BTC, market::T_USD>(
                account_id2,
                0,
                120000,
                coin::zero(),
                coin::withdraw(user2, 120000*15120),
            ),
        );

        // let quote_out_vol = get_amount_out<market::T_BTC, market::T_USD>(215000, true);
        let addr3 = address_of(user3);
        let taker_order = market::new_order(
            user3,
            2, // sell
            200000,
            0,
            0,
            0,
        );
            // quote_out+(120000-120000*5/10000)*15120);
        // debug::print(&quote_out);
        // sell
        let (base_out, quote_out) = hybrid_swap<market::T_BTC, market::T_USD>(
            addr3,
            2,
            0,
            0,
            coin::zero(),
            coin::zero(),
            // 120000,
            // 120000 * 15120,
            taker_order,
        );
        assert!(coin::value(&base_out) == 200000-120000, 1);
        coin::deposit(addr3, base_out);
        let quote_ob_vol = 120000 * 15120;
        let ob_fee = quote_ob_vol * 5 / 10000;
        let quote_ob_net = quote_ob_vol - ob_fee;
        // debug::print(&quote_ob_net);
        // debug::print(&coin::value(&quote_out));
        assert!(coin::value(&quote_out) == quote_ob_net, 2);
        coin::deposit(addr3, quote_out);
    }

    // swap just use amm
    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_hybrid_swap_sell_only_amm(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        market::test_register_pair(user1, user2, user3);

        add_liquidity<market::T_BTC, market::T_USD>(user1, 100000, 100000 * 15120, 0, 0);
        add_liquidity<market::T_BTC, market::T_USD>(user1, 200000, 200000 * 15120, 0, 0);

        let addr2 = address_of(user2);
        let account_id2 = escrow::get_or_register_account_id(addr2);
        market::do_place_postonly_order<market::T_BTC, market::T_USD>(
            1, // buy
            15120 * 1000000000,
            market::build_order<market::T_BTC, market::T_USD>(
                account_id2,
                0,
                120000,
                coin::zero(),
                coin::withdraw(user2, 120000*15120),
            ),
        );

        // let quote_out_vol = get_amount_out<market::T_BTC, market::T_USD>(215000, true);
        let addr3 = address_of(user3);
        let taker_order = market::new_order(
            user3,
            2, // sell
            200000,
            0,
            0,
            0,
        );
        // quote_out+(120000-120000*5/10000)*15120);
        // debug::print(&quote_out);
        // sell
        let (base_out, quote_out) = hybrid_swap<market::T_BTC, market::T_USD>(
            addr3,
            2,
            0,
            0,
            coin::zero(),
            coin::zero(),
            // 120000,
            // 120000 * 15120,
            taker_order,
        );
        assert!(coin::value(&base_out) == 200000-120000, 1);
        coin::deposit(addr3, base_out);
        let quote_ob_vol = 120000 * 15120;
        let ob_fee = quote_ob_vol * 5 / 10000;
        let quote_ob_net = quote_ob_vol - ob_fee;
        // debug::print(&quote_ob_net);
        // debug::print(&coin::value(&quote_out));
        assert!(coin::value(&quote_out) == quote_ob_net, 2);
        coin::deposit(addr3, quote_out);
    }

    /*
    // alloc hybrid swap
    #[test]
    fun test_get_amm_price() {
        use std::debug;

        let qty: u128 = 100000;
        let price_ratio: u128 = 1000000000;
        let base_reserve: u128 = 1000000000;
        let quote_reserve: u128 = 25000*1000000000;
        let fee_ratio: u128 = 200;
        let fee_deno: u128 = 1000000;

        // buy
        let buy_price = get_amm_price(BUY, qty, price_ratio, base_reserve, quote_reserve, fee_ratio, fee_deno);
        // sell
        let sell_price = get_amm_price(SELL, qty, price_ratio, base_reserve, quote_reserve, fee_ratio, fee_deno);

        debug::print(&buy_price);
        debug::print(&sell_price);
    }

    // partial use orderbook
    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_calc_hybrid_swap_sell_1(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        market::test_register_pair(user1, user2, user3);
        // 
        let addr2 = address_of(user2);
        let account_id2 = escrow::get_or_register_account_id(addr2);
        let o1 = market::do_place_postonly_order<market::T_BTC, market::T_USD>(
            BUY, // buy
            15120 * 1000000000,
            market::build_order<market::T_BTC, market::T_USD>(
                account_id2,
                0,
                120000000,
                coin::zero(),
                coin::withdraw(user2, 120000000*15120),
            ),
        );
        let o2 = market::do_place_postonly_order<market::T_BTC, market::T_USD>(
            BUY, // buy
            15110 * 1000000000,
            market::build_order<market::T_BTC, market::T_USD>(
                account_id2,
                0,
                120000000,
                coin::zero(),
                coin::withdraw(user2, 120000000*15110),
            ),
        );
        let o3 = market::do_place_postonly_order<market::T_BTC, market::T_USD>(
            BUY, // buy
            15100 * 1000000000,
            market::build_order<market::T_BTC, market::T_USD>(
                account_id2,
                0,
                120000000,
                coin::zero(),
                coin::withdraw(user2, 120000000*15100),
            ),
        );

        let steps = market::get_pair_side_steps<market::T_BTC, market::T_USD>(BUY);
        let (base_reserve, quote_reserve, amm_fee_ratio) = amm::get_pool_reserve_fee_u128<market::T_BTC, market::T_USD>();
        let (amm_base_qty, amm_quote_vol, ob_base_qty, ob_quote_vol) = 
            calc_hybrid_partial<market::T_BTC, market::T_USD>(SELL, 100000000, base_reserve, quote_reserve, amm_fee_ratio, &steps);
        assert!(amm_base_qty == 0, 1);
        assert!(amm_quote_vol == 0, 1);
        assert!(ob_base_qty == 100000000, 1);
        // debug::print(&ob_quote_vol);
        assert!(ob_quote_vol == 15120 * 100000000, 1);

        // add some liquid
        add_liquidity<market::T_BTC, market::T_USD>(user1, 100000000, 100000000 * 15120, 0, 0);
        add_liquidity<market::T_BTC, market::T_USD>(user1, 200000000, 200000000 * 15120, 0, 0);
        let steps = market::get_pair_side_steps<market::T_BTC, market::T_USD>(BUY);
        let (base_reserve, quote_reserve, amm_fee_ratio) = amm::get_pool_reserve_fee_u128<market::T_BTC, market::T_USD>();
        let (amm_base_qty, amm_quote_vol, ob_base_qty, ob_quote_vol) = 
            calc_hybrid_partial<market::T_BTC, market::T_USD>(SELL, 100000000, base_reserve, quote_reserve, amm_fee_ratio, &steps);

        assert!(amm_base_qty == 0, 1);
        assert!(amm_quote_vol == 0, 1);
        assert!(ob_base_qty == 100000000, 1);
        assert!(ob_quote_vol == 15120 * 100000000, 1);

        let lp_balance = coin::balance<LP<market::T_BTC, market::T_USD>>(address_of(user1));
        // debug::print(&lp_balance);
        // total suply: 2379936758
        // lp_balance:  36889019757
        //              36889022757.45455
        // 281818181
        // 300000000
        router::remove_liquidity<market::T_BTC, market::T_USD>(user1, lp_balance, 300000000-1000, 300000000 * 15120-1000);
        let steps = market::get_pair_side_steps<market::T_BTC, market::T_USD>(BUY);
        let (base_reserve, quote_reserve, amm_fee_ratio) = amm::get_pool_reserve_fee_u128<market::T_BTC, market::T_USD>();
        let (amm_base_qty, amm_quote_vol, ob_base_qty, ob_quote_vol) = 
            calc_hybrid_partial<market::T_BTC, market::T_USD>(SELL, 100000000, base_reserve, quote_reserve, amm_fee_ratio, &steps);

        assert!(amm_base_qty == 0, 1);
        assert!(amm_quote_vol == 0, 1);
        assert!(ob_base_qty == 100000000, 1);
        assert!(ob_quote_vol == 15120 * 100000000, 1);

        market::cancel_order<market::T_BTC, market::T_USD>(user2, 1, o1);
        market::cancel_order<market::T_BTC, market::T_USD>(user2, 1, o2);
        market::cancel_order<market::T_BTC, market::T_USD>(user2, 1, o3);
        // 100000000
        add_liquidity<market::T_BTC, market::T_USD>(user1, 100000000, 100000000 * 15120, 0, 0);
        add_liquidity<market::T_BTC, market::T_USD>(user1, 200000000, 200000000 * 15120, 0, 0);
        let (base_reserve, quote_reserve, amm_fee_ratio) = amm::get_pool_reserve_fee_u128<market::T_BTC, market::T_USD>();
        let (amm_base_qty, amm_quote_vol, ob_base_qty, ob_quote_vol) = 
            calc_hybrid_partial<market::T_BTC, market::T_USD>(SELL, 100000000, base_reserve, quote_reserve, amm_fee_ratio,
                &vector::empty<market::PriceStep>());

        assert!(amm_base_qty == 100000000, 1);
        assert!(amm_quote_vol == 1133574696837, 1);
        assert!(ob_base_qty == 0, 1);
        assert!(ob_quote_vol == 0, 1);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_calc_hybrid_swap_sell_2(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        use std::debug;

        market::test_register_pair(user1, user2, user3);
        let steps = vector::empty<market::PriceStep>();
        let price_ratio = 1000000000;
        // buy orders
        vector::push_back(&mut steps, market::new_price_step(100000000, 27060*price_ratio, 1));
        vector::push_back(&mut steps, market::new_price_step(110000000, 27059*price_ratio, 8));
        vector::push_back(&mut steps, market::new_price_step(120000000, 27058*price_ratio, 5));
        vector::push_back(&mut steps, market::new_price_step(130000000, 27055*price_ratio, 2));
        let amm_pools = vector<vector<u64>>[
            vector<u64>[100000000, 27061*100000000],
            vector<u64>[200000000, 27061*200000000],
            vector<u64>[300000000, 27061*300000000],
            vector<u64>[500000000, 27061*500000000],
            vector<u64>[1000000000, 27061*1000000000],
            vector<u64>[100000000, 27060*100000000],
            vector<u64>[200000000, 27060*200000000],
            vector<u64>[300000000, 27060*300000000],
            vector<u64>[500000000, 27060*500000000],
            vector<u64>[1000000000, 27060*1000000000],
            vector<u64>[100000000, 27058*100000000],
            vector<u64>[200000000, 27058*200000000],
            vector<u64>[300000000, 27058*300000000],
            vector<u64>[500000000, 27058*500000000],
            vector<u64>[1000000000, 27058*1000000000],
            vector<u64>[100000000, 27054*100000000],
            vector<u64>[200000000, 27058*200000000],
            vector<u64>[300000000, 27058*300000000],
            vector<u64>[500000000, 27058*500000000],
            vector<u64>[1000000000, 27058*1000000000],
        ];

        let i = 0;
        let j = 0;
        let amm_fee_ratio = 10;
        let qty = 10000000;
        while (i < vector::length(&amm_pools)) {
            let pool = vector::borrow(&amm_pools, i);
            let base_reserve = (*vector::borrow(pool, 0) as u128);
            let quote_reserve = (*vector::borrow(pool, 1) as u128);
            while (j < 10) {
                qty = qty * (j + 1) * 15 / 10;
                let (amm_base_qty, amm_quote_vol, ob_base_qty, ob_quote_vol) = 
                    calc_hybrid_partial<market::T_BTC, market::T_USD>(
                        SELL,
                        qty,
                        base_reserve, quote_reserve, amm_fee_ratio,
                        &steps);
                debug::print(&i);
                debug::print(&j);
                debug::print(&qty);
                debug::print(&amm_base_qty);
                debug::print(&amm_quote_vol);
                debug::print(&ob_base_qty);
                debug::print(&ob_quote_vol);
            }
        }
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_calc_hybrid_swap_buy_1(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        market::test_register_pair(user1, user2, user3);

        add_liquidity<market::T_BTC, market::T_USD>(user1, 100000, 100000 * 15120, 0, 0);
        add_liquidity<market::T_BTC, market::T_USD>(user1, 200000, 200000 * 15120, 0, 0);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3
    )]
    fun test_calc_hybrid_swap_buy_2(
        user1: &signer,
        user2: &signer,
        user3: &signer,
    ) {
        market::test_register_pair(user1, user2, user3);

    }
    */
}
