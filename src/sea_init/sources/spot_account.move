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
}
