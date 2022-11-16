1. 发布
aptos move publish --profile xxx

2. 编译 lp 包

cd sea_lp
aptos move compile --save-metadata
3. 初始化
aptos move run --assume-yes --function-id 0xbfeab661334042d549d1ddeb49fb28cc3c0ee9c445844651b17182900000000::lp_coin::publish_package --args hex:"`xxd -ps -c10000000  /Users/mac/work/lp_coin/build/lp_coin/package-metadata.bcs`"  hex:"`xxd -ps -c10000000  /Users/mac/work//lp_coin/build/lp_coin/bytecode_modules/lp_coin.mv`"

aptos move run --assume-yes --function-id 0x20cea9406e2349568c613140a57988290deb709ae14fed30f29320f9b446abbf::spot_account::initialize_lp_account --args hex:"`xxd -ps -c10000000  /Users/guotie/guotie/chain/seaprotocol/members/bigwin/seaprotocol/src/sea_lp/build/SeaLP/package-metadata.bcs`"  hex:"`xxd -ps -c10000000  /Users/guotie/guotie/chain/seaprotocol/members/bigwin/seaprotocol/src/sea_lp/build/SeaLP/bytecode_modules/lp.mv`"

aptos move run --profile dev2 --assume-yes --function-id 0x1639d77dcc10235c91f135a0a59606df36e60fa67a7757783ffa87a84a390299::spot_account::initialize_spot_account


aptos move run --profile dev2 --assume-yes --function-id 0x1639d77dcc10235c91f135a0a59606df36e60fa67a7757783ffa87a84a390299::spot_account::publish_pkg --args hex:"`xxd -ps -c10000000  /Users/guotie/guotie/chain/seaprotocol/members/bigwin/seaprotocol/src/sea_lp/build/SeaLP/package-metadata.bcs`"  hex:"`xxd -ps -c10000000  /Users/guotie/guotie/chain/seaprotocol/members/bigwin/seaprotocol/src/sea_lp/build/SeaLP/bytecode_modules/lp.mv`"

