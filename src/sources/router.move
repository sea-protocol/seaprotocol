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
    use aptos_framework::coin::{Self, Coin};

    use sea::amm::{Self, LP};
    use sea::escrow;
    use sea::utils;
    use sea::fee;
    
    const E_NO_AUTH:                              u64 = 100;
    const E_POOL_NOT_EXIST:                       u64 = 7000;
    const E_INSUFFICIENT_BASE_AMOUNT:             u64 = 7001;
    const E_INSUFFICIENT_QUOTE_AMOUNT:            u64 = 7002;
    const E_INSUFFICIENT_AMOUNT:                  u64 = 7003;
    const E_INVALID_AMOUNT_OUT:                   u64 = 7004;
    const E_INSUFFICIENT_LIQUIDITY:               u64 = 7005;

    public entry fun add_liquidity<B, Q, F>(
        account: &signer,
        amt_base_desired: u64,
        amt_quote_desired: u64,
        amt_base_min: u64,
        amt_quote_min: u64
    ) {
        assert!(amm::pool_exist<B, Q, F>(), E_POOL_NOT_EXIST);

        let (amount_base,
            amount_quote) = amm::calc_optimal_coin_values<B, Q, F>(
                amt_base_desired,
                amt_quote_desired,
                amt_base_min,
                amt_quote_min);
        let coin_base = coin::withdraw<B>(account, amount_base);
        let coin_quote = coin::withdraw<Q>(account, amount_quote);
        let lp_coins = amm::mint<B, Q, F>(coin_base, coin_quote);

        let acc_addr = address_of(account);
        if (!coin::is_account_registered<LP<B, Q, F>>(acc_addr)) {
            coin::register<LP<B, Q, F>>(account);
        };
        coin::deposit(acc_addr, lp_coins);
    }

    public entry fun remove_liquidity<B, Q, F>(
        account: &signer,
        liquidity: u64,
        amt_base_min: u64,
        amt_quote_min: u64,
    ) {
        assert!(amm::pool_exist<B, Q, F>(), E_POOL_NOT_EXIST);
        let coins = coin::withdraw<LP<B, Q, F>>(account, liquidity);
        let (base_out, quote_out) = amm::burn<B, Q, F>(coins);

        assert!(coin::value(&base_out) >= amt_base_min, E_INSUFFICIENT_BASE_AMOUNT);
        assert!(coin::value(&quote_out) >= amt_quote_min, E_INSUFFICIENT_QUOTE_AMOUNT);

        // transfer
        let account_addr = address_of(account);
        coin::deposit(account_addr, base_out);
        coin::deposit(account_addr, quote_out);
    }

    // sell base
    public entry fun swap_base_for_exact_quote<B, Q, F>(
        account: &signer,
        amount_out: u64,
        amount_in_max: u64
        ) {
        let coin_in_needed = get_amount_in<B, Q, F>(amount_out, false);
        assert!(coin_in_needed <= amount_in_max, E_INSUFFICIENT_BASE_AMOUNT);
        let coin_in = coin::withdraw<B>(account, coin_in_needed);
        let coin_out;
        coin_out = swap_base_for_quote<B, Q, F>(coin_in, amount_out);
        utils::register_coin_if_not_exist<Q>(account);
        coin::deposit<Q>(address_of(account), coin_out);
    }

    // sell base
    public entry fun swap_exact_base_for_quote<B, Q, F>(
        account: &signer,
        amount_in: u64,
        amount_out_min: u64
        ) {
        let coin_in = coin::withdraw<B>(account, amount_in);
        let coin_out;
        coin_out = swap_base_for_quote<B, Q, F>(coin_in, amount_out_min);
        assert!(coin::value(&coin_out) >= amount_out_min, E_INSUFFICIENT_QUOTE_AMOUNT);
        utils::register_coin_if_not_exist<Q>(account);
        coin::deposit<Q>(address_of(account), coin_out);
    }

    // buy base
    public entry fun swap_quote_for_exact_base<B, Q, F>(
        account: &signer,
        amount_out: u64,
        amount_in_max: u64
        ) {
        let coin_in_needed = get_amount_in<B, Q, F>(amount_out, true);
        assert!(coin_in_needed <= amount_in_max, E_INSUFFICIENT_BASE_AMOUNT);
        let coin_in = coin::withdraw<Q>(account, coin_in_needed);
        let coin_out;
        coin_out = swap_quote_for_base<B, Q, F>(coin_in, amount_out);
        utils::register_coin_if_not_exist<B>(account);
        coin::deposit<B>(address_of(account), coin_out);
    }

    // buy base
    public entry fun swap_exact_quote_for_base<B, Q, F>(
        account: &signer,
        amount_in: u64,
        amount_out_min: u64
        ) {
        let coin_in = coin::withdraw<Q>(account, amount_in);
        let coin_out;
        coin_out = swap_quote_for_base<B, Q, F>(coin_in, amount_out_min);
        assert!(coin::value(&coin_out) >= amount_out_min, E_INSUFFICIENT_QUOTE_AMOUNT);
        utils::register_coin_if_not_exist<B>(account);
        coin::deposit<B>(address_of(account), coin_out);
    }

    public entry fun withdraw_dao_fee<B, Q, F>(
        account: &signer,
        to: address
    ) {
        assert!(address_of(account) == @sea, E_NO_AUTH);

        let amount = coin::balance<LP<B, Q, F>>(@sea_spot) - amm::get_min_liquidity();
        assert!(amount > 0, E_INSUFFICIENT_AMOUNT);
        coin::transfer<LP<B, Q, F>>(&escrow::get_spot_account(), to, amount);
    }

    // sell base, buy quote
    public fun swap_base_for_quote<B, Q, F>(
        coin_in: Coin<B>,
        coin_out_val: u64
    ): Coin<Q> {
        let (zero, coin_out) = amm::swap<B, Q, F>(coin_in, 0, coin::zero(), coin_out_val);
        coin::destroy_zero(zero);

        coin_out
    }

    // sell quote, buy base
    public fun swap_quote_for_base<B, Q, F>(
        coin_in: Coin<Q>,
        coin_out_val: u64,
    ): Coin<B> {
        let (coin_out, zero) = amm::swap<B, Q, F>(coin::zero(), coin_out_val, coin_in, 0);
        coin::destroy_zero(zero);

        coin_out
    }

    public fun get_amount_in<B, Q, F>(
        amount_out: u64,
        out_is_base: bool,
    ): u64 {
        assert!(amount_out > 0, E_INVALID_AMOUNT_OUT);
        let (base_reserve, quote_reserve, fee_ratio) = amm::get_pool_reserve_fee<B, Q, F>();
        assert!(base_reserve> 0 && quote_reserve > 0, E_INSUFFICIENT_LIQUIDITY);

        let numerator: u128;
        let denominator: u128;
        let fee_deno = fee::get_fee_denominate();
        if (out_is_base) {
            numerator = (base_reserve as u128) * (amount_out as u128) * (fee_deno as u128);
            denominator = ((quote_reserve - amount_out) as u128) * ((fee_deno - fee_ratio) as u128);
        } else {
            numerator = (quote_reserve as u128) * (amount_out as u128) * (fee_deno as u128);
            denominator = ((base_reserve - amount_out) as u128) * ((fee_deno - fee_ratio) as u128);
        };

        ((numerator / denominator + 1) as u64)
    }
}
