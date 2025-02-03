#[test_only]
module gateway_sui::gateway_sui_tests;
use gateway_sui::gateway::{Gateway, register_vault, deposit, withdraw, is_registered, WithdrawCap, AdminCap, init_for_testing, ENonceMismatch};
use sui::coin::{Self,Coin};

#[test_only]
use sui::sui::SUI;
#[test_only]
use sui::test_scenario::{Self as ts, Scenario};
#[test_only]
fun test_coin(ts: &mut Scenario): Coin<SUI> {
    coin::mint_for_testing<SUI>(42, ts.ctx())
}

#[test_only]
fun setup(scenario: &mut Scenario) {
    ts::next_tx(scenario, @0xA);
    {
        init_for_testing(scenario.ctx());
    };
    ts::next_tx(scenario, @0xA);
    {
         let mut  gateway = scenario.take_shared<Gateway>();
         let admin_cap = ts::take_from_address<AdminCap>(scenario, @0xA);
         register_vault<SUI>(&mut gateway, &admin_cap);
         let b = is_registered<SUI>(&gateway);
         assert!(b);
         ts::return_shared(gateway);
         ts::return_to_address(@0xA, admin_cap);
    };

    ts::next_tx(scenario, @0xB);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        // create some test coin
        let coin = test_coin( scenario);
        let ethAddr = b"0x7c125C1d515b8945841b3d5144a060115C58725F".to_string().to_ascii();
        deposit(&mut gateway, coin, ethAddr, scenario.ctx());
        ts::return_shared(gateway);
    };
}

#[test]
fun test_register_deposit_withdraw() {
   let mut scenario = ts::begin(@0xA);
   setup(&mut scenario);

   ts::next_tx(&mut scenario, @0xA);
   {
        let mut gateway = scenario.take_shared<Gateway>();
        let cap = ts::take_from_address<WithdrawCap>(&scenario, @0xA);
        let nonce = gateway.nonce();
        let coins = withdraw<SUI>(&mut gateway, 10, nonce, &cap, scenario.ctx());
        assert!(coin::value(&coins) == 10);
        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
        transfer::public_transfer(coins, @0xA);
   };
   ts::next_tx(&mut scenario, @0xA);
   {
       let gateway = scenario.take_shared<Gateway>();
       assert!(gateway.nonce() == 1); // nonce should be updated
       // check the received coin on @0xB
       let coin = ts::take_from_address<Coin<SUI>>(&scenario, @0xA);
       assert!(coin::value(&coin) == 10);
       ts::return_to_address(@0xA, coin);
       ts::return_shared(gateway);

   };
   ts::end(scenario);
}

#[test, expected_failure(abort_code = ENonceMismatch)]
fun test_withdraw_wrong_nonce() {
   let mut scenario = ts::begin(@0xA);
   setup(&mut scenario);

   ts::next_tx(&mut scenario, @0xA);
   {
       let mut gateway = scenario.take_shared<Gateway>();
       let cap = ts::take_from_address<WithdrawCap>(&scenario, @0xA);
       let nonce = gateway.nonce() + 1; // intentially create a mismatch
       let coins = withdraw<SUI>(&mut gateway, 10, nonce, &cap, scenario.ctx());
       assert!(coin::value(&coins) == 10);
       ts::return_to_address(@0xA, cap);
       ts::return_shared(gateway);
       transfer::public_transfer(coins, @0xA);
    };
   ts::end(scenario);
}
