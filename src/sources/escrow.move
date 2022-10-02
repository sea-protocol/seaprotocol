/// # Module-level documentation sections
///
/// * [Background](#Background)
/// * [Implementation](#Implementation)
/// * [Basic public functions](#Basic-public-functions)
/// * [Traversal](#Traversal)
///
/// # Background
///
/// escrow account, escrow assets
/// 
module sea::escrow {
    use std::signer::address_of;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_std::type_info::{Self, TypeInfo};
    use aptos_std::table::{Self, Table};
    use sea::spot_account;

    // Friends >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    friend sea::spot;

    // Constants ====================================================
    const E_NO_AUTH:             u64 = 6000;
    const E_COIN_NOT_EQUAL:      u64 = 6001;
    const E_NO_ESCROW_ASSET:     u64 = 6002;
    const E_ACCOUNT_REGISTERED:  u64 = 6003;

    struct EscrowAccountAsset has key {
        n_coin: u64,
        n_quote: u64,
        n_account: u64,
        coin_map: Table<TypeInfo, u64>,
        quote_map: Table<TypeInfo, u64>,
        // assets_map: Table<u64, u64>,
        address_map: Table<address, u64>,
        account_map: Table<u64, address>,
    }

    // store in account
    struct AccountEscrow<phantom CoinType> has key {
        // key is coin_id
        frozen: Coin<CoinType>,
        available: Coin<CoinType>,
    }

    /// Stores resource account signer capability under Liquidswap account.
    struct SpotEscrowAccountCapability has key {
        signer_cap: SignerCapability
    }

    public entry fun initialize(sea_admin: &signer) {
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);
        move_to(sea_admin, EscrowAccountAsset {
            n_coin: 0,
            n_quote: 0,
            n_account: 0,
            coin_map: table::new<TypeInfo, u64>(),
            quote_map: table::new<TypeInfo, u64>(),
            // assets_map: table::new<u64, u64>(),
            address_map: table::new<address, u64>(),
            account_map: table::new<u64, address>()
        });

        // the resource account signer
        let signer_cap = spot_account::retrieve_signer_cap(sea_admin);
        move_to(sea_admin, SpotEscrowAccountCapability { signer_cap });
    }

    // get account escrow coin available
    public fun escrow_available<CoinType>(
        addr: address
    ): u64 acquires AccountEscrow {
        let ref = borrow_global<AccountEscrow<CoinType>>(addr);
        coin::value(&ref.available)
    }

    // get account escrow coin available
    public fun escrow_frozen<CoinType>(
        addr: address
    ): u64 acquires AccountEscrow {
        let ref = borrow_global<AccountEscrow<CoinType>>(addr);
        coin::value(&ref.frozen)
    }

    public fun deposit<CoinType>(
        account: &signer,
        amount: u64,
        is_frozen: bool
    ) acquires AccountEscrow {
        let account_addr = address_of(account);
        if (exists<AccountEscrow<CoinType>>(account_addr)) {
            let current = borrow_global_mut<AccountEscrow<CoinType>>(account_addr);
            if (is_frozen) {
                coin::merge(&mut current.frozen, coin::withdraw(account, amount));
            } else {
                coin::merge(&mut current.available, coin::withdraw(account, amount));
            }
        } else {
            if (is_frozen) {
                move_to(account, AccountEscrow<CoinType>{
                    available: coin::zero(),
                    frozen: coin::withdraw(account, amount),
                });
            } else {
                move_to(account, AccountEscrow<CoinType>{
                    available: coin::withdraw(account, amount),
                    frozen: coin::zero(),
                });
            }
        };
        // if (table::contains(&escrow_ref.assets_map, asset_id)) {
        //     let asset_ref_mut = table::borrow_mut(&mut escrow_ref.assets_map, asset_id);
        //     *asset_ref_mut = *asset_ref_mut + amount;
        // } else {
        //     table::add(&mut escrow_ref.assets_map, asset_id, amount);
        // };
    }

    // withdraw
    public fun withdraw<CoinType>(
        account: &signer,
        amount: u64,
    ) acquires AccountEscrow {
        let account_addr = address_of(account);
        assert!(exists<AccountEscrow<CoinType>>(account_addr), E_NO_ESCROW_ASSET);
        let escrow_ref = borrow_global_mut<AccountEscrow<CoinType>>(account_addr);
        
        coin::deposit<CoinType>(account_addr, coin::extract(&mut escrow_ref.available, amount));
        // let coin_id = get_coin_id<CoinType>();
        // let account_addr = address_of(account);
        // let escrow_ref = borrow_global_mut<EscrowAccountAsset>(@sea);
        // let account_id = table::borrow<address, u64>(&escrow_ref.address_map, account_addr);
        // let asset_id =  account_asset_id(*account_id, coin_id);
        // let escrow_amt = table::borrow_mut<u64, u64>(&mut escrow_ref.assets_map, asset_id);
        // let escrower = get_spot_account();
        // if (amount > *escrow_amt) {
        //     coin::transfer<CoinType>(&escrower, account_addr, *escrow_amt);
        // } else {
        //     coin::transfer<CoinType>(&escrower, account_addr, amount);
        // };
    }

    public fun is_quote_coin<CoinType>(): bool acquires EscrowAccountAsset {
        let info = type_info::type_of<CoinType>();
        let coinlist = borrow_global<EscrowAccountAsset>(@sea);
        table::contains<TypeInfo, u64>(&coinlist.quote_map, info)
    }

    public fun get_account_id(addr: address): u64 acquires EscrowAccountAsset {
        let escrow_ref = borrow_global<EscrowAccountAsset>(@sea);
        *table::borrow<address, u64>(
            &escrow_ref.address_map,
            addr
        )
    }

    public fun get_account_addr_by_id(id: u64): address acquires EscrowAccountAsset {
        let escrow_ref = borrow_global<EscrowAccountAsset>(@sea);
        *table::borrow<u64, address>(
            &escrow_ref.account_map,
            id
        )
    }

    public(friend) fun get_or_register_account_id(addr: address): u64 acquires EscrowAccountAsset {
        let ref = borrow_global_mut<EscrowAccountAsset>(@sea);
        if (!table::contains<address, u64>(&ref.address_map, addr)) {
            let account_id: u64 = ref.n_account + 1;
            ref.n_account = account_id;
            table::add(&mut ref.address_map, addr, account_id);
            table::add(&mut ref.account_map, account_id, addr);

            account_id
        } else {
            *table::borrow<address, u64>(
                &ref.address_map,
                addr
            )
        }
    }

    public(friend) fun register_account(addr: address): u64 acquires EscrowAccountAsset {
        let ref = borrow_global_mut<EscrowAccountAsset>(@sea);
        assert!(!table::contains<address, u64>(&ref.address_map, addr), E_ACCOUNT_REGISTERED);
        let account_id: u64 = ref.n_account + 1;
        ref.n_account = account_id;
        table::add(&mut ref.address_map, addr, account_id);
        table::add(&mut ref.account_map, account_id, addr);

        account_id
    }

    public(friend) fun get_spot_account(): signer acquires SpotEscrowAccountCapability {
        let spot_cap = borrow_global<SpotEscrowAccountCapability>(@sea);
        account::create_signer_with_capability(&spot_cap.signer_cap)
    }

    // available -> frozen
    // available -= amount
    // frozen += amount
    public(friend) fun transfer_to_frozen<CoinType>(
        addr: address,
        amount: u64,
    ) acquires AccountEscrow {
        let escrow_ref = borrow_global_mut<AccountEscrow<CoinType>>(addr);
        // assert!();
        coin::merge(&mut escrow_ref.frozen, coin::extract(&mut escrow_ref.available, amount))
    }

    public(friend) fun transfer_from_frozen<CoinType>(
        addr: address,
        amount: u64,
    ) acquires AccountEscrow {
        let escrow_ref = borrow_global_mut<AccountEscrow<CoinType>>(addr);
        coin::merge(&mut escrow_ref.available, coin::extract(&mut escrow_ref.frozen, amount))
    }

    // increase the escrow account coin
    public(friend) fun incr_escrow_coin<CoinType>(
        addr: address,
        amt: Coin<CoinType>,
        is_frozen: bool
    ) acquires AccountEscrow {
        let escrow_ref = borrow_global_mut<AccountEscrow<CoinType>>(addr);
        if (is_frozen) {
            coin::merge(&mut escrow_ref.frozen, amt);
        } else {
            coin::merge(&mut escrow_ref.available, amt);
        }
    }

    public(friend) fun dec_escrow_coin<CoinType>(
        addr: address,
        amt: u64,
        is_frozen: bool
    ): Coin<CoinType> acquires AccountEscrow {
        let escrow_ref = borrow_global_mut<AccountEscrow<CoinType>>(addr);
        if (is_frozen) {
            coin::extract<CoinType>(&mut escrow_ref.frozen, amt)
        } else {
            coin::extract<CoinType>(&mut escrow_ref.available, amt)
        }
    }

    public(friend) fun get_or_register_coin_id<CoinType>(
        is_quote: bool,
    ): u64 acquires EscrowAccountAsset,
                    SpotEscrowAccountCapability {
        let coinlist = borrow_global_mut<EscrowAccountAsset>(@sea);
        let info = type_info::type_of<CoinType>();

        if (table::contains<TypeInfo, u64>(&coinlist.coin_map, info)) {
            let cid = table::borrow(&coinlist.coin_map, info);
            return *cid
        };
        // register coin for spot account
        coin::register<CoinType>(&get_spot_account());
        coinlist.n_coin = coinlist.n_coin + 1;
        let id = coinlist.n_coin;
        if (is_quote) {
            coinlist.n_quote = coinlist.n_quote + 1;
            table::add<TypeInfo, u64>(&mut coinlist.quote_map, info, id);
        };
        table::add<TypeInfo, u64>(&mut coinlist.coin_map, info, id);
        id
    }

    fun account_asset_id(account_id: u64, coin_id: u64): u64 {
        (account_id << 32) | (coin_id & 0xffffffff)
    }

    fun get_coin_id<CoinType>(): u64 acquires EscrowAccountAsset {
        let escrow_ref = borrow_global_mut<EscrowAccountAsset>(@sea);
        *table::borrow<TypeInfo, u64>(
            &escrow_ref.coin_map,
            type_info::type_of<CoinType>())
    }
}