#[test_only]
module sea::test_env {
    use std::string;
    // use std::debug;
    use std::signer::address_of;
    
    use aptos_framework::coin;
    use aptos_framework::genesis;
    use aptos_framework::account;
    use aptos_framework::aptos_account;

    use sea::market;
    use sea::fee;
    use sea::amm;
    use sea::escrow;
    use sea::events;
    use sea::spot_account;

    /// coins
    struct T_BTC {}
    struct T_SEA {}
    struct T_ETH {}
    struct T_USDC {}
    struct T_USDT {}

    const T_USDC_DECIMALS: u8 = 6;
    const T_USDT_DECIMALS: u8 = 4;
    const T_BTC_DECIMALS:  u8 = 8;
    const T_SEA_DECIMALS:  u8 = 3;
    const T_ETH_DECIMALS:  u8 = 8;

    const T_USDC_AMT: u64 = 10000000*1000000; // 6 decimals
    const T_USDT_AMT: u64 = 10000000*10000; // 4 decimals
    const T_BTC_AMT: u64 = 100*100000000; // 8 decimals
    const T_SEA_AMT: u64 = 100000000*1000; // 3 decimals
    const T_ETH_AMT: u64 = 10000*100000000; // 8 decimals

    public fun create_test_coin<T>(
        sea_admin: &signer,
        name: vector<u8>,
        decimals: u8,
        user_a: &signer,
        user_b: &signer,
        user_c: &signer,
        user_d: &signer,
        amt_a: u64,
        amt_b: u64,
        amt_c: u64,
        amt_d: u64,
    ) {
        let (bc, fc, mc) = coin::initialize<T>(sea_admin,
            string::utf8(name),
            string::utf8(name),
            decimals,
            false);
        
        coin::register<T>(sea_admin);
        coin::register<T>(user_a);
        coin::register<T>(user_b);
        coin::register<T>(user_c);
        coin::register<T>(user_d);

        coin::deposit(address_of(user_a), coin::mint<T>(amt_a, &mc));
        coin::deposit(address_of(user_b), coin::mint<T>(amt_b, &mc));
        coin::deposit(address_of(user_c), coin::mint<T>(amt_c, &mc));
        coin::deposit(address_of(user_d), coin::mint<T>(amt_d, &mc));
        coin::destroy_burn_cap(bc);
        coin::destroy_freeze_cap(fc);
        coin::destroy_mint_cap(mc);
    }

    // before create quote, the coin should be registered
    public fun create_quote<Q>(
        sea_admin: &signer,
        min_notional: u64) {
        market::register_quote<Q>(sea_admin, min_notional);
    }

    // before create pairs, you should create quotes first
    public fun create_test_pairs<B, Q>(
        sea_admin: &signer,
        fee_level: u64,
        price_coefficient: u64,
        lot_size: u64,
        ) {
        market::register_pair<B, Q>(sea_admin, fee_level, price_coefficient, lot_size);
    }
    
    fun prepare_env(): signer {
        // account::create_account_for_test(@sea);
        genesis::setup();
        account::create_account_for_test(@sea_spot);
        let sea_admin = account::create_account_for_test(@sea);

        spot_account::initialize_spot_account(&sea_admin);
        events::initialize(&sea_admin);
        market::initialize(&sea_admin);
        escrow::initialize(&sea_admin);
        fee::initialize(&sea_admin);
        amm::initialize(&sea_admin);

        sea_admin
    }

    public fun create_test_env(
        user_a: &signer,
        user_b: &signer,
        user_c: &signer,
        user_d: &signer,
    ) {
        let sea_admin = prepare_env();

        aptos_account::create_account(address_of(user_a));
        aptos_account::create_account(address_of(user_b));
        aptos_account::create_account(address_of(user_c));
        aptos_account::create_account(address_of(user_d));

        create_test_coin<T_BTC>(&sea_admin, b"T_BTC", T_BTC_DECIMALS, user_a, user_b, user_c, user_d, T_BTC_AMT, T_BTC_AMT, T_BTC_AMT, T_BTC_AMT);
        create_test_coin<T_ETH>(&sea_admin, b"T_ETH", T_ETH_DECIMALS, user_a, user_b, user_c, user_d, T_ETH_AMT, T_ETH_AMT, T_ETH_AMT, T_ETH_AMT);
        create_test_coin<T_USDC>(&sea_admin, b"T_USDC", T_USDC_DECIMALS, user_a, user_b, user_c, user_d, T_USDC_AMT, T_USDC_AMT, T_USDC_AMT, T_USDC_AMT);
        create_test_coin<T_USDT>(&sea_admin, b"T_USDT", T_USDT_DECIMALS, user_a, user_b, user_c, user_d, T_USDT_AMT, T_USDT_AMT, T_USDT_AMT, T_USDT_AMT);
        create_test_coin<T_SEA>(&sea_admin, b"T_SEA", T_SEA_DECIMALS, user_a, user_b, user_c, user_d, T_SEA_AMT, T_SEA_AMT, T_SEA_AMT, T_SEA_AMT);

        // min_notional: 1 USDC
        create_quote<T_USDC>(&sea_admin, 1000000);
        // min: 1 USDT
        create_quote<T_USDT>(&sea_admin, 10000);
        // min: 0.0001
        create_quote<T_BTC>(&sea_admin, 10000);

        // create pair: BTC/USDC
        create_test_pairs<T_BTC, T_USDC>(&sea_admin, 500, 1000000000, 10000);  // lot_size sea: 0.00001
        create_test_pairs<T_BTC, T_USDT>(&sea_admin, 500, 1000000000, 10000); 
        create_test_pairs<T_ETH, T_USDC>(&sea_admin, 500, 1000000000, 100000); // lot_size eth: 0.001
        create_test_pairs<T_ETH, T_USDT>(&sea_admin, 500, 1000000000, 100000);
        create_test_pairs<T_ETH, T_BTC>(&sea_admin, 500, 1000000000, 1000);
        create_test_pairs<T_SEA, T_USDC>(&sea_admin, 500, 1000000000, 1000);  // lot_size sea: 0.001
        create_test_pairs<T_SEA, T_USDT>(&sea_admin, 500, 1000000000, 1000);
        create_test_pairs<T_SEA, T_BTC>(&sea_admin, 500, 1000000000, 1000);

        create_test_pairs<T_USDT, T_USDC>(&sea_admin, 500, 1000000000, 100); // lot_size: 0.01
    }
}
