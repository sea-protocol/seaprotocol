module sea::mock_coins {
    use std::signer;
    use std::string;
    
    use aptos_framework::simple_map::{Self, SimpleMap};
    use aptos_framework::coin;

    /// coins
    struct BTC {}
    struct SEA {}
    struct ETH {}
    struct USDC {}
    struct USDT {}

    const T_USDC_DECIMALS: u8 = 6;
    const T_USDT_DECIMALS: u8 = 4;
    const T_BTC_DECIMALS:  u8 = 8;
    const T_SEA_DECIMALS:  u8 = 4;
    const T_ETH_DECIMALS:  u8 = 8;

    /// faucet amount
    const T_USDC_AMT: u64 = 10000*1000000; // 6 decimals
    const T_USDT_AMT: u64 = 10000*10000;   // 4 decimals
    const T_BTC_AMT: u64 = 1*100000000;    // 8 decimals
    const T_SEA_AMT: u64 = 100000*10000;   // 4 decimals
    const T_ETH_AMT: u64 = 100*100000000;  // 8 decimals

    struct FaucetAccounts has key {
        claimed_accounts: SimpleMap<address, bool>,
        btc_mint_cap: coin::MintCapability<BTC>,
        sea_mint_cap: coin::MintCapability<SEA>,
        eth_mint_cap: coin::MintCapability<ETH>,
        usdc_mint_cap: coin::MintCapability<USDC>,
        usdt_mint_cap: coin::MintCapability<USDT>,
    }

    fun init_module(
        sea_admin: &signer
    ) {
        let btc_cap = create_coin<BTC>(sea_admin, b"BTC", T_BTC_DECIMALS);
        let sea_cap = create_coin<SEA>(sea_admin, b"SEA", T_SEA_DECIMALS);
        let eth_cap = create_coin<ETH>(sea_admin, b"ETH", T_ETH_DECIMALS);
        let usdc_cap = create_coin<USDC>(sea_admin, b"USDC", T_USDC_DECIMALS);
        let usdt_cap = create_coin<USDT>(sea_admin, b"USDT", T_USDT_DECIMALS);
        
        move_to(sea_admin,
                FaucetAccounts {
                    claimed_accounts: simple_map::create(),
                    btc_mint_cap: btc_cap,
                    sea_mint_cap: sea_cap,
                    eth_mint_cap: eth_cap,
                    usdc_mint_cap: usdc_cap,
                    usdt_mint_cap: usdt_cap,
                });
    }

    fun create_coin<CoinType>(
        sea_admin: &signer,
        name: vector<u8>,
        decimals: u8,
        ): coin::MintCapability<CoinType> {
        let (bc, fc, mc) = coin::initialize<CoinType>(sea_admin,
            string::utf8(name),
            string::utf8(name),
            decimals,
            false);
        
        coin::destroy_burn_cap(bc);
        coin::destroy_freeze_cap(fc);

        mc
    }

    public entry fun claim_faucet(
        account: &signer,
    ) acquires FaucetAccounts {
        let fc = borrow_global_mut<FaucetAccounts>(@sea);
        let addr = signer::address_of(account);

        assert!(!simple_map::contains_key(&fc.claimed_accounts, &addr), 0x1);
        simple_map::add(&mut fc.claimed_accounts, addr, true);

        mint_faucet_to<BTC>(account, &fc.btc_mint_cap, T_BTC_AMT);
        mint_faucet_to<SEA>(account, &fc.sea_mint_cap, T_SEA_AMT);
        mint_faucet_to<ETH>(account, &fc.eth_mint_cap, T_ETH_AMT);
        mint_faucet_to<USDC>(account, &fc.usdc_mint_cap, T_USDC_AMT);
        mint_faucet_to<USDT>(account, &fc.usdt_mint_cap, T_USDT_AMT);
    }

    fun mint_faucet_to<CoinType>(
        account: &signer,
        mint_cap: &coin::MintCapability<CoinType>,
        amount: u64,
    ) {
        let addr = signer::address_of(account);

        coin::register<CoinType>(account);
        coin::deposit(addr, coin::mint<CoinType>(amount, mint_cap));
    }
}
