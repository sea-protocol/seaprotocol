/// # Module-level documentation sections
///
/// * [Background](#Background)
/// * [Implementation](#Implementation)
/// * [Basic public functions](#Basic-public-functions)
/// * [Traversal](#Traversal)
///
/// # Background
///
/// Price is the most important part of an order. But there are two difficulty.
/// First, in Cex, the price can be represent by decimal, but in solidity/move,
/// decimal is expensive. so we use u128 to represent the price
/// Second, we are permissionless DEX, there can be many pairs, some of the price
/// is very high, but some of them is very low, so how can we inact an universal rule.
/// here, the rule is effective digits
/// 
module sea::price {
    // Constants ====================================================
    const E1: u128 = 10;
    const E2: u128 = 100;
    const E4: u128 = 10000;
    const E8: u128 = 100000000;
    const MAX_EFFECTIVE_DIGITS: u128 = 1000000;
    const MAX_U64: u128 = 0xffffffff;
    // 64 bit
    const ORDER_ID_MASK: u128 = 0xffffffffffffffff;

    public fun get_price_order_id(v: u128): (u64, u64) {
        (((v >> 64) as u64), ((v & ORDER_ID_MASK) as u64))
    }

    // price_ratio = price_coefficient / math.pow(10, quote_decimals-base_decimals)
    // price = price_decimal * price_coefficient
    // quote = base * price / price_ratio = base * price_decimal * math.pow(10, quote_decimals-base_decimals)
    // price_ratio should >= 1 or else return false
    public fun calc_price_ratio(
        base_scale: u64,
        quote_scale: u64,
        price_coefficient: u64,
    ): (u64, bool) {
        if (quote_scale >= base_scale) {
            let delta = quote_scale/base_scale;
            if (price_coefficient < delta) {
                return (0, false)
            };
            (price_coefficient/delta, true)
        } else {
            let ratio = ((price_coefficient as u128) * ((base_scale/quote_scale) as u128));
            if (ratio > MAX_U64) {
                return (0, false)
            };
            ((ratio as u64), true)
        }
    }

    // check the price is valid
    public fun is_valid_price(price: u128): bool {
        let valid: bool;
        if (price == 0) {
            return false
        };

        loop {
            if (price % E8 == 0) {
                price = price / E8;
            } else if (price % E4 == 0) {
                price = price / E4;
            } else if (price % E2 == 0) {
                price = price / E2;
            } else if (price % E1 == 0) {
                price = price / E1;
            } else {
                break
            }
        };

        valid = price < MAX_EFFECTIVE_DIGITS;
        valid
    }

    #[test]
    fun test_valid_price() {
        let maxu128: u128 = 0xffffffffffffffffffffffffffffffff;
        let i: u128 = 1;
        // while(i <= 100000) {
        while(i <= 100) {
            let price = i;
            loop {
                let ok = is_valid_price(price);
                assert!(ok, (i as u64));
                if (maxu128 / 10 < price) {
                    break
                };
                price = price * 10;
            };
            i = i + 1;
        }
    }

    #[test]
    fun test_valid_price_10k() {
        use std::vector;

        let maxu128: u128 = 0xffffffffffffffffffffffffffffffff;
        let invalid_prices: vector<u128> = vector[100247, 100001, 234567, 990011,
        998899, 540001, 780328, 304050, 328764, 846380, 769000, 700201,
        847320, 456012, 870302, 650934, 544502, 500001, 900001, 900010];

        while(vector::length(&invalid_prices) > 0) {
            let price = vector::pop_back<u128>(&mut invalid_prices);
            loop {
                let ok = is_valid_price(price);
                assert!(ok, (price as u64));
                if (maxu128 / 10 < price) {
                    break
                };
                price = price * 10;
            };
        }
    }

    #[test]
    fun test_invalid_price() {
        use std::vector;

        let maxu128: u128 = 0xffffffffffffffffffffffffffffffff;
        let i: u64 = 1;
        let invalid_prices: vector<u128> = vector[10002347, 1000001, 2345671, 9990011,
        238948362, 543210001, 7803282, 203040506, 32876401, 84638001, 7690001, 70000201,
        8473201, 4560012, 87093202, 6509324, 5445002, 5000001, 9000001, 90000000010];

        while(vector::length(&invalid_prices) > 0) {
            let price = vector::pop_back<u128>(&mut invalid_prices);
            loop {
                let ok = is_valid_price(price);
                assert!(!ok, (i as u64));
                if (maxu128 / 10 < price) {
                    break
                };
                price = price * 10;
            };
        }
    }

    #[test]
    fun test_calc_price_ratio() {

    }
}
