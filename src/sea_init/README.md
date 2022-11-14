aptos move run --assume-yes --function-id 0xbfeab661334042d549d1ddeb49fb28cc3c0ee9c445844651b17182900000000::lp_coin::publish_package --args hex:"`xxd -ps -c10000000  /Users/mac/work/lp_coin/build/lp_coin/package-metadata.bcs`"  hex:"`xxd -ps -c10000000  /Users/mac/work//lp_coin/build/lp_coin/bytecode_modules/lp_coin.mv`"

aptos move run --assume-yes --function-id 0x20cea9406e2349568c613140a57988290deb709ae14fed30f29320f9b446abbf::spot_account::initialize_lp_account --args hex:"`xxd -ps -c10000000  /Users/guotie/guotie/chain/seaprotocol/members/bigwin/seaprotocol/src/sea_lp/build/SeaLP/package-metadata.bcs`"  hex:"`xxd -ps -c10000000  /Users/guotie/guotie/chain/seaprotocol/members/bigwin/seaprotocol/src/sea_lp/build/SeaLP/bytecode_modules/lp.mv`"

