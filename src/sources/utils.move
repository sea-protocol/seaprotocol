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
}
