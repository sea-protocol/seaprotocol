/// # Module-level documentation sections
///
/// * [Background](#Background)
/// * [Implementation](#Implementation)
/// * [Basic public functions](#Basic-public-functions)
/// * [Traversal](#Traversal)
///
/// # Background
///
/// SEA token
/// 
module sea::sea {
    use std::string;
    use std::signer::address_of;
    use aptos_framework::coin::{Self, BurnCapability, MintCapability};

    use sea::utils;

    struct SEA {}
    
    const E_NO_AUTH: u64 = 1;

    // Friends >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    friend sea::mining;

    /// Capabilities resource storing mint and burn capabilities.
    /// The resource is stored on the account that initialized coin `CoinType`.
    struct Capabilities<phantom CoinType> has key {
        // owner: address,
        burn_cap: BurnCapability<CoinType>,
        // freeze_cap: FreezeCapability<CoinType>,
        mint_cap: MintCapability<CoinType>,
    }

    fun init_module(
        sender: &signer,
    ) {
        assert!(address_of(sender) == @sea, 1);

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<SEA>(
            sender,
            string::utf8(b"SEA"),
            string::utf8(b"SEA"),
            6,
            true,
        );
        coin::destroy_freeze_cap(freeze_cap);
        move_to(sender, Capabilities<SEA> {
            // owner: address_of(sender),
            burn_cap,
            mint_cap,
        });
    }

    // Admin functions ====================================================
    // public entry fun transfer_cap(
    //     admin: &signer,
    //     from_addr: address,
    //     to_addr: address,
    // ) acquires Capabilities {
    //     let cap = borrow_global_mut<Capabilities<SEA>>(from_addr);
    //     assert!(address_of(admin) == cap.owner, E_NO_AUTH);

    //     cap.owner = to_addr;
    // }

    // public entry fun claim_cap(
    //     admin: &signer,
    //     from_addr: address,
    // ) acquires Capabilities {
    //     let cap = borrow_global_mut<Capabilities<SEA>>(from_addr);
    //     assert!(address_of(admin) == cap.owner, E_NO_AUTH);

    //     move_to(admin, cap);
    // }

    public(friend) fun mint(
        account: &signer,
        amount: u64,
    ) acquires Capabilities {
        let capabilities = borrow_global<Capabilities<SEA>>(@sea);
        let addr = address_of(account);

        let coins_minted = coin::mint(amount, &capabilities.mint_cap);

        utils::register_coin_if_not_exist<SEA>(account);
        coin::deposit(addr, coins_minted);
    }
}
