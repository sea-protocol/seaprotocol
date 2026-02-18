# Deprecated

Moved to [https://www.gridtrade.xyz/](https://github.com/sea-dex/gridtrade)


# seaprotocol
We believe anybody has the right to trade any asset anywhere, anytime!

Sea protocol is an ultimate DEX base on order-book & AMM, currently being developed on the Aptos & Sui blockchain.Sea protocol leverages the hyper parallelization of Aptos/Sui to bring incredible speed,reliability, and cost-effectiveness to decentralized trading.


**Be the voice of freedom. Bank the unbanked. Speak for the silenced.**

# design

# Grid Orders

Grid order is also known as grid trading. grid orders at regular intervals across a range. Buy orders are replaced with sell orders when they fill and sell orders are replaced with buy orders.

for example, Alice place a grid order which has 8 orders, 4 is buy order, 4 is sell order, as following:
| Side  | Price  | Qty  | 
|---|---|---|
| Sell3  | 103  | 2.5  |
| Sell2  | 102  | 2.5  |
| Sell1  | 101  | 2.5  |
| Sell0  | 100  | 2.5  |
| Buy0  |  98 | 2.5  |
| Buy1  |  97 |  2.5 |
| Buy2  |  96 | 2.5  |
| Buy3  |  95 |  2.5 |

If Sell0 is filled, this order got 100*2.5 = 250 quote; then this order will filp to buy order:
| Side  | Price  | Qty  | 
|---|---|---|
| Buy  | 99  | 2.5  |

If the filp order is filled, then it become sell order again:
| Side  | Price  | Qty  | 
|---|---|---|
| Sell  | 100  | 2.5  |

As the price fluctuates up and down, the grid filp again and again, the makes will got more and more profit.

And we provide maximum flexibility: you can cancel any order in the grid at any time.

Uniswap v3 a continual ranged grid order.

# Pair

## Min Lot Size

Sea protocol set min lot size to protect Sybil attack.

The pair's min lot size is NOT set when the pair is created. The min lot size is set when first trade created, and the min lot size can be modify at anytime when the trade price is updated, but it is not necessary.

## Price

Because aptos stdlib coin balance is u64, so the coin's decimals can NOT be too big, the recommend max is 8.

When not consider the coin scale, price formula is following:
```
price = quote_volume / base_volume
```

If we consider the coin scale, it became:
```
price = (quote_amount * base_scale) / (base_amount * quote_scale)
```

If the price is express in big int, we should multiple the price by a big number, such as 10^8, we call this is price coefficient, so:

```
price = price_coefficient * (quote_amount * base_scale) / (base_amount * quote_scale)
```

If we define price_ratio as following:
```
price_ratio = price_coefficient * base_scale / quote_scale
```

then, the final price express:
```
price = price_ratio * (quote_amount/base_amount)
```

# zero spread

You can place post-only orders with same price, reverse side!

This is important for stable coin swap. For example, the USDT/USDC pair, in the orderbook, there have both sell orders with price 1 and buy orders with price 1, so anyone can buy USDT at price 1, or sell USDT at price 1.

# Trading is mining

Trading is mining.

Uniswap does not allocate tokens to trades, I think this is unfair for traders. 

Traders paid the trade fee, paid the gas fee, but got nothing.

We will avoid this and our token will incentivize both traders and LPs, for 50% to 50%.


## test

```
aptos move test -i 1000000000
```

# Join us

Follow us on twitter:

https://twitter.com/sea_protocol

Join us on discord:

https://discord.gg/fuEkecabwS

And our medium:

https://medium.com/@seaprotocol

