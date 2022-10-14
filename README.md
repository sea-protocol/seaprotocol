# seaprotocol
sea protocol is the next generation DEX base on CLOB

follow us on twitter:

https://twitter.com/sea_protocol

or join us on discord:

https://discord.gg/fuEkecabwS

## test

```
aptos move test -i 1000000000
```

# design

## Grid Orders

Grid order is orders at regular intervals across a range. Buy orders are replaced with sell orders when they fill and sell orders are replaced with buy orders.

Uniswap v3 a continual ranged grid order.

# Min Lot Size

## Price

Because aptos stdlib coin balance is u64, so the coin's decimals can NOT be too big, the recommend max is 8.

