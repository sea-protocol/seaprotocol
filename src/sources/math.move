module sea::math {

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
}