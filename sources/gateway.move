module gateway::gateway;

use std::ascii::String;
use std::type_name::{get, into_string};
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::event;

// === Errors ===

const EVaultAlreadyRegistered: u64 = 0;
const EInvalidReceiverAddress: u64 = 1;
const EVaultNotRegistered: u64 = 2;
const ENonceMismatch: u64 = 3;

const ReceiverAddressLength: u64 = 42;

// === Structs ===

// Vault stores the balance of a specific coin type
public struct Vault<phantom T> has store {
    balance: Balance<T>,
}

// Gateway stores the vaults and the nonce for withdrawals
public struct Gateway has key {
    id: UID,
    vaults: Bag,
    nonce: u64,
}

// WithdrawCap is a capability object that allows the caller to withdraw tokens from the gateway
public struct WithdrawCap has key, store {
    id: UID,
}

// AdminCap is a capability object that allows the caller to register a new vault
public struct AdminCap has key, store {
    id: UID,
}

// === Events ===

// DepositEvent is emitted when a user deposits tokens into the gateway
public struct DepositEvent has copy, drop {
    coin_type: String,
    amount: u64,
    sender: address,
    receiver: String, // 0x hex address
}

fun init(ctx: &mut TxContext) {
    let gateway = Gateway {
        id: object::new(ctx),
        vaults: bag::new(ctx),
        nonce: 0,
    };
    transfer::share_object(gateway);

    // to withdraw tokens from the gateway, the caller must have the WithdrawCap
    let withdraw_cap = WithdrawCap {
        id: object::new(ctx),
    };
    transfer::transfer(withdraw_cap, tx_context::sender(ctx));

    // to register a new vault, the caller must have the AdminCap
    let admin_cap = AdminCap {
        id: object::new(ctx),
    };
    transfer::transfer(admin_cap, tx_context::sender(ctx));
}

// === Deposit Functions ===

// deposit allows the user to deposit tokens into the gateway
public fun deposit<T>(gateway: &mut Gateway, coin: Coin<T>, receiver: String, ctx: &mut TxContext) {
    assert!(receiver.length() == ReceiverAddressLength, EInvalidReceiverAddress);
    assert!(is_registered<T>(gateway), EVaultNotRegistered);

    // Deposit the coin into the vault
    let amount = coin.value();
    let coin_name = get_coin_name<T>();
    let vault = bag::borrow_mut<String, Vault<T>>(&mut gateway.vaults, coin_name);
    let coin_balance = coin.into_balance();
    balance::join(&mut vault.balance, coin_balance);

    // Emit deposit event
    event::emit(DepositEvent {
        coin_type: coin_name,
        amount: amount,
        sender: tx_context::sender(ctx),
        receiver: receiver,
    });
}

// === Withdraw Functions ===

// withdraw allows the TSS to withdraw tokens from the gateway
entry fun withdraw<T>(
    gateway: &mut Gateway,
    amount: u64,
    nonce: u64,
    recipient: address,
    cap: &WithdrawCap,
    ctx: &mut TxContext,
) {
    let coin = withdraw_impl<T>(gateway, amount, nonce, cap, ctx);
    transfer::public_transfer(coin, recipient);
}

public fun withdraw_impl<T>(
    gateway: &mut Gateway,
    amount: u64,
    nonce: u64,
    _cap: &WithdrawCap,
    ctx: &mut TxContext,
): Coin<T> {
    assert!(is_registered<T>(gateway), EVaultNotRegistered);
    assert!(nonce == gateway.nonce, ENonceMismatch); // prevent replay
    gateway.nonce = nonce + 1;

    // Withdraw the coin from the vault
    let coin_name = get_coin_name<T>();
    let vault = bag::borrow_mut<String, Vault<T>>(&mut gateway.vaults, coin_name);
    let coin_out = coin::take(&mut vault.balance, amount, ctx);
    coin_out
}

// === View Functions ===

public fun nonce(gateway: &Gateway): u64 {
    gateway.nonce
}

public fun get_vault_balance<T>(gateway: &Gateway): u64 {
    if (!is_registered<T>(gateway)) {
        return 0
    };
    let coin_name = get_coin_name<T>();
    let vault = bag::borrow<String, Vault<T>>(&gateway.vaults, coin_name);
    balance::value(&vault.balance)
}

// === Admin Functions ===

// register_vault registers a new vault for a specific coin type
public fun register_vault<T>(gateway: &mut Gateway, _cap: &AdminCap) {
    assert!(is_registered<T>(gateway) == false, EVaultAlreadyRegistered);
    let vault_name = get_coin_name<T>();
    let vault = Vault<T> {
        balance: balance::zero<T>(),
    };
    bag::add(&mut gateway.vaults, vault_name, vault);
}

// is_registered returns true if a vault for the given coin type is registered
public fun is_registered<T>(gateway: &Gateway): bool {
    let vault_name = get_coin_name<T>();
    bag::contains_with_type<String, Vault<T>>(&gateway.vaults, vault_name)
}

// === Helpers ===

// get_coin_name returns the name of the coin type to index the vault
fun get_coin_name<T>(): String {
    into_string(get<T>())
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}
