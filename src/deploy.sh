#!/bin/bash

echo 'get fund ....'
aptos account fund-with-faucet --account dev3 --amount 1000000000
aptos account fund-with-faucet --account sealib --amount 1000000000

echo 'deploy sea_init/sea_lp ....'
cd sea_lp
aptos move compile --save-metadata
cd ../sea_init
aptos move publish --profile dev3 --assume-yes
aptos move run --profile dev3 --assume-yes --function-id 0xf5de9e9d7a718c10964a8e5ce32de33c591979e2b2e76a1e58dcc9e6f74480df::spot_account::initialize_spot_account
aptos move run --profile dev3 --assume-yes --function-id 0xf5de9e9d7a718c10964a8e5ce32de33c591979e2b2e76a1e58dcc9e6f74480df::spot_account::publish_pkg --args hex:"`xxd -ps -c10000000  /Users/guotie/guotie/chain/seaprotocol/members/bigwin/seaprotocol/src/sea_lp/build/SeaLP/package-metadata.bcs`"  hex:"`xxd -ps -c10000000  /Users/guotie/guotie/chain/seaprotocol/members/bigwin/seaprotocol/src/sea_lp/build/SeaLP/bytecode_modules/lp.mv`"

echo 'deploy sealib ....'
cd ../sea_lib
aptos move publish --profile sealib --assume-yes

echo 'deploy sea ....'
cd ../
aptos move publish --profile dev3 --assume-yes


echo 'deploy sea_mock ....'
cd sea_mock
aptos move publish --profile dev3 --assume-yes

aptos move run --function-id 0xf5de9e9d7a718c10964a8e5ce32de33c591979e2b2e76a1e58dcc9e6f74480df::market::register_quote \
--args u64:10000000  --type-args 0xf5de9e9d7a718c10964a8e5ce32de33c591979e2b2e76a1e58dcc9e6f74480df::mock_coins::USDC --assume-yes --profile dev3
aptos move run --function-id 0xf5de9e9d7a718c10964a8e5ce32de33c591979e2b2e76a1e58dcc9e6f74480df::market::register_quote \
--args u64:10000000  --type-args 0xf5de9e9d7a718c10964a8e5ce32de33c591979e2b2e76a1e58dcc9e6f74480df::mock_coins::USDT --assume-yes --profile dev3

