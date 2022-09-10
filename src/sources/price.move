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
/// is very high, but some of them is very low, so how can we inact an universal rule
/// 
module sea::price {
}
