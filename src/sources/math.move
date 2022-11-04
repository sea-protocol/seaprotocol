module sea::math {

    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    /// Returns 10^degree.
    public fun pow_10(degree: u8): u64 {
        let res = 1;
        let i = 0;
        while ({
            spec {
                invariant res == spec_pow(10, i);
                invariant 0 <= i && i <= degree;
            };
            i < degree
        }) {
            res = res * 10;
            i = i + 1;
        };
        res
    }

    spec fun spec_pow(y: u64, x: u64): u64 {
        if (x == 0) {
            1
        } else {
            y * spec_pow(y, x-1)
        }
    }
    spec pow_10 {
        ensures degree == 0 ==> result == 1;
        ensures result == spec_pow(10, degree);
    }

    public fun min_u64(a: u64, b: u64): u64 {
        if (a < b) a else b
    }

    /// Get square root of `y`.
    /// Babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    public fun sqrt(y: u128): u64 {
        if (y < 4) {
            if (y == 0) {
                0u64
            } else {
                1u64
            }
        } else {
            let z = y;
            let x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            };
            (z as u64)
        }
    }
    // Check if mul maybe overflow
    // The result maybe false positive
    public fun is_overflow_mul(a: u128, b: u128): bool {
        MAX_U128 / b <= a
    }
}