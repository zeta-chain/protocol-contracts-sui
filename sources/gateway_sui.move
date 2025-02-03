module gateway_sui::gateway;

use sui::coin::{Self,Coin};
use std::ascii::{String};
use sui::balance::{Self,Balance};
use sui::bag::{Self,Bag};
use std::type_name::{get, into_string};
use sui::event;

// === Errors ===
const EVaultAlreadyRegistered: u64 = 0;
const EReceiverAddressInvalid: u64 = 1;
const EVaultNotRegistered: u64 = 2;
const ENonceMismatch: u64 = 3;

// === Structs ===

public struct Vault<phantom T> has store {
    balance: Balance<T>,
}

public struct Gateway has key {
    id: UID,
    vaults: Bag,
    nonce: u64,
}

public struct WithdrawCap has key, store {
    id: UID,
}

public struct AdminCap has key, store {
    id: UID,
}

// === Events ===
public struct DepositEvent has copy, drop {
    coin_type: String,
    amount: u64,
    depositor: address,
    receiver: String, // 0x hex address
}



fun init(ctx: &mut TxContext)  {
    let gateway = Gateway {
        id: object::new(ctx),
        vaults: bag::new(ctx),
        nonce: 0,
    };

    // to withdraw tokens from the gateway, the caller must have the WithdrawCap
    let withdraw_cap = WithdrawCap {
        id: object::new(ctx),
    };
    transfer::transfer(withdraw_cap, tx_context::sender(ctx));
    transfer::share_object(gateway);

    // to register a new vault, the caller must have the AdminCap
    let admin_cap = AdminCap {
        id: object::new(ctx),
    };
    transfer::transfer(admin_cap, tx_context::sender(ctx));
}

public fun generate_coin_name<T>(): String {
   into_string(get<T>())
}

// add a capability object to restrict the priviledge of register_vault, liek the WithdrawCap
public fun register_vault<T>(gateway: &mut Gateway, _cap: &AdminCap) {
    assert!(is_registered<T>(gateway) == false, EVaultAlreadyRegistered);
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
    assert!(receiver.length() == 42, EReceiverAddressInvalid);
    let vault_registered = is_registered<T>(gateway);
    assert!(vault_registered, EVaultNotRegistered);
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


public fun withdraw<T>(gateway: &mut Gateway, amount:u64, nonce:u64,  _cap: &WithdrawCap, ctx: &mut TxContext): Coin<T> {
    let vault_registered = is_registered<T>(gateway);
    assert!(vault_registered, EVaultNotRegistered);
    assert!(nonce == gateway.nonce, ENonceMismatch); // prevent replay
    let coin_name = generate_coin_name<T>();
    let vault = bag::borrow_mut<String, Vault<T>>(&mut gateway.vaults, coin_name);
    let coin_out = coin::take(&mut vault.balance, amount, ctx);
    gateway.nonce = nonce + 1;
    coin_out
}

entry fun withdraw_to_address<T>(gateway: &mut Gateway, amount:u64, nonce:u64, recipient: address,  cap: &WithdrawCap, ctx: &mut TxContext) {
    let coin = withdraw<T>(gateway, amount, nonce, cap, ctx);
    transfer::public_transfer(coin, recipient);
}


// === View Functions ===
public fun nonce(gateway: &Gateway): u64 {
    gateway.nonce
}

public fun get_vault_balance<T>(gateway: &Gateway): u64 {
    let vault_registered = is_registered<T>(gateway);
    assert!(vault_registered, EVaultNotRegistered);
    let coin_name = generate_coin_name<T>();
    let vault = bag::borrow<String, Vault<T>>(&gateway.vaults, coin_name);
    balance::value(&vault.balance)
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}
