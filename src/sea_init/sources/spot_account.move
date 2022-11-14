/// # Module-level documentation sections
///
/// * [Background](#Background)
/// * [Implementation](#Implementation)
/// * [Basic public functions](#Basic-public-functions)
/// * [Traversal](#Traversal)
///
/// # Background
///
/// spot resource account
/// 
module sea::spot_account {
    use std::signer;

    use aptos_framework::account::{Self, SignerCapability};

    const E_NO_AUTH: u64 = 1;

    /// Temporary storage for spot resource account signer capability.
    struct CapabilityStorage has key { signer_cap: SignerCapability }

    /// Creates new resource account for Sea spot DEX, puts signer capability into storage.
    /// Can be executed only from Sea account.
    public entry fun initialize_spot_account(
        sea_admin: &signer
    ) {
        assert!(signer::address_of(sea_admin) == @sea, E_NO_AUTH);

        let (_, signer_cap) =
            account::create_resource_account(sea_admin, b"sea_spot_account");
        move_to(sea_admin, CapabilityStorage { signer_cap });
    }

    public entry fun initialize_lp_account(
        sea_admin: &signer,
        lp_coin_metadata_serialized: vector<u8>,
        lp_coin_code: vector<u8>
    ) {
        assert!(signer::address_of(sea_admin) == @sea, E_NO_AUTH);

        let (lp_acc, signer_cap) =
            account::create_resource_account(sea_admin, b"sea_spot_account");
        aptos_framework::code::publish_package_txn(
            &lp_acc,
            lp_coin_metadata_serialized,
            vector[lp_coin_code]
        );
        move_to(sea_admin, CapabilityStorage { signer_cap });
    }

    public entry fun publish_pkg(
        sea_admin: &signer,
        lp_coin_metadata_serialized: vector<u8>,
        lp_coin_code: vector<u8>) acquires CapabilityStorage {
        assert!(signer::address_of(sea_admin) == @sea, E_NO_AUTH);
        
        let cap = borrow_global<CapabilityStorage>(@sea);
        let sign = account::create_signer_with_capability(&cap.signer_cap);

        aptos_framework::code::publish_package_txn(
            &sign,
            lp_coin_metadata_serialized,
            vector[lp_coin_code]
        );
    }

    /// Destroys temporary storage for resource account signer capability and returns signer capability.
    /// It needs for initialization of Sea DEX spot market.
    public fun retrieve_signer_cap(
        sea_admin: &signer
    ): SignerCapability acquires CapabilityStorage {
        assert!(signer::address_of(sea_admin) == @sea, E_NO_AUTH);
        let CapabilityStorage { signer_cap } =
            move_from<CapabilityStorage>(signer::address_of(sea_admin));
        signer_cap
    }

    #[test_only]
    use std::debug;

    #[test(sea_admin = @sea)]
    fun test_resource_account(
        sea_admin: &signer
    ): signer {
        let (_, signer_cap) =
            account::create_resource_account(sea_admin, b"sea_spot_account");
        let sig = account::create_signer_with_capability(&signer_cap);
        debug::print(&signer::address_of(&sig));
        return sig
    }
}
