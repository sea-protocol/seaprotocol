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
    use aptos_framework::coin::{Self, BurnCapability, FreezeCapability, MintCapability};

    struct SEA {}
    
    // Friends >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    friend sea::mining;

    /// Capabilities resource storing mint and burn capabilities.
    /// The resource is stored on the account that initialized coin `CoinType`.
    struct Capabilities<phantom CoinType> has key {
        burn_cap: BurnCapability<CoinType>,
        freeze_cap: FreezeCapability<CoinType>,
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
            4,
            true,
        );
        move_to(sender, Capabilities<SEA> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }

    // Public functions ====================================================
    
    public(friend) fun mint(
        to: address,
        amount: u64,
    ) acquires Capabilities {
        let capabilities = borrow_global<Capabilities<SEA>>(@sea);

        let coins_minted = coin::mint(amount, &capabilities.mint_cap);
        coin::deposit(to, coins_minted);
    }
}

