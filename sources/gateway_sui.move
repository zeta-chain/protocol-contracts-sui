module gateway_sui::gateway;

use sui::coin::{Self,Coin};
use std::ascii::String;
use sui::balance::{Self,Balance,Supply};
use sui::bag::{Self,Bag};
use std::type_name::{get, into_string};

public struct Vault<phantom T> has store {
    balance: Balance<T>,
}

public struct Gateway has key {
    id: UID,
    vaults: Bag,
}

fun init(ctx: &mut TxContext)  {
    let gateway = Gateway {
        id: object::new(ctx),
        vaults: bag::new(ctx),
    };
    transfer::share_object(gateway);
}

public fun generate_coin_name<T>(): String {
   into_string(get<T>())
}

public fun register_vault<T>(gateway: &mut Gateway) {
    let vault_name = generate_coin_name<T>();
    let vault = Vault<T> {
        balance: balance::zero<T>(),
    };
    bag::add(&mut gateway.vaults, vault_name, vault);
}

public fun is_registered<T>(gateway: &Gateway): bool {
    let vault_name = generate_coin_name<T>();
    bag::contains_with_type<String,Vault<T>>(&gateway.vaults, vault_name)
}

public fun deposit<T>(gateway: &mut Gateway, coin: Coin<T>, _: &mut TxContext) {
    let vault_registered = is_registered<T>(gateway);
    assert!(vault_registered, 1);
    let coin_name = generate_coin_name<T>();
    let vault = bag::borrow_mut<String, Vault<T>>(&mut gateway.vaults, coin_name);
    let coin_balance = coin.into_balance();
    balance::join(&mut vault.balance, coin_balance);
}

public fun withdraw<T>(gateway: &mut Gateway, amount:u64, ctx: &mut TxContext): u64 {
    let vault_registered = is_registered<T>(gateway);
    assert!(vault_registered, 1);
    let coin_name = generate_coin_name<T>();
    let vault = bag::borrow_mut<String, Vault<T>>(&mut gateway.vaults, coin_name);
    let coin_out = coin::take(&mut vault.balance, amount, ctx);
    transfer::public_transfer(coin_out, tx_context::sender(ctx));
    amount
}

#[test_only]
use sui::sui::SUI;
#[test_only]
use sui::test_scenario::{Self as ts, Scenario};
#[test_only]
fun test_coin(ts: &mut Scenario): Coin<SUI> {
    coin::mint_for_testing<SUI>(42, ts.ctx())
}

#[test]
fun test_register_vault() {
   let mut scenario = ts::begin(@0xA);

   ts::next_tx(&mut scenario, @0xA);
   {
       init(scenario.ctx());
   };
   ts::next_tx(&mut scenario, @0xA);
   {
        let mut  gateway = scenario.take_shared<Gateway>();
        register_vault<SUI>(&mut gateway);
        let b = is_registered<SUI>(&gateway);
        assert!(b);
        ts::return_shared(gateway);
   };

   ts::next_tx(&mut scenario, @0xA);
   {
       let mut gateway = scenario.take_shared<Gateway>();
       // create some test coin
       let coin = test_coin(&mut scenario);
       deposit(&mut gateway, coin, scenario.ctx());
       ts::return_shared(gateway);
   };
   ts::next_tx(&mut scenario, @0xB);
   {
        let mut gateway = scenario.take_shared<Gateway>();
        withdraw<SUI>(&mut gateway, 10, scenario.ctx());
        ts::return_shared(gateway);

   };
   ts::next_tx(&mut scenario, @0xB);
   {
       // check the received coin on @0xB
       let coin = ts::take_from_address<Coin<SUI>>(&scenario, @0xB);
       assert!(coin::value(&coin) == 10);
       ts::return_to_address(@0xB, coin);
   };
   ts::end(scenario);
}
