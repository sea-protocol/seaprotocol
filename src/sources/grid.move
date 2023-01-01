/// # Module-level documentation sections
///
/// * [Background](#Background)
/// * [Implementation](#Implementation)
/// * [Basic public functions](#Basic-public-functions)
/// * [Traversal](#Traversal)
///
/// # Background
///
/// spot grid
/// 
module sea::grid {
    use sea::price;
    use sea::utils;

    const BUY:                    u8 = 1;
    const SELL:                   u8 = 2;
    const PRICE_DENOMINATE_64:    u64 = 100000;
    const PRICE_DENOMINATE_128:   u128 = 100000;
    // arithmetic: price_diff = (grid_upper_limit - grid_lower_limit) / grid_count

    // fun is_grid_arith_mode(opts: u64): bool {
    //     (opts & 0x01) == GRID_OPTS_ARITH
    // }

    // fun is_grid_base_equal(opts: u64): bool {
    //     (opts & 0x2) == GRID_OPTS_EQUAL_BASE
    // }

    // sell orders: next level's price higher
    // buy orders: next level's price lower
    public fun next_level_price(
        side: u8,
        arithmetic: bool,
        price: u64,
        delta: u64,
    ): u64 {
        let nprice;

        if (arithmetic) {
            nprice = if (side == BUY) price - delta else price + delta;
        } else {
            if (side == BUY) {
                // buy
                nprice = (((price as u128) * PRICE_DENOMINATE_128 / ((PRICE_DENOMINATE_64 + delta) as u128)) as u64)
            } else {
                // flip order is sell order
                nprice = (((price as u128) * ((PRICE_DENOMINATE_64 + delta) as u128) / PRICE_DENOMINATE_128) as u64)
            };
        };

        price::to_valid_price(nprice)
    }

    public fun next_level_qty(
        base_equal: bool,
        qty: u64,
        price: u64,
        price_ratio: u64,
        lot_size: u64,
    ): u64 {
        let nqty;

        if (base_equal) {
            nqty = qty;
        } else {
            nqty = utils::calc_base_qty(qty, price, price_ratio);
        };
        if (lot_size > 0) {
            nqty = nqty / lot_size * lot_size;
        };

        nqty
    }

    // side: the flip order's side: 1: BUY; 2: SELL
    // return: (price, base_qty, quote_qty)
    public fun calc_grid_order_price_qty(
        side: u8,
        arithmetic: bool,
        price: u64,
        price_delta: u64,
        volume: u64,
        // quote_amt: u64,
        price_ratio: u64,
        lot_size: u64,
    ): (u64, u64, u64) {
        let nprice;
        let base_qty;
        let quote_qty = 0;

        // price
        if (arithmetic) {
            nprice = if (side == BUY) price - price_delta else price + price_delta;
        } else {
            if (side == BUY) {
                // buy
                nprice = (((price as u128) * PRICE_DENOMINATE_128 / ((PRICE_DENOMINATE_64 + price_delta) as u128)) as u64)
            } else {
                // flip order is sell order
                nprice = (((price as u128) * ((PRICE_DENOMINATE_64 + price_delta) as u128) / PRICE_DENOMINATE_128) as u64)
            };
            nprice = price::to_valid_price(nprice);
        };
        // base qty
        if (side == BUY) {
            // buy order
            base_qty = ((((volume as u128) * (price_ratio as u128)/ (nprice as u128)) as u64) / lot_size) * lot_size;
            quote_qty = (((nprice as u128) * (base_qty as u128) / (price_ratio as u128)) as u64);
        } else {
            // sell order
            base_qty = (volume / lot_size) * lot_size
        };

        (nprice, base_qty, quote_qty)
    }

    #[test]
    fun test_grid_flip_eth() {
        use std::vector;
        // use std::debug;

        // eth/usdc price is about 1000
        // usdc is 6 decimals, eth is 8 decimals
        let price_ratio = 100000000000;
        let lot_size = 100000;
        let prices: vector<u64> = vector[45, 500, 612, 999, 1001, 1215, 4587, 10006];
        // 20, 12, 8, 5, 3, 2, 1.8, 1.6, 1.5, 1.4, 1.3, 1.2, 1.15, 1.1, 1.05, 1.04, 1.01
        let ratios: vector<u64> = vector[1900000, 1100000, 700000, 400000, 200000, 100000, 80000, 
        60000, 50000, 40000, 30000, 20000, 15000, 10000, 5000, 4000, 1000];
        // 0.1 0.2345, 1.0586
        let bases: vector<u64> = vector[10000000, 23450000, 105860000]; // flip to sell orders
        // 100, 1000, 5000
        let quotes: vector<u64> = vector[100000000, 1000000000, 5000000000]; // flip to buy orders

        let i: u64 = 0;
        let j: u64 = 0;
        let k: u64 = 0;
        // side = 2
        while (i < vector::length(&bases)) {
            let base = vector::borrow<u64>(&mut bases, i);
            while (j < vector::length(&ratios)) {
                let ratio = vector::borrow(&mut ratios, j);
                while (k < vector::length(&prices)) {
                    let price = vector::borrow(&mut prices, k);

                    let (nprice, base_qty, quote_qty) = calc_grid_order_price_qty(2,
                        true,
                        *price * price_ratio,
                        *ratio,
                        *base,
                        price_ratio,
                        lot_size
                        );

                    nprice;
                    base_qty;
                    quote_qty;
                    // debug::print(&nprice);
                    // debug::print(&base_qty);
                    // debug::print(&quote_qty);
                    k = k +1;
                };
                k = 0;
                j = j + 1;
            };
            j = 0;
            i = i + 1;
        };

        // side = 1
        i = 0;
        j = 0;
        k = 0;
        while (i < vector::length(&quotes)) {
            let quote = vector::borrow<u64>(&mut quotes, i);
            while (j < vector::length(&ratios)) {
                let ratio = vector::borrow(&mut ratios, j);
                while (k < vector::length(&prices)) {
                    let price = vector::borrow(&mut prices, k);

                    let (nprice, base_qty, quote_qty) = calc_grid_order_price_qty(1,
                        true,
                        *price * price_ratio,
                        *ratio,
                        *quote,
                        price_ratio,
                        lot_size
                        );

                    nprice;
                    base_qty;
                    quote_qty;
                    // debug::print(&nprice);
                    // debug::print(&base_qty);
                    // debug::print(&quote_qty);
                    k = k +1;
                };
                k = 0;
                j = j + 1;
            };
            j = 0;
            i = i + 1;
        };
    }

    #[test]
    fun test_grid_flip_1() {
        // usdt/usdc
        // usdc is 6 decimals, usdt is 4 decimals
        use std::vector;
        // use std::debug;

        let price_ratio = 10000000;
        let lot_size = 100000;
        let prices: vector<u64> = vector[9996, 9997, 9998, 9999, 10000, 10001, 10002, 10003, 10004, 10005, 10006];
        // 1.2, 1.1, 1.05, 1.04, 1.01
        let ratios: vector<u64> = vector[20000, 10000, 5000, 4000, 1000];
        // 100, 200 usdt
        let bases: vector<u64> = vector[1000000, 2000000]; // flip to sell orders
        // 100, 200 usdc
        let quotes: vector<u64> = vector[100000000, 200000000]; // flip to buy orders

        let i: u64 = 0;
        let j: u64 = 0;
        let k: u64 = 0;
        // side = 2
        while (i < vector::length(&bases)) {
            let base = vector::borrow<u64>(&mut bases, i);
            while (j < vector::length(&ratios)) {
                let ratio = vector::borrow(&mut ratios, j);
                while (k < vector::length(&prices)) {
                    let price = vector::borrow(&mut prices, k);

                    let (nprice, base_qty, quote_qty) = calc_grid_order_price_qty(2,
                        true,
                        *price * price_ratio/10000,
                        *ratio,
                        *base,
                        price_ratio,
                        lot_size
                        );

                        nprice;
                        base_qty;
                        quote_qty;
                    // debug::print(&nprice);
                    // debug::print(&base_qty);
                    // debug::print(&quote_qty);
                    k = k +1;
                };
                k = 0;
                j = j + 1;
            };
            j = 0;
            i = i + 1;
        };

        // side = 1
        i = 0;
        j = 0;
        k = 0;
        while (i < vector::length(&quotes)) {
            let quote = vector::borrow<u64>(&mut quotes, i);
            while (j < vector::length(&ratios)) {
                let ratio = vector::borrow(&mut ratios, j);
                while (k < vector::length(&prices)) {
                    let price = vector::borrow(&mut prices, k);

                    let (nprice, base_qty, quote_qty) = calc_grid_order_price_qty(1,
                        true,
                        *price * price_ratio,
                        *ratio,
                        *quote,
                        price_ratio,
                        lot_size
                        );

                    nprice;
                    base_qty;
                    quote_qty;
                    // debug::print(&nprice);
                    // debug::print(&base_qty);
                    // debug::print(&quote_qty);
                    k = k +1;
                };
                k = 0;
                j = j + 1;
            };
            j = 0;
            i = i + 1;
        };
    }

    #[test]
    fun test_grid_flip_0001() {
        // use std::debug;

        // price about 0.001/usdc
        // usdc is 6 decimals, base token is 8 decimals
        let price_ratio = 100000000000;
        let lot_size = 100000000; // 1
        let ratio = 12000; // 1.12
        let price = 9000000; // 0.009
        let i = 0;
        let qty = 1000000000000; // 10000
        //        1973600000000
        
        while (i < 100) {
            // flip 100 times
            // sell
            let (nprice, base_qty, _) = calc_grid_order_price_qty(
                SELL,
                true,
                price,
                ratio,
                qty,
                price_ratio,
                lot_size
            );
            // debug::print(&i);
            // debug::print(&nprice);

            let quote_qty = (((base_qty as u128) * (nprice as u128) / (price_ratio as u128)) as u64);
            (price, qty, _) = calc_grid_order_price_qty(
                BUY,
                true,
                nprice,
                ratio,
                quote_qty,
                price_ratio,
                lot_size
            );
            // debug::print(&price);
            // debug::print(&qty);
            // buy
            i = i + 1;
        }
    }
}
