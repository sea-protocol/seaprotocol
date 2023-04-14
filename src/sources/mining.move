/// # Module-level documentation sections
///
/// * [Background](#Background)
/// * [Implementation](#Implementation)
/// * [Basic public functions](#Basic-public-functions)
/// * [Traversal](#Traversal)
///
/// # Background
///
/// trading is mining, for both traders and LPs
/// 
module sea::mining {
    use std::signer::address_of;
    use aptos_framework::timestamp;

    use sea::sea;

    // Friends ====================================================
    friend sea::market;
    friend sea::amm;

    // Structs ====================================================

    struct UserMintInfo has key {
        volume: u64,
        referer_addr: address,
    }

    struct MintInfo has key {
        enabled: bool,
        sea_per_second: u64, // SEA issued every second
        last_ts: u64,
        pool_sea: u64,
        total_volume: u64,
    }
 
    /// Errors ====================================================
    const E_MINT_DISABLED:      u64 = 900;
    const E_NOT_ENOUGH_SEA:     u64 = 901;

    fun init_module(
        sender: &signer,
    ) {
        assert!(address_of(sender) == @sea, 1);
    
        move_to(sender, MintInfo {
            enabled: false,
            sea_per_second: 0,
            last_ts: 0,
            pool_sea: 0,
            total_volume: 0,
        });
    }

    // Public functions ====================================================
    // user should initialize it's mint info
    public entry fun init_user_mint_info(
        account: &signer,
        referer_addr: address,
    ) {
        if (!exists<UserMintInfo>(address_of(account))) {
            move_to(account, UserMintInfo {
                volume: 0,
                referer_addr: referer_addr,
            });
        };
    }

    public fun claim_reward(
        account: &signer,
    ) acquires UserMintInfo, MintInfo {
        let pool_info = borrow_global_mut<MintInfo>(@sea);
        assert!(pool_info.enabled, E_MINT_DISABLED);

        update_pool_info(pool_info);
        let addr = address_of(account);
        let maker_info = borrow_global_mut<UserMintInfo>(addr);
        if (maker_info.volume == 0) {
            return
        };

        let reward = (((maker_info.volume as u128) * (pool_info.pool_sea as u128) / (pool_info.total_volume as u128)) as u64);
        assert!(reward <= pool_info.pool_sea, E_NOT_ENOUGH_SEA);
        sea::mint(account, reward);

        // mint referer reward if exists: 5%
        // mint dev team reward

        pool_info.total_volume = pool_info.total_volume - maker_info.volume;
        pool_info.pool_sea = pool_info.pool_sea - reward;
        maker_info.volume = 0;
    }

    public(friend) fun on_trade(
        taker_addr: address,
        maker_addr: address,
        vol: u64) acquires UserMintInfo, MintInfo {
        let pool_info = borrow_global_mut<MintInfo>(@sea);
        if (!pool_info.enabled) {
            return
        };

        if (exists<UserMintInfo>(maker_addr)) {
            let maker_info = borrow_global_mut<UserMintInfo>(maker_addr);
            maker_info.volume = maker_info.volume + vol;
            pool_info.total_volume = pool_info.total_volume + vol;
        };

        if (!exists<UserMintInfo>(taker_addr)) {
            return
        };
        let info = borrow_global_mut<UserMintInfo>(taker_addr);
        pool_info.total_volume = pool_info.total_volume + vol;
        info.volume = info.volume + vol;
    }

    public(friend) fun on_swap(
        taker: &signer,
        vol: u64) acquires UserMintInfo, MintInfo {
        let pool_info = borrow_global_mut<MintInfo>(@sea);
        if (!pool_info.enabled) {
            return
        };

        let addr = address_of(taker);
        pool_info.total_volume = pool_info.total_volume + vol;
        if (!exists<UserMintInfo>(addr)) {
            move_to(taker, UserMintInfo {
                volume: vol
            });
            return
        };
        let info = borrow_global_mut<UserMintInfo>(addr);
        info.volume = info.volume + vol;
    }

    // Admin functions ====================================================
    public entry fun configure_trade_mining(
        admin: &signer,
        enabled: bool,
        sea_per_second: u64,
    ) acquires MintInfo {
        assert!(address_of(admin) == @sea, 1);
        let pool_info = borrow_global_mut<MintInfo>(@sea);

        pool_info.enabled = enabled;
        pool_info.sea_per_second = sea_per_second;
        pool_info.last_ts = timestamp::now_seconds();
    }

    // Private functions ====================================================

    fun update_pool_info(
        pool: &mut MintInfo,
    ) {
        let ts = timestamp::now_seconds();
        if (ts > pool.last_ts) {
            pool.pool_sea = pool.pool_sea + (ts - pool.last_ts) * pool.sea_per_second;
            pool.last_ts = ts;
        }
    }
}
