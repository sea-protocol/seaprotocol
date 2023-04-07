/// # Module-level documentation sections
///
/// * [Background](#Background)
/// * [Implementation](#Implementation)
/// * [Basic public functions](#Basic-public-functions)
/// * [Traversal](#Traversal)
///
/// # Background
///
/// AMM
/// 
module sea::amm {
    use std::option;
    use std::signer::address_of;
    use std::string::{Self, String};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use aptos_framework::account;

    use sealib::u256;
    use sealib::uq64x64;

    use sealib::math;
    
    use sea::fee;
    use sea::escrow;
    use sea_spot::lp::{LP};

    // Friends >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    friend sea::market;

    // Constants ====================================================
    const MIN_LIQUIDITY: u64 = 1000;

    // Errors ====================================================
    const E_NO_AUTH:                       u64 = 5000;
    const E_INITIALIZED:                   u64 = 5001;
    const E_POOL_LOCKED:                   u64 = 5002;
    const E_MIN_LIQUIDITY:                 u64 = 5003;
    const E_INSUFFICIENT_LIQUIDITY_BURNED: u64 = 5004;
    const E_INSUFFICIENT_INPUT_AMOUNT:     u64 = 5005;
    const E_INSUFFICIENT_OUTPUT_AMOUNT:    u64 = 5006;
    const ERR_K_ERROR:                     u64 = 5007;
    const E_INVALID_LOAN_PARAM:            u64 = 5008;
    const E_INSUFFICIENT_AMOUNT:           u64 = 5009;
    const E_PAY_LOAN_ERROR:                u64 = 5010;
    const E_INSUFFICIENT_BASE_AMOUNT:      u64 = 5011;
    const E_INSUFFICIENT_QUOTE_AMOUNT:     u64 = 5012;
    const E_INTERNAL_ERROR:                u64 = 5013;
    const E_AMM_LOCKED:                    u64 = 5014;
    const E_INVALID_DAO_FEE:               u64 = 5015;
    const E_POOL_EXISTS:                   u64 = 5016;

    // Events ====================================================
    struct EventSwap has store, drop {
        base_in: u64,
        quote_in: u64,
        base_out: u64,
        quote_out: u64,
        pair_id: u64,
        fee_ratio: u64,
        base_reserve: u64,
        quote_reserve: u64,
        k_last: u128,
        timestamp: u64,
    }

    struct EventPoolUpdated has store, drop {
        pair_id: u64,
        base_reserve: u64,
        quote_reserve: u64,
        last_price_x_cumulative: u128,
        last_price_y_cumulative: u128,
        k_last: u128,
        timestamp: u64,
    }

    // Pool liquidity pool
    struct Pool<phantom BaseType, phantom QuoteType> has key {
        base_id: u64,
        quote_id: u64,
        pair_id: u64,
        base_reserve: Coin<BaseType>,
        quote_reserve: Coin<QuoteType>,
        last_timestamp: u64,
        last_price_x_cumulative: u128,
        last_price_y_cumulative: u128,
        k_last: u128,
        lp_mint_cap: coin::MintCapability<LP<BaseType, QuoteType>>,
        lp_burn_cap: coin::BurnCapability<LP<BaseType, QuoteType>>,
        locked: bool,
        fee_ratio: u64,
        mining_weight: u64,
        event_swap: event::EventHandle<EventSwap>,
        event_pool_updated: event::EventHandle<EventPoolUpdated>,
    }

    // AMMConfig global AMM config
    struct AMMConfig has key {
        dao_fee: u64, // DAO will take 1/dao_fee from trade fee
        locked: bool,
    }

    // Flashloan flash loan
    struct Flashloan<phantom BaseType, phantom QuoteType> {
        x_loan: u64,
        y_loan: u64,
    }

    // initialize
    fun init_module(sea_admin: &signer) {
        initialize(sea_admin);
    }

    public fun initialize(sea_admin: &signer) {
        // init amm config
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);
        assert!(!exists<AMMConfig>(address_of(sea_admin)), E_INITIALIZED);
        // let signer_cap = spot_account::retrieve_signer_cap(sea_admin);
        // move_to(sea_admin, SpotAccountCapability { signer_cap });
        move_to(sea_admin, AMMConfig {
            dao_fee: 10, // 1/10
            locked: false,
        });
    }

    public entry fun set_market_locked(
        sea_admin: &signer,
        locked: bool,
    ) acquires AMMConfig {
        // init amm config
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);
        let ac = borrow_global_mut<AMMConfig>(@sea);

        ac.locked = locked
    }

    public entry fun set_market_dao_fee(
        sea_admin: &signer,
        dao_fee: u64,
    ) acquires AMMConfig {
        // init amm config
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);
        assert!(dao_fee < 50, E_INVALID_DAO_FEE);
        let ac = borrow_global_mut<AMMConfig>(@sea);

        ac.dao_fee = dao_fee
    }

    // create_pool should be called by spot register_pair
    public(friend) fun create_pool<B, Q>(
        res_account: &signer,
        base_id: u64,
        quote_id: u64,
        pair_id: u64,
        fee_ratio: u64,
    ) {
        let (name, symbol) = get_lp_name_symbol<B, Q>();
        let (lp_burn_cap, lp_freeze_cap, lp_mint_cap) =
            coin::initialize<LP<B, Q>>(
                res_account,
                name,
                symbol,
                6,
                true
            );
        coin::destroy_freeze_cap(lp_freeze_cap);

        assert!(!exists<Pool<B, Q>>(address_of(res_account)), E_POOL_EXISTS);
        let pool = Pool<B, Q> {
            base_id: base_id,
            quote_id: quote_id,
            pair_id: pair_id,
            base_reserve: coin::zero<B>(),
            quote_reserve: coin::zero<Q>(),
            last_timestamp: 0,
            last_price_x_cumulative: 0,
            last_price_y_cumulative: 0,
            k_last: 0,
            lp_mint_cap,
            lp_burn_cap,
            locked: false,
            fee_ratio: fee_ratio,
            mining_weight: 0,

            event_swap: account::new_event_handle<EventSwap>(res_account),
            event_pool_updated: account::new_event_handle<EventPoolUpdated>(res_account),
        };
        move_to(res_account, pool);
        coin::register<LP<B, Q>>(res_account);
    }

    public entry fun modify_pool_fee<B, Q>(
        sea_admin: &signer,
        fee_level: u64) acquires Pool {
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);
        fee::assert_fee_level_valid(fee_level);
        let pool = borrow_global_mut<Pool<B, Q>>(@sea_spot);

        pool.fee_ratio = fee_level;
    }

    public entry fun set_pool_weight<B, Q>(
        sea_admin: &signer,
        weight: u64) acquires Pool {
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);

        let pool = borrow_global_mut<Pool<B, Q>>(@sea_spot);

        pool.mining_weight = weight;
    }

    public fun get_min_liquidity(): u64 {
        MIN_LIQUIDITY
    }
    
    public fun pool_exist<B, Q>(): bool {
        exists<Pool<B, Q>>(@sea_spot)
    }

    public fun mint<B, Q>(
        base: Coin<B>,
        quote: Coin<Q>,
    ): Coin<LP<B, Q>> acquires Pool, AMMConfig {
        assert_amm_unlocked();
        escrow::validate_pair<B, Q>();
        let pool = borrow_global_mut<Pool<B, Q>>(@sea_spot);
        assert!(pool.locked == false, E_POOL_LOCKED);

        mint_fee<B, Q>(pool);

        let total_supply = option::extract(&mut coin::supply<LP<B, Q>>());
        let base_reserve = coin::value(&pool.base_reserve);
        let quote_reserve = coin::value(&pool.quote_reserve);
        let base_vol = coin::value(&base);
        let quote_vol = coin::value(&quote);
        let liquidity: u64;
        if (total_supply == 0) {
            liquidity = math::sqrt((base_vol as u128) * (quote_vol as u128));
            assert!(liquidity > MIN_LIQUIDITY, E_MIN_LIQUIDITY);
            liquidity = liquidity - MIN_LIQUIDITY;
        } else {
            let x_liq = (((base_vol as u128) * total_supply / (base_reserve as u128)) as u64);
            let y_liq = (((quote_vol as u128) * total_supply / (quote_reserve as u128)) as u64);
            liquidity = math::min_u64(x_liq, y_liq);
        };
        assert!(liquidity > 0, E_MIN_LIQUIDITY);

        coin::merge(&mut pool.base_reserve, base);
        coin::merge(&mut pool.quote_reserve, quote);

        let lp = coin::mint<LP<B, Q>>(liquidity, &pool.lp_mint_cap);
        update_pool(pool, base_reserve, quote_reserve);
        // here should update k_last to last reserve
        pool.k_last = (coin::value(&pool.base_reserve) as u128) * (coin::value(&pool.quote_reserve) as u128);

        lp
    }

    public fun burn<B, Q>(
        lp: Coin<LP<B, Q>>,
    ): (Coin<B>, Coin<Q>) acquires Pool, AMMConfig {
        assert_amm_unlocked();
        escrow::validate_pair<B, Q>();
        let pool = borrow_global_mut<Pool<B, Q>>(@sea_spot);
        assert!(pool.locked == false, E_POOL_LOCKED);
        let burn_vol = coin::value(&lp);

        mint_fee<B, Q>(pool);

        let total_supply = option::extract(&mut coin::supply<LP<B, Q>>());
        let base_reserve = coin::value(&pool.base_reserve);
        let quote_reserve = coin::value(&pool.quote_reserve);

        // debug::print(&total_supply);
        // debug::print(&base_reserve);
        // debug::print(&quote_reserve);

        // how much base and quote to be returned
        let base_to_return_val = (((burn_vol as u128) * (base_reserve as u128) / total_supply) as u64);
        let quote_to_return_val = (((burn_vol as u128) * (quote_reserve as u128) / total_supply) as u64);
        assert!(base_to_return_val > 0 && quote_to_return_val > 0, E_INSUFFICIENT_LIQUIDITY_BURNED);

        // Withdraw those values from reserves
        let base_coin_to_return = coin::extract(&mut pool.base_reserve, base_to_return_val);
        let quote_coin_to_return = coin::extract(&mut pool.quote_reserve, quote_to_return_val);

        update_pool<B, Q>(pool, base_reserve, quote_reserve);
        pool.k_last = (base_reserve as u128) * (quote_reserve as u128);
        coin::burn(lp, &pool.lp_burn_cap);

        (base_coin_to_return, quote_coin_to_return)
    }

    public fun swap<B, Q>(
        base_in: Coin<B>,
        base_out: u64,
        quote_in: Coin<Q>,
        quote_out: u64,
    ): (Coin<B>, Coin<Q>) acquires Pool, AMMConfig {
        assert_amm_unlocked();
        escrow::validate_pair<B, Q>();
        let pool = borrow_global_mut<Pool<B, Q>>(@sea_spot);
        assert!(pool.locked == false, E_POOL_LOCKED);
        assert!(base_out > 0 || quote_out > 0, E_INSUFFICIENT_OUTPUT_AMOUNT);

        let base_in_vol = coin::value(&base_in);
        let quote_in_vol = coin::value(&quote_in);
        assert!(base_in_vol > 0 || quote_in_vol > 0, E_INSUFFICIENT_INPUT_AMOUNT);

        let base_reserve = coin::value(&pool.base_reserve);
        let quote_reserve = coin::value(&pool.quote_reserve);

        // Deposit new coins to liquidity pool.
        coin::merge(&mut pool.base_reserve, base_in);
        coin::merge(&mut pool.quote_reserve, quote_in);

        let base_swaped = coin::extract(&mut pool.base_reserve, base_out);
        let quote_swaped = coin::extract(&mut pool.quote_reserve, quote_out);

        let base_balance = coin::value(&mut pool.base_reserve);
        let quote_balance = coin::value(&mut pool.quote_reserve);

        assert_k_increase(base_balance, quote_balance, base_in_vol, quote_in_vol, base_reserve, quote_reserve, pool.fee_ratio);

        update_pool(pool, base_reserve, quote_reserve);

        // emit event
        event::emit_event<EventSwap>(&mut pool.event_swap, EventSwap{
                    base_in: base_in_vol,
                    quote_in: quote_in_vol,
                    base_out: base_out,
                    quote_out: quote_out,
                    pair_id: pool.pair_id,
                    fee_ratio: pool.fee_ratio,
                    base_reserve: base_reserve,
                    quote_reserve: quote_reserve,
                    k_last: pool.k_last,
                    timestamp: timestamp::now_seconds(),
                });

        (base_swaped, quote_swaped)
    }

    /// Calculate optimal amounts of coins to add
    public fun calc_optimal_coin_values<B, Q>(
        amount_base_desired: u64,
        amount_quote_desired: u64,
        amount_base_min: u64,
        amount_quote_min: u64
    ): (u64, u64) acquires Pool {
        let pool = borrow_global<Pool<B, Q>>(@sea_spot);
        let (reserve_base, reserve_quote) = (coin::value(&pool.base_reserve), coin::value(&pool.quote_reserve));
        if (reserve_base == 0 && reserve_quote == 0) {
            (amount_base_desired, amount_quote_desired)
        } else {
            let amount_quote_optimal = quote(amount_base_desired, reserve_base, reserve_quote);
            if (amount_quote_optimal <= amount_quote_desired) {
                assert!(amount_quote_optimal >= amount_quote_min, E_INSUFFICIENT_QUOTE_AMOUNT);
                (amount_base_desired, amount_quote_optimal)
            } else {
                let amount_base_optimal = quote(amount_quote_desired, reserve_quote, reserve_base);
                assert!(amount_base_optimal <= amount_base_desired, E_INTERNAL_ERROR);
                assert!(amount_base_optimal >= amount_base_min, E_INSUFFICIENT_BASE_AMOUNT);
                (amount_base_optimal, amount_quote_desired)
            }
        }
    }
    
    // Get flash swap coins. User can loan any coins, and repay in the same tx.
    // In most cases, user may loan one coin, and repay the same or the other coin.
    // require X < Y.
    // * `loan_coin_x` - expected amount of X coins to loan.
    // * `loan_coin_y` - expected amount of Y coins to loan.
    // Returns both loaned X and Y coins: `(Coin<XBaseType>, Coin<QuoteType>, Flashloan<BaseType, QuoteType)`.
    public fun flash_swap<B, Q>(
        loan_coin_x: u64,
        loan_coin_y: u64
    ): (Coin<B>, Coin<Q>, Flashloan<B, Q>) acquires Pool {
        // assert check
        escrow::validate_pair<B, Q>();
        assert!(loan_coin_x > 0 || loan_coin_y > 0, E_INVALID_LOAN_PARAM);

        let pool = borrow_global_mut<Pool<B, Q>>(@sea_spot);
        assert!(pool.locked == false, E_POOL_LOCKED);
        assert!(coin::value(&pool.base_reserve) >= loan_coin_x &&
            coin::value(&pool.quote_reserve) >= loan_coin_y, E_INSUFFICIENT_AMOUNT);
        pool.locked = true;

        let x_loan = coin::extract(&mut pool.base_reserve, loan_coin_x);
        let y_loan = coin::extract(&mut pool.quote_reserve, loan_coin_y);

        // Return loaned amount.
        (x_loan, y_loan, Flashloan<B, Q> {x_loan: loan_coin_x, y_loan: loan_coin_y})
    }

    public fun pay_flash_swap<B, Q>(
        base_in: Coin<B>,
        quote_in: Coin<Q>,
        flash_loan: Flashloan<B, Q>
    ) acquires Pool {
        // assert check
        escrow::validate_pair<B, Q>();

        let Flashloan { x_loan, y_loan } = flash_loan;
        let amount_base_in = coin::value(&base_in);
        let amount_quote_in = coin::value(&quote_in);

        assert!(amount_base_in > 0 || amount_quote_in > 0, E_PAY_LOAN_ERROR);

        let pool = borrow_global_mut<Pool<B, Q>>(@sea_spot);
        let base_reserve = coin::value(&pool.base_reserve);
        let quote_reserve = coin::value(&pool.quote_reserve);

        // reserve size before loan out
        base_reserve = base_reserve + x_loan;
        quote_reserve = quote_reserve + y_loan;

        coin::merge(&mut pool.base_reserve, base_in);
        coin::merge(&mut pool.quote_reserve, quote_in);

        let base_balance = coin::value(&pool.base_reserve);
        let quote_balance = coin::value(&pool.quote_reserve);
        assert_k_increase(base_balance, quote_balance, amount_base_in, amount_quote_in, base_reserve, quote_reserve, pool.fee_ratio);
        // update internal
        update_pool(pool, base_reserve, quote_reserve);

        pool.locked = false;
    }

    public fun get_pool_reserve_fee<B, Q>(): (u64, u64, u64) acquires Pool {
        let pool = borrow_global_mut<Pool<B, Q>>(@sea_spot);
        assert!(pool.locked == false, E_POOL_LOCKED);
        let base_reserve = coin::value(&pool.base_reserve);
        let quote_reserve = coin::value(&pool.quote_reserve);

        (base_reserve, quote_reserve, pool.fee_ratio)
    }

    public fun get_pool_reserve_fee_u128<B, Q>(): (u128, u128, u128) acquires Pool {
        let pool = borrow_global_mut<Pool<B, Q>>(@sea_spot);
        assert!(pool.locked == false, E_POOL_LOCKED);
        let base_reserve = coin::value(&pool.base_reserve);
        let quote_reserve = coin::value(&pool.quote_reserve);

        ((base_reserve as u128), (quote_reserve as u128), (pool.fee_ratio as u128))
    }

    // Private functions ====================================================

    fun assert_amm_unlocked() acquires AMMConfig {
        let ac = borrow_global<AMMConfig>(@sea);
        assert!(ac.locked == false, E_AMM_LOCKED);
    }

    // k should not decrease
    fun assert_k_increase(
        base_balance: u64,
        quote_balance: u64,
        base_in: u64,
        quote_in: u64,
        base_reserve: u64,
        quote_reserve: u64,
        fee: u64,
    ) {
        let fee_deno = (fee::get_fee_denominate() as u128);
        // debug::print(&fee_deno);
        let base_balance_adjusted = (base_balance as u128) * fee_deno - (base_in as u128) * (fee as u128);
        let quote_balance_adjusted = (quote_balance as u128) * fee_deno - (quote_in as u128) * (fee as u128);
        let balance_k_old_not_scaled = (base_reserve as u128) * (quote_reserve as u128);
        let scale = fee_deno * fee_deno;

        // should be: new_reserve_x * new_reserve_y > old_reserve_x * old_eserve_y
        // gas saving
        if (
            math::is_overflow_mul(base_balance_adjusted, quote_balance_adjusted)
            || math::is_overflow_mul(balance_k_old_not_scaled, scale)
        ) {
            let balance_xy_adjusted = u256::mul(u256::from_u128(base_balance_adjusted), u256::from_u128(quote_balance_adjusted));
            let balance_xy_old = u256::mul(u256::from_u128(balance_k_old_not_scaled), u256::from_u128(scale));
            assert!(u256::compare(&balance_xy_adjusted, &balance_xy_old) == 2, ERR_K_ERROR);
        } else {
            assert!(base_balance_adjusted * quote_balance_adjusted >= balance_k_old_not_scaled * scale, ERR_K_ERROR)
        };
    }

    fun quote(
        amount_base: u64,
        reserve_base: u64,
        reserve_quote: u64
    ): u64 {
        assert!(amount_base > 0, E_INSUFFICIENT_AMOUNT);
        assert!(reserve_base > 0 && reserve_quote > 0, E_INSUFFICIENT_AMOUNT);
        ((amount_base as u128) * (reserve_quote as u128) / (reserve_base as u128) as u64)
    }

    fun get_lp_name_symbol<BaseType, QuoteType>(): (String, String) {
        let name = string::utf8(b"LP-");
        string::append(&mut name, coin::symbol<BaseType>());
        string::append_utf8(&mut name, b"-");
        string::append(&mut name, coin::symbol<QuoteType>());

        let symbol = string::utf8(b"");
        string::append(&mut symbol, coin_symbol_prefix<BaseType>());
        string::append_utf8(&mut symbol, b"-");
        string::append(&mut symbol, coin_symbol_prefix<QuoteType>());

        (name, symbol)
    }

    fun coin_symbol_prefix<CoinType>(): String {
        let symbol = coin::symbol<CoinType>();
        let prefix_length = math::min_u64(string::length(&symbol), 4);
        string::sub_string(&symbol, 0, prefix_length)
    }

    fun update_pool<B, Q>(
        pool: &mut Pool<B, Q>,
        base_reserve: u64,
        quote_reserve: u64,
    ) {
        let last_ts = pool.last_timestamp;
        let now_ts = timestamp::now_seconds();

        let time_elapsed = ((now_ts - last_ts) as u128);

        if (time_elapsed > 0 && base_reserve != 0 && quote_reserve != 0) {
            let last_price_x_cumulative = uq64x64::to_u128(uq64x64::fraction(quote_reserve, base_reserve)) * time_elapsed;
            let last_price_y_cumulative = uq64x64::to_u128(uq64x64::fraction(base_reserve, quote_reserve)) * time_elapsed;

            pool.last_price_x_cumulative = pool.last_price_x_cumulative + last_price_x_cumulative;
            pool.last_price_y_cumulative = pool.last_price_y_cumulative + last_price_y_cumulative;
        };

        pool.last_timestamp = now_ts;
        event::emit_event<EventPoolUpdated>(&mut pool.event_pool_updated, EventPoolUpdated{
                    pair_id: pool.pair_id,
                    base_reserve: coin::value(&pool.base_reserve),
                    quote_reserve: coin::value(&pool.quote_reserve),
                    last_price_x_cumulative: pool.last_price_x_cumulative,
                    last_price_y_cumulative: pool.last_price_y_cumulative,
                    k_last: pool.k_last,
                    timestamp: now_ts,
                });
    }

    fun mint_fee<B, Q>(
        pool: &mut Pool<B, Q>,
    ) acquires AMMConfig {
        let dao_fee = (borrow_global<AMMConfig>(@sea).dao_fee as u128);
        let k_last = pool.k_last;
        let base_reserve = coin::value(&pool.base_reserve);
        let quote_reserve = coin::value(&pool.quote_reserve);

        if (k_last != 0) {
            let root_k = math::sqrt_u128((base_reserve as u128) * (quote_reserve as u128));
            let root_k_last = math::sqrt_u128(k_last);
            let total_supply = option::extract(&mut coin::supply<LP<B, Q>>());
            if (root_k > root_k_last) {
                let delta_k = (root_k - root_k_last);
                let liquidity;
                if (math::is_overflow_mul(total_supply, delta_k)) {
                    let numerator = u256::mul(u256::from_u128(total_supply), u256::from_u128(delta_k));
                    let denominator = u256::from_u128(root_k * dao_fee + root_k_last);
                    liquidity = u256::as_u64(u256::div(numerator, denominator));
                } else {
                    let numerator = total_supply * delta_k;
                    let denominator = root_k * dao_fee + root_k_last;
                    liquidity = ((numerator / denominator) as u64);
                };
                if (liquidity > 0) {
                    let coins = coin::mint<LP<B, Q>>(liquidity, &pool.lp_mint_cap);
                    coin::deposit(@sea_spot, coins);
                }
            }
        };
        pool.k_last = (base_reserve as u128) * (quote_reserve as u128);
    }

    // Test-only functions ====================================================
    // Tests ==================================================================
}
