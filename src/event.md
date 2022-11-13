## place order

```
    struct EventOrderPlace has store, drop {
        qty: u64,
        pair_id: u64,
        order_id: u64,
        price: u64,
        side: u8,
        grid_id: u64,
        account_id: u64,
        is_flip: bool,
    }
```

## cancel order
```
    struct EventOrderCancel has store, drop {
        qty: u64,
        pair_id: u64,
        order_id: u64,
        price: u64,
        side: u8,
        grid_id: u64,
        account_id: u64,
    }
```

## order filled
```
    struct EventTrade has store, drop {
        qty: u64,
        quote_qty: u64,
        pair_id: u64,
        price: u64,
        fee_total: u64,
        fee_maker: u64,
        fee_dao: u64,
    }
```

## order complete
```
    struct EventOrderComplete has store, drop {
        pair_id: u64,
        order_id: u64,
        price: u64,
        side: u8,
        grid_id: u64,
        account_id: u64,
    }
```

## register account
```
    struct EventAccount has store, drop {
        account_id: u64,
        account_addr: address,
    }
```

## register coin
```
    struct EventCoin has store, drop {
        coin_id: u64,
        coin_info: TypeInfo,
    }
```

## register quote
```
    struct EventQuote has store, drop {
        coin_info: TypeInfo,
        coin_id: u64,
        min_notional: u64,
    }
```

## register pair/pool
```
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
```
