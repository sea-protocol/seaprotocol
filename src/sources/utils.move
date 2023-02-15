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
module sea::utils {
    use std::signer::address_of;
    use aptos_framework::coin;

    /// When provided CoinType is not a coin.
    const E_IS_NOT_COIN: u64 = 3000;

    /// Check if provided generic `CoinType` is a coin.
    public fun assert_is_coin<CoinType>() {
        assert!(coin::is_coin_initialized<CoinType>(), E_IS_NOT_COIN);
    }

    public fun register_coin_if_not_exist<CoinType>(
        account: &signer
    ) {
        let account_addr = address_of(account);
        if (!coin::is_account_registered<CoinType>(account_addr)) {
            coin::register<CoinType>(account);
        }
    }
        
    // quote_qty = qty * price / price_ratio
    public fun calc_quote_qty(
        qty: u64,
        price: u64,
        price_ratio: u64,
    ): u64 {
        let quote_qty = ((qty as u128) * (price as u128)/(price_ratio as u128));
        
        (quote_qty as u64)
    }

    public fun calc_quote_qty_u128(
        qty: u128,
        price: u128,
        price_ratio: u128,
    ): u128 {
        (qty) * (price)/(price_ratio)
    }

    // base_qty = quote_qty * price_ratio / price
    public fun calc_base_qty(
        quote_qty: u64,
        price: u64,
        price_ratio: u64,
    ): u64 {
        (((quote_qty as u128) * (price_ratio as u128) / (price as u128)) as u64)
    }

}
