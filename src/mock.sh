
# create pairs
aptos account fund-with-faucet --account pool --amount 1000000000

aptos move run --function-id 0xf5de9e9d7a718c10964a8e5ce32de33c591979e2b2e76a1e58dcc9e6f74480df::market::register_pair \
--args u64:500 --args u64:1000000000 --args u64:100 \
 --type-args 0xf5de9e9d7a718c10964a8e5ce32de33c591979e2b2e76a1e58dcc9e6f74480df::mock_coins::BTC \
 --type-args 0xf5de9e9d7a718c10964a8e5ce32de33c591979e2b2e76a1e58dcc9e6f74480df::mock_coins::USDT \
 --assume-yes --profile pool

aptos move run --function-id 0xf5de9e9d7a718c10964a8e5ce32de33c591979e2b2e76a1e58dcc9e6f74480df::market::register_pair \
--args u64:500 --args u64:1000000000 --args u64:100 \
 --type-args 0xf5de9e9d7a718c10964a8e5ce32de33c591979e2b2e76a1e58dcc9e6f74480df::mock_coins::ETH \
 --type-args 0xf5de9e9d7a718c10964a8e5ce32de33c591979e2b2e76a1e58dcc9e6f74480df::mock_coins::USDT \
 --assume-yes --profile pool
