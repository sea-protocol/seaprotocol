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
    use aptos_framework::coin;

    /// When provided CoinType is not a coin.
    const E_IS_NOT_COIN: u64 = 3000;

    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    /// Check if provided generic `CoinType` is a coin.
    public fun assert_is_coin<CoinType>() {
        assert!(coin::is_coin_initialized<CoinType>(), E_IS_NOT_COIN);
    }
    
    // Check if mul maybe overflow
    // The result maybe false positive
    public fun is_overflow_mul(a: u128, b: u128): bool {
        MAX_U128 / b <= a
    }
}
