//
// fee denominator is 1000000
module sea::fee {
    use std::signer::address_of;
    use aptos_std::type_info;

    // fee ratio 0.02%
    struct FeeRatio200 has store {}

    // fee ratio 0.05%
    struct FeeRatio500 has store {}

    // fee ratio 0.1%
    struct FeeRatio1000 has store {}

    struct MakerProportion has key {
        grid_propportion: u64,
        order_proportion: u64,
    }

    /// Errors
    const E_NO_FEE_RATIO: u64 = 4000;
    const E_NO_AUTH:      u64 = 4001;
    const FEE_DENOMINATE: u64 = 1000000;

    public entry fun initialize(sea_admin: &signer) {
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);

        move_to(sea_admin, MakerProportion{
            grid_propportion: 800,
            order_proportion: 600,
            })
    }

    public entry fun modify_maker_port(
        sea_admin: &signer,
        grid: u64,
        order: u64) acquires MakerProportion {
        assert!(address_of(sea_admin) == @sea, E_NO_AUTH);
        let prop = borrow_global_mut<MakerProportion>(@sea);

        prop.grid_propportion = grid;
        prop.order_proportion = order;
    }

    // maker fee shares
    public fun get_maker_fee_shares(fee: u64, ratio: u64): (u64, u64) {
        let maker_share = fee * ratio / 1000;
        (maker_share, fee-maker_share)
    }

    /// get fee ratio by type
    public fun get_fee_ratio<F>(): u64 {
        if (type_info::type_of<F>() == type_info::type_of<FeeRatio200>()) {
            return 200
        } else if (type_info::type_of<F>() == type_info::type_of<FeeRatio500>()) {
            return 500
        } else if (type_info::type_of<F>() == type_info::type_of<FeeRatio1000>()) {
            return 1000
        };
    
        assert!(false, E_NO_FEE_RATIO);
        0
    }
}