/// # Module-level documentation sections
///
/// * [Background](#Background)
/// * [Implementation](#Implementation)
/// * [Basic public functions](#Basic-public-functions)
/// * [Traversal](#Traversal)
///
/// # Background
///
module sea::events {
    use std::signer::address_of;
    use std::string::{String};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_std::type_info::{Self, TypeInfo};
    use aptos_framework::account;
    use aptos_framework::coin;

    friend sea::escrow;
    friend sea::market;
    
    const E_NO_AUTH:     u64 = 10;
    const E_INITIALIZED: u64 = 11;

    // event pair
    struct EventPair has store, drop {
        base: TypeInfo,
        quote: TypeInfo,
        fee_ratio: u64,
        base_id: u64,
        quote_id: u64,
        pair_id: u64,
        lot_size: u64,
        price_ratio: u64,
        price_coefficient: u64,
        base_decimals: u8,
        quote_decimals: u8,
    }

    // event register quote
    struct EventQuote has store, drop {
        coin_info: TypeInfo,
        name: String,
        symbol: String,
        decimals: u8,
        coin_id: u64,
        min_notional: u64,
    }

    struct EventAccount has store, drop {
        account_id: u64,
        account_addr: address,
    }

    struct EventCoin has store, drop {
        coin_id: u64,
        name: String,
        symbol: String,
        decimals: u8,
        coin_info: TypeInfo,
    }

    struct EventContainer has key {
        event_pairs: EventHandle<EventPair>,
        event_quotes: EventHandle<EventQuote>,
        event_coins: EventHandle<EventCoin>,
        event_accounts: EventHandle<EventAccount>,
    }

    fun init_module(sea_admin: &signer) {
        initialize(sea_admin);
    }

    public fun initialize(sea_admin: &signer) {
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);
        assert!(!exists<EventContainer>(address_of(sea_admin)), E_INITIALIZED);

        move_to(sea_admin, EventContainer {
            event_pairs: account::new_event_handle<EventPair>(sea_admin),
            event_quotes: account::new_event_handle<EventQuote>(sea_admin),
            event_coins: account::new_event_handle<EventCoin>(sea_admin),
            event_accounts: account::new_event_handle<EventAccount>(sea_admin),
        });
    }

    public(friend) fun emit_pair_event<B, Q>(
        fee_ratio: u64,
        base_id: u64,
        quote_id: u64,
        pair_id: u64,
        lot_size: u64,
        price_ratio: u64,
        price_coefficient: u64,
    ) acquires EventContainer {
        let container = borrow_global_mut<EventContainer>(@sea);

        event::emit_event<EventPair>(
            &mut container.event_pairs,
            EventPair{
                base: type_info::type_of<B>(),
                quote: type_info::type_of<Q>(),
                fee_ratio: fee_ratio,
                base_id: base_id,
                quote_id: quote_id,
                pair_id: pair_id,
                lot_size: lot_size,
                price_ratio: price_ratio,
                price_coefficient: price_coefficient,
                base_decimals: coin::decimals<B>(),
                quote_decimals: coin::decimals<Q>(),
        },
        );
    }

    public(friend) fun emit_quote_event<Q>(
        coin_id: u64,
        min_notional: u64,
    ) acquires EventContainer {
        let container = borrow_global_mut<EventContainer>(@sea);

        event::emit_event<EventQuote>(
            &mut container.event_quotes,
            EventQuote{
                coin_info: type_info::type_of<Q>(),
                coin_id: coin_id,
                name: coin::name<Q>(),
                symbol: coin::symbol<Q>(),
                decimals: coin::decimals<Q>(),
                min_notional: min_notional,
            },
        );
    }

    public(friend) fun emit_coin_event<Q>(
        coin_id: u64,
    ) acquires EventContainer {
        let container = borrow_global_mut<EventContainer>(@sea);

        event::emit_event<EventCoin>(
            &mut container.event_coins,
            EventCoin{
                coin_info: type_info::type_of<Q>(),
                name: coin::name<Q>(),
                symbol: coin::symbol<Q>(),
                decimals: coin::decimals<Q>(),
                coin_id: coin_id,
            },
        );
    }

    public(friend) fun emit_account_event(
        account_id: u64,
        account_addr: address,
    ) acquires EventContainer {
        let container = borrow_global_mut<EventContainer>(@sea);

        event::emit_event<EventAccount>(
            &mut container.event_accounts,
            EventAccount{
                account_id: account_id,
                account_addr: account_addr,
            },
        );
    }

    // #[test]
    // fun test_events() {
    //     let sea_admin = aptos_framework::account::create_account_for_test(@sea);
    //     initialize(&sea_admin);
    // }
}
