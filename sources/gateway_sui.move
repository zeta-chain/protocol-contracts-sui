module gateway_sui::gateway;

use sui::coin::{Self,Coin};
use std::ascii::{String};
use sui::balance::{Self,Balance};
use sui::bag::{Self,Bag};
use std::type_name::{get, into_string};
use sui::event;

public struct Vault<phantom T> has store {
    balance: Balance<T>,
}

public struct Gateway has key {
    id: UID,
    vaults: Bag,
}

public struct WithdrawCap has key, store {
    id: UID,
}

fun init(ctx: &mut TxContext)  {
    let gateway = Gateway {
        id: object::new(ctx),
        vaults: bag::new(ctx),
    };

    let cap = WithdrawCap {
        id: object::new(ctx),
    };
    transfer::transfer(cap, tx_context::sender(ctx));
    transfer::share_object(gateway);
}

public fun generate_coin_name<T>(): String {
   into_string(get<T>())
}

// add a capability object to restrict the priviledge of register_vault, liek the WithdrawCap
public fun register_vault<T>(gateway: &mut Gateway) {
    assert!(is_registered<T>(gateway) == false, 3);
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

// TODO: add a separate interface deposit_and_call to match the other chain intefaces?
public fun deposit<T>(gateway: &mut Gateway, coin: Coin<T>, receiver: String, ctx: &mut TxContext) {
    // TODO: use string as error code?
    assert!(receiver.length() == 42, 2);
    let vault_registered = is_registered<T>(gateway);
    assert!(vault_registered, 1);
    let amount = coin.value();

    let coin_name = generate_coin_name<T>();
    let vault = bag::borrow_mut<String, Vault<T>>(&mut gateway.vaults, coin_name);
    let coin_balance = coin.into_balance();
    balance::join(&mut vault.balance, coin_balance);
    // Emit deposit event
    let event = DepositEvent {
        coin_type: coin_name,
        amount: amount,
        depositor: tx_context::sender(ctx),
        receiver: receiver,
    };
    event::emit(event);
}


public fun withdraw<T>(gateway: &mut Gateway, amount:u64, _cap: &WithdrawCap, ctx: &mut TxContext): Coin<T> {
    let vault_registered = is_registered<T>(gateway);
    assert!(vault_registered, 1);
    let coin_name = generate_coin_name<T>();
    let vault = bag::borrow_mut<String, Vault<T>>(&mut gateway.vaults, coin_name);
    let coin_out = coin::take(&mut vault.balance, amount, ctx);
    // transfer::public_transfer(coin_out, tx_context::sender(ctx));
    // amount
    coin_out
}

entry fun withdraw_to_address<T>(gateway: &mut Gateway, amount:u64, recipient: address, cap: &WithdrawCap, ctx: &mut TxContext) {
    let coin = withdraw<T>(gateway, amount, cap, ctx);
    transfer::public_transfer(coin, recipient);
}

// events
public struct DepositEvent has copy, drop {
    coin_type: String,
    amount: u64,
    depositor: address,
    receiver: String, // 0x hex address
}



// query functions
public fun get_vault_balance<T>(gateway: &Gateway): u64 {
    let vault_registered = is_registered<T>(gateway);
    assert!(vault_registered, 1);
    let coin_name = generate_coin_name<T>();
    let vault = bag::borrow<String, Vault<T>>(&gateway.vaults, coin_name);
    balance::value(&vault.balance)
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

   ts::next_tx(&mut scenario, @0xB);
   {
       let mut gateway = scenario.take_shared<Gateway>();
       // create some test coin
       let coin = test_coin(&mut scenario);
       let ethAddr = b"0x7c125C1d515b8945841b3d5144a060115C58725F".to_string().to_ascii();
       deposit(&mut gateway, coin, ethAddr, scenario.ctx());
       ts::return_shared(gateway);
   };

   ts::next_tx(&mut scenario, @0xA);
   {
        let mut gateway = scenario.take_shared<Gateway>();
        let cap = ts::take_from_address<WithdrawCap>(&scenario, @0xA);
        let coins = withdraw<SUI>(&mut gateway, 10, &cap, scenario.ctx());
        assert!(coin::value(&coins) == 10);
        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
        transfer::public_transfer(coins, @0xA);
   };
   ts::next_tx(&mut scenario, @0xA);
   {
       // check the received coin on @0xB
       let coin = ts::take_from_address<Coin<SUI>>(&scenario, @0xA);
       assert!(coin::value(&coin) == 10);
       ts::return_to_address(@0xA, coin);
   };
   ts::end(scenario);
}
