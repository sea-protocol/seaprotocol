#[test_only]
module sea::test_router {
    use std::signer;
    // use std::debug;

    use aptos_framework::coin;

    use sea::router;
    // use sea::fee::FeeRatio500;
    use sea::test_env::{Self, T_BTC, T_USDC};
    use sea_spot::lp::{LP};

    const T_BTC_PRECISION:  u64 = 100000000;
    const T_USDC_PRECISION: u64 = 1000000;

    #[test_only]
    fun add_amm_liquidity<B, Q>(
        user: &signer,
        base_amt: u64,
        quote_amt: u64,
        slip: u64, // n/10000
    ): u64 {
        router::add_liquidity<B, Q>(
            user,
            base_amt,
            quote_amt,
            base_amt * (10000-slip) / 10000,
            quote_amt * (10000-slip) / 10000,
        );
        let account_addr = signer::address_of(user);
        let lp_balance = coin::balance<LP<B, Q>>(account_addr);
        // let base_balance = coin::balance<B>(account_addr);
        // let quote_balance = coin::balance<Q>(account_addr);

        // debug::print(&lp_balance);
        // debug::print(&base_balance);
        // debug::print(&quote_balance);
        // debug::print(&9999999999999999999);
        
        lp_balance
    }

    #[test_only]
    fun remove_amm_liquidity<B, Q>(
        user: &signer,
        amt: u64,
    ) {
        router::remove_liquidity<B, Q>(user, amt, 0, 0);
        // let account_addr = signer::address_of(user);
        // let lp_balance = coin::balance<LP<B, Q>>(account_addr);
        // let base_balance = coin::balance<B>(account_addr);
        // let quote_balance = coin::balance<Q>(account_addr);

        // debug::print(&lp_balance);
        // debug::print(&base_balance);
        // debug::print(&quote_balance);
        // debug::print(&9999999999999999999);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3,
        user4 = @user_4
    )]
    // #[expected_failure(abort_code = 5003)]
    #[expected_failure]
    public fun test_less_min_liquidity(
        user1: &signer,
        user2: &signer,
        user3: &signer,
        user4: &signer,
    ) {
        test_env::create_test_env(user1, user2, user3, user4);

        add_amm_liquidity<T_BTC, T_USDC>(
            user1,
            999,
            999,
            10,
        );
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3,
        user4 = @user_4
    )]
    public fun test_add_min_liquidity(
        user1: &signer,
        user2: &signer,
        user3: &signer,
        user4: &signer,
    ) {
        test_env::create_test_env(user1, user2, user3, user4);

        let lp = add_amm_liquidity<T_BTC, T_USDC>(
            user1,
            1001,
            1001,
            10,
        );
        assert!(lp == 1, 1);
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3,
        user4 = @user_4
    )]
    public fun test_add_liquidity(
        user1: &signer,
        user2: &signer,
        user3: &signer,
        user4: &signer,
    ) {
        test_env::create_test_env(user1, user2, user3, user4);

        add_amm_liquidity<T_BTC, T_USDC>(
            user1,
            1*T_BTC_PRECISION,
            10000*T_USDC_PRECISION,
            10,
        );
        add_amm_liquidity<T_BTC, T_USDC>(
            user2,
            2*T_BTC_PRECISION,
            20000*T_USDC_PRECISION,
            10,
        );
        add_amm_liquidity<T_BTC, T_USDC>(
            user3,
            3*T_BTC_PRECISION,
            30000*T_USDC_PRECISION,
            10,
        );
        add_amm_liquidity<T_BTC, T_USDC>(
            user4,
            T_BTC_PRECISION/10,
            1000*T_USDC_PRECISION,
            10,
        );
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3,
        user4 = @user_4
    )]
    public fun test_add_remove_liquidity(
        user1: &signer,
        user2: &signer,
        user3: &signer,
        user4: &signer,
    ) {
        test_env::create_test_env(user1, user2, user3, user4);

        let liq1 = add_amm_liquidity<T_BTC, T_USDC>(
            user1,
            1*T_BTC_PRECISION,
            10000*T_USDC_PRECISION,
            10,
        );
        remove_amm_liquidity<T_BTC, T_USDC>(user1, liq1);

        let liq2 = add_amm_liquidity<T_BTC, T_USDC>(
            user2,
            2*T_BTC_PRECISION,
            20000*T_USDC_PRECISION,
            10,
        );
        remove_amm_liquidity<T_BTC, T_USDC>(user2, liq2);

        let liq3 = add_amm_liquidity<T_BTC, T_USDC>(
            user3,
            3*T_BTC_PRECISION,
            30000*T_USDC_PRECISION,
            10,
        );
        remove_amm_liquidity<T_BTC, T_USDC>(user3, liq3);

        let liq4 = add_amm_liquidity<T_BTC, T_USDC>(
            user4,
            T_BTC_PRECISION/10,
            1000*T_USDC_PRECISION,
            10,
        );
        remove_amm_liquidity<T_BTC, T_USDC>(user4, liq4);
    }

    // quote_out linear quote out
    #[test_only]
    fun test_sell_exact_base<B, Q>(
        user: &signer,
        base_in: u64,
        quote_out: u64
    ) {
        let amt_out = router::get_amount_out<B, Q>(base_in, true);
        quote_out;
        // debug::print(&amt_out);
        // debug::print(&quote_out);
        // debug::print(&100000000000000001);
        router::sell_exact_base<T_BTC, T_USDC>(
            user,
            base_in,
            amt_out
        );
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3,
        user4 = @user_4
    )]
    public fun test_amm_sell_exact_base_e2e(
        user1: &signer,
        user2: &signer,
        user3: &signer,
        user4: &signer,
    ) {
        test_env::create_test_env(user1, user2, user3, user4);

        add_amm_liquidity<T_BTC, T_USDC>(
            user1,
            1*T_BTC_PRECISION,
            10000*T_USDC_PRECISION,
            10,
        );

        test_sell_exact_base<T_BTC, T_USDC>(
            user2,
            1*T_BTC_PRECISION/100,
            100*T_USDC_PRECISION
        );
    }

    #[test_only]
    fun test_sell_exact_quote<B, Q>(
        user: &signer,
        quote_in: u64,
        base_out: u64
    ) {
        let amt_out = router::get_amount_out<B, Q>(quote_in, false);
        base_out;
        // debug::print(&amt_out);
        // debug::print(&base_out);
        // debug::print(&100000000000000002);
        router::sell_exact_quote<T_BTC, T_USDC>(
            user,
            quote_in,
            amt_out
        );
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3,
        user4 = @user_4
    )]
    public fun test_amm_swap_exact_quote_e2e(
        user1: &signer,
        user2: &signer,
        user3: &signer,
        user4: &signer,
    ) {
        test_env::create_test_env(user1, user2, user3, user4);

        add_amm_liquidity<T_BTC, T_USDC>(
            user1,
            1*T_BTC_PRECISION,
            10000*T_USDC_PRECISION,
            10,
        );

        test_sell_exact_quote<T_BTC, T_USDC>(
            user2,
            100*T_USDC_PRECISION,
            1*T_BTC_PRECISION/100,
        );
    }

    #[test_only]
    fun test_buy_exact_quote<B, Q>(
        user: &signer,
        quote_out: u64,
        base_in: u64
    ) {
        let amt_in = router::get_amount_in<B, Q>(quote_out, false);
        base_in;
        // debug::print(&amt_in);
        // debug::print(&base_in);
        // debug::print(&100000000000000003);
        router::buy_exact_quote<T_BTC, T_USDC>(
            user,
            quote_out,
            amt_in
        );
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3,
        user4 = @user_4
    )]
    public fun test_amm_buy_exact_quote_e2e(
        user1: &signer,
        user2: &signer,
        user3: &signer,
        user4: &signer,
    ) {
        test_env::create_test_env(user1, user2, user3, user4);

        add_amm_liquidity<T_BTC, T_USDC>(
            user1,
            1*T_BTC_PRECISION,
            10000*T_USDC_PRECISION,
            10,
        );

        test_buy_exact_quote<T_BTC, T_USDC>(
            user2,
            100*T_USDC_PRECISION,
            1*T_BTC_PRECISION/100,
        );
    }

    #[test_only]
    fun test_buy_exact_base<B, Q>(
        user: &signer,
        quote_out: u64,
        base_in: u64
    ) {
        let amt_in = router::get_amount_in<B, Q>(quote_out, true);
        base_in;
        // debug::print(&amt_in);
        // debug::print(&base_in);
        // debug::print(&100000000000000003);
        router::buy_exact_base<T_BTC, T_USDC>(
            user,
            quote_out,
            amt_in
        );
    }

    #[test(
        user1 = @user_1,
        user2 = @user_2,
        user3 = @user_3,
        user4 = @user_4
    )]
    public fun test_amm_buy_exact_base_e2e(
        user1: &signer,
        user2: &signer,
        user3: &signer,
        user4: &signer,
    ) {
        test_env::create_test_env(user1, user2, user3, user4);

        add_amm_liquidity<T_BTC, T_USDC>(
            user1,
            1*T_BTC_PRECISION,
            10000*T_USDC_PRECISION,
            10,
        );

        test_buy_exact_base<T_BTC, T_USDC>(
            user2,
            1*T_BTC_PRECISION/100,
            100*T_USDC_PRECISION,
        );
    }
}
