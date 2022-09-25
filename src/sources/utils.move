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

    /// Check if provided generic `CoinType` is a coin.
    public fun assert_is_coin<CoinType>() {
        assert!(coin::is_coin_initialized<CoinType>(), E_IS_NOT_COIN);
    }
}
