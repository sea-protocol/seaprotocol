/// # Module-level documentation sections
///
/// * [Background](#Background)
/// * [Implementation](#Implementation)
/// * [Basic public functions](#Basic-public-functions)
/// * [Traversal](#Traversal)
///
/// # Background
///
/// router for orderbook and AMM
/// 
module sea::router {
    use std::signer::address_of;
    // use std::debug;
    use aptos_framework::coin::{Self, Coin};

    use sea_spot::lp::{LP};
    
    use sea::amm;
    use sea::escrow;
    use sea::utils;
    use sea::fee;
    use sea::market;
    
    const BUY:                u8   = 1;
    const SELL:               u8   = 2;

    const E_NO_AUTH:                              u64 = 100;
    const E_POOL_NOT_EXIST:                       u64 = 7000;
    const E_INSUFFICIENT_BASE_AMOUNT:             u64 = 7001;
    const E_INSUFFICIENT_QUOTE_AMOUNT:            u64 = 7002;
    const E_INSUFFICIENT_AMOUNT:                  u64 = 7003;
    const E_INVALID_AMOUNT_OUT:                   u64 = 7004;
    const E_INVALID_AMOUNT_IN:                    u64 = 7005;
    const E_INSUFFICIENT_LIQUIDITY:               u64 = 7006;
    const E_INSUFFICIENT_QUOTE_RESERVE:           u64 = 7007;
    const E_INSUFFICIENT_BASE_RESERVE:            u64 = 7008;
    const E_INSUFFICIENT_AMOUNT_OUT:              u64 = 7009;

    // hybrid swap
    public entry fun hybrid_swap_entry<B, Q>(
        account: &signer,
        side: u8,
        amm_base_qty: u64,
        amm_qty_in: u64,  // buy: this is quote in; sell: this is amm base in
        ob_base_qty: u64,   // order book base qty
        ob_price: u64, // order book min/max price
        ob_vol: u64,   // order book quote qty
        slip_in_out: u64, // slippage in/out quote volume
    ) {
        let base_out = coin::zero<B>();
        let quote_out = coin::zero<Q>();
        let addr = address_of(account);

        if (ob_base_qty > 0) {
            let order = market::new_order<B, Q>(account, side, ob_base_qty, ob_vol, 0, 0);
            let order_left = market::match_order(addr, side, ob_price, order);
            let (order_base, order_quote) = market::extract_order(order_left);
            coin::merge(&mut base_out, order_base);
            coin::merge(&mut quote_out, order_quote);
        };
        if (amm_base_qty > 0) {
            if (side == BUY) {
                // buy exact base
                let coin_in = coin::withdraw<Q>(account, amm_qty_in);
                let coin_out = swap_quote_for_base<B, Q>(coin_in, amm_base_qty);
                coin::merge(&mut base_out, coin_out);
            } else {
                // sell exact base
                let coin_in = coin::withdraw<B>(account, amm_base_qty);
                let coin_out  = swap_base_for_quote<B, Q>(coin_in, amm_qty_in);
                coin::merge(&mut quote_out, coin_out);
            };
        };
        if (side == BUY) {
            // taker got base
            assert!(coin::value(&base_out) > slip_in_out, E_INSUFFICIENT_AMOUNT_OUT);
            utils::register_coin_if_not_exist<B>(account);
        } else {
            // taker got quote
            assert!(coin::value(&quote_out) > slip_in_out, E_INSUFFICIENT_AMOUNT_OUT);
            utils::register_coin_if_not_exist<Q>(account);
        };

        let addr = address_of(account);
        coin::deposit(addr, base_out);
        coin::deposit(addr, quote_out);
    }

    public entry fun add_liquidity<B, Q>(
        account: &signer,
        amt_base_desired: u64,
        amt_quote_desired: u64,
        amt_base_min: u64,
        amt_quote_min: u64
    ) {
        assert!(amm::pool_exist<B, Q>(), E_POOL_NOT_EXIST);

        let (amount_base,
            amount_quote) = amm::calc_optimal_coin_values<B, Q>(
                amt_base_desired,
                amt_quote_desired,
                amt_base_min,
                amt_quote_min);
        let coin_base = coin::withdraw<B>(account, amount_base);
        let coin_quote = coin::withdraw<Q>(account, amount_quote);
        let lp_coins = amm::mint<B, Q>(coin_base, coin_quote);

        let acc_addr = address_of(account);
        utils::register_coin_if_not_exist<LP<B, Q>>(account);
        coin::deposit(acc_addr, lp_coins);
    }

    public entry fun remove_liquidity<B, Q>(
        account: &signer,
        liquidity: u64,
        amt_base_min: u64,
        amt_quote_min: u64,
    ) {
        assert!(amm::pool_exist<B, Q>(), E_POOL_NOT_EXIST);
        let coins = coin::withdraw<LP<B, Q>>(account, liquidity);
        let (base_out, quote_out) = amm::burn<B, Q>(coins);

        assert!(coin::value(&base_out) >= amt_base_min, E_INSUFFICIENT_BASE_AMOUNT);
        assert!(coin::value(&quote_out) >= amt_quote_min, E_INSUFFICIENT_QUOTE_AMOUNT);

        // transfer
        let account_addr = address_of(account);
        coin::deposit(account_addr, base_out);
        coin::deposit(account_addr, quote_out);
    }

    // user: buy exact quote
    // amount_out: quote amount out of pool
    // amount_in_max: base amount into pool
    public entry fun buy_exact_quote<B, Q>(
        account: &signer,
        amount_out: u64,
        amount_in_max: u64
        ) {
        let coin_in_needed = get_amount_in<B, Q>(amount_out, false);
        assert!(coin_in_needed <= amount_in_max, E_INSUFFICIENT_BASE_AMOUNT);
        let coin_in = coin::withdraw<B>(account, coin_in_needed);
        let coin_out;
        coin_out = swap_base_for_quote<B, Q>(coin_in, amount_out);
        utils::register_coin_if_not_exist<Q>(account);
        coin::deposit<Q>(address_of(account), coin_out);
    }

    // user: sell base
    public entry fun sell_exact_base<B, Q>(
        account: &signer,
        amount_in: u64,
        amount_out_min: u64
        ) {
        let coin_in = coin::withdraw<B>(account, amount_in);
        let coin_out;
        coin_out = swap_base_for_quote<B, Q>(coin_in, amount_out_min);
        assert!(coin::value(&coin_out) >= amount_out_min, E_INSUFFICIENT_QUOTE_AMOUNT);
        utils::register_coin_if_not_exist<Q>(account);
        coin::deposit<Q>(address_of(account), coin_out);
    }

    // user: buy base
    // amount_out: the exact base amount
    public entry fun buy_exact_base<B, Q>(
        account: &signer,
        amount_out: u64,
        amount_in_max: u64
        ) {
        let coin_in_needed = get_amount_in<B, Q>(amount_out, true);
        assert!(coin_in_needed <= amount_in_max, E_INSUFFICIENT_BASE_AMOUNT);
        let coin_in = coin::withdraw<Q>(account, coin_in_needed);
        let coin_out;
        coin_out = swap_quote_for_base<B, Q>(coin_in, amount_out);
        utils::register_coin_if_not_exist<B>(account);
        coin::deposit<B>(address_of(account), coin_out);
    }

    // user: sell exact quote
    public entry fun sell_exact_quote<B, Q>(
        account: &signer,
        amount_in: u64,
        amount_out_min: u64
        ) {
        let coin_in = coin::withdraw<Q>(account, amount_in);
        let coin_out;
        coin_out = swap_quote_for_base<B, Q>(coin_in, amount_out_min);
        assert!(coin::value(&coin_out) >= amount_out_min, E_INSUFFICIENT_QUOTE_AMOUNT);
        utils::register_coin_if_not_exist<B>(account);
        coin::deposit<B>(address_of(account), coin_out);
    }

    public entry fun withdraw_dao_fee<B, Q>(
        account: &signer,
        to: address
    ) {
        assert!(address_of(account) == @sea, E_NO_AUTH);

        let amount = coin::balance<LP<B, Q>>(@sea_spot) - amm::get_min_liquidity();
        assert!(amount > 0, E_INSUFFICIENT_AMOUNT);
        coin::transfer<LP<B, Q>>(&escrow::get_spot_account(), to, amount);
    }

    /*
    // if buy base, provide quote coin
    // if sell base, provide base coin
    public fun hybrid_swap<B, Q>(
        side: u8,
        addr: address,
        total_base_in: Coin<B>,
        total_quote_in: Coin<Q>,
        amm_base_qty: u64,
        amm_qty_in: u64,  // buy: this is quote in; sell: this is amm base in
        ob_base_qty: u64, // order book base qty
        ob_price: u64, // order book min/max price
        ob_vol: u64,   // order book quote qty
        slip_in_out: u64, // slippage in/out quote volume
    ): (Coin<B>, Coin<Q>) {
        let base_out = coin::zero<B>();
        let quote_out = coin::zero<Q>();

        if (ob_base_qty > 0) {
            let order = market::build_order<B, Q>(account, side, ob_base_qty, ob_vol, 0, 0);
            let order_left = market::match_order(addr, side, ob_price, order);
            let (order_base, order_quote) = market::extract_order(order_left);
            coin::merge(&mut base_out, order_base);
            coin::merge(&mut quote_out, order_quote);
        };
        if (amm_base_qty > 0) {
            if (side == BUY) {
                // buy exact base
                let coin_in = coin::withdraw<Q>(account, amm_qty_in);
                let coin_out = swap_quote_for_base<B, Q>(coin_in, amm_base_qty);
                coin::merge(&mut base_out, coin_out);
            } else {
                // sell exact base
                let coin_in = coin::withdraw<B>(account, amm_base_qty);
                let coin_out  = swap_base_for_quote<B, Q>(coin_in, amm_qty_in);
                coin::merge(&mut quote_out, coin_out);
            };
        };
        if (side == BUY) {
            // taker got base
            assert!(coin::value(&base_out) > slip_in_out, E_INSUFFICIENT_AMOUNT_OUT);
        } else {
            // taker got quote
            assert!(coin::value(&quote_out) > slip_in_out, E_INSUFFICIENT_AMOUNT_OUT);
        };

        (base_out, quote_out)
    }
    */

    // sell base, buy quote
    public fun swap_base_for_quote<B, Q>(
        coin_in: Coin<B>,
        coin_out_val: u64
    ): Coin<Q> {
        let (zero, coin_out) = amm::swap<B, Q>(coin_in, 0, coin::zero(), coin_out_val);
        coin::destroy_zero(zero);

        coin_out
    }

    // sell quote, buy base
    public fun swap_quote_for_base<B, Q>(
        coin_in: Coin<Q>,
        coin_out_val: u64,
    ): Coin<B> {
        let (coin_out, zero) = amm::swap<B, Q>(coin::zero(), coin_out_val, coin_in, 0);
        coin::destroy_zero(zero);

        coin_out
    }

    /// out_is_base: in user perspective
    public fun get_amount_in<B, Q>(
        amount_out: u64,
        out_is_base: bool,
    ): u64 {
        assert!(amount_out > 0, E_INVALID_AMOUNT_OUT);
        let (base_reserve, quote_reserve, fee_ratio) = amm::get_pool_reserve_fee<B, Q>();
        assert!(base_reserve> 0 && quote_reserve > 0, E_INSUFFICIENT_LIQUIDITY);

        let numerator: u128;
        let denominator: u128;
        let fee_deno = fee::get_fee_denominate();
        if (out_is_base) {
            assert!(base_reserve > amount_out, E_INSUFFICIENT_BASE_RESERVE);
            numerator = (quote_reserve as u128) * (amount_out as u128) * (fee_deno as u128);
            denominator = ((base_reserve - amount_out) as u128) * ((fee_deno - fee_ratio) as u128);
        } else {
            assert!(quote_reserve > amount_out, E_INSUFFICIENT_QUOTE_RESERVE);
            numerator = (base_reserve as u128) * (amount_out as u128) * (fee_deno as u128);
            denominator = ((quote_reserve - amount_out) as u128) * ((fee_deno - fee_ratio) as u128);
        };

        // debug::print(&denominator);
        ((numerator / denominator + 1) as u64)
    }

    public fun get_amount_out<B, Q>(
        amount_in: u64,
        out_is_quote: bool,
    ): u64 {
        assert!(amount_in > 0, E_INVALID_AMOUNT_IN);
        let (base_reserve, quote_reserve, fee_ratio) = amm::get_pool_reserve_fee<B, Q>();
        assert!(base_reserve > 0 && quote_reserve > 0, E_INSUFFICIENT_LIQUIDITY);

        let fee_deno = fee::get_fee_denominate();
        let amount_in_with_fee = (amount_in as u128) * ((fee_deno - fee_ratio) as u128);
        let numerator: u128;
        let denominator: u128;
        if (out_is_quote) {
            numerator = amount_in_with_fee * (quote_reserve as u128);
            denominator = (base_reserve as u128) * (fee_deno as u128) + amount_in_with_fee;
        } else {
            numerator = amount_in_with_fee * (base_reserve as u128);
            denominator = (quote_reserve as u128) * (fee_deno as u128) + amount_in_with_fee;
        };

        let amount_out = numerator / denominator;
        // debug::print(&amount_out);
        (amount_out as u64)
    }

    #[test]
    fun test_hybrid_swap() {

    }
}
