
module sea::fee {
    use aptos_std::type_info;

    // fee ratio 0.02%
    struct FeeRatio200 has store {}

    // fee ratio 0.05%
    struct FeeRatio500 has store {}

    // fee ratio 0.1%
    struct FeeRatio1000 has store {}

    /// Errors
    const E_NO_FEE_RATIO: u64 = 4000;

    /// get fee ratio by type
    public fun get_fee_ratio<F>(): u64 {
        if (type_info::type_of<F>() == type_info::type_of<FeeRatio200>()) {
            return 200;
        } else if (type_info::type_of<F>() == type_info::type_of<FeeRatio500>()) {
            return 500;
        } else if (type_info::type_of<F>() == type_info::type_of<FeeRatio1000>()) {
            return 1000;
        };
    
        assert!(false, E_NO_FEE_RATIO);
        0
    }
}