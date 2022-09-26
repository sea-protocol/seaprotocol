/// escrow account
module sea::account {
    use aptos_std::table::{Self, Table};
    use std::signer::address_of;

    struct SpotAccount has key {
        account_id: u64
    }

    struct SpotAccounts has key {
        n_account: u64,
        accounts: Table<address, u64>
    }

    // Constants ====================================================
    const E_ACCOUNT_NOT_AUTH: u64     = 1;
    const E_ACCOUNT_NOT_INIT: u64     = 2;

    /// init_spot_accounts init spot accounts
    public entry fun init_spot_accounts(account: &signer) {
        assert!(address_of(account) == @sea, E_ACCOUNT_NOT_AUTH);

        move_to<SpotAccounts>(account, SpotAccounts{
            n_account: 0,
            accounts: table::new<address, u64>()
        });
    }

    /// register account
    public entry fun register_spot_account(
            account: &signer
        ) acquires SpotAccounts {
        assert!(exists<SpotAccounts>(@sea), E_ACCOUNT_NOT_INIT);
        let spot_accounts = borrow_global_mut<SpotAccounts>(@sea);
        // let addr = address_of(account);
        spot_accounts.n_account = spot_accounts.n_account + 1;
        let account_id = spot_accounts.n_account;

        move_to(account, SpotAccount{account_id: account_id});
    }
}
