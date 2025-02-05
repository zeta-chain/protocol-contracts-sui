module gateway::gateway;

use std::ascii::String;
use std::type_name::{get, into_string};
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::event;

// === Errors ===

const EAlreadyWhitelisted: u64 = 0;
const EInvalidReceiverAddress: u64 = 1;
const ENotWhitelisted: u64 = 2;
const ENonceMismatch: u64 = 3;
const EPayloadTooLong: u64 = 4;

const ReceiverAddressLength: u64 = 42;
const PayloadMaxLength: u64 = 1024;

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

// AdminCap is a capability object that allows the caller to whitelist a new vault
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

// DepositAndCallEvent is emitted when a user deposits tokens into the gateway with a call
public struct DepositAndCallEvent has copy, drop {
    coin_type: String,
    amount: u64,
    sender: address,
    receiver: String, // 0x hex address
    payload: vector<u8>,
}

// === Initialization ===

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

    // to whitelist a new vault, the caller must have the AdminCap
    let admin_cap = AdminCap {
        id: object::new(ctx),
    };
    transfer::transfer(admin_cap, tx_context::sender(ctx));
}

// === Deposit Functions ===

// deposit allows the user to deposit tokens into the gateway
entry fun deposit<T>(gateway: &mut Gateway, coin: Coin<T>, receiver: String, ctx: &mut TxContext) {
    deposit_impl(gateway, coin, receiver, ctx)
}

// deposit_and_call allows the user to deposit tokens into the gateway and call a contract
entry fun deposit_and_call<T>(
    gateway: &mut Gateway,
    coin: Coin<T>,
    receiver: String,
    payload: vector<u8>,
    ctx: &mut TxContext,
) {
    deposit_and_call_impl(gateway, coin, receiver, payload, ctx)
}

public fun deposit_impl<T>(
    gateway: &mut Gateway,
    coin: Coin<T>,
    receiver: String,
    ctx: &mut TxContext,
) {
    let amount = coin.value();
    let coin_name = get_coin_name<T>();

    check_receiver_and_deposit_to_vault(gateway, coin, receiver);

    // Emit deposit event
    event::emit(DepositEvent {
        coin_type: coin_name,
        amount: amount,
        sender: tx_context::sender(ctx),
        receiver: receiver,
    });
}

public fun deposit_and_call_impl<T>(
    gateway: &mut Gateway,
    coin: Coin<T>,
    receiver: String,
    payload: vector<u8>,
    ctx: &mut TxContext,
) {
    assert!(payload.length() <= PayloadMaxLength, EPayloadTooLong);

    let amount = coin.value();
    let coin_name = get_coin_name<T>();

    check_receiver_and_deposit_to_vault(gateway, coin, receiver);

    // Emit deposit event
    event::emit(DepositAndCallEvent {
        coin_type: coin_name,
        amount: amount,
        sender: tx_context::sender(ctx),
        receiver: receiver,
        payload: payload,
    });
}

// check_receiver_and_deposit_to_vault is a helper function that checks the receiver address and deposits the coin
fun check_receiver_and_deposit_to_vault<T>(gateway: &mut Gateway, coin: Coin<T>, receiver: String) {
    assert!(receiver.length() == ReceiverAddressLength, EInvalidReceiverAddress);
    assert!(is_whitelisted<T>(gateway), ENotWhitelisted);

    // Deposit the coin into the vault
    let coin_name = get_coin_name<T>();
    let vault = bag::borrow_mut<String, Vault<T>>(&mut gateway.vaults, coin_name);
    balance::join(&mut vault.balance, coin.into_balance());
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
    assert!(is_whitelisted<T>(gateway), ENotWhitelisted);
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
    if (!is_whitelisted<T>(gateway)) {
        return 0
    };
    let coin_name = get_coin_name<T>();
    let vault = bag::borrow<String, Vault<T>>(&gateway.vaults, coin_name);
    balance::value(&vault.balance)
}

// is_whitelisted returns true if a given coin type is whitelisted
public fun is_whitelisted<T>(gateway: &Gateway): bool {
    let vault_name = get_coin_name<T>();
    bag::contains_with_type<String, Vault<T>>(&gateway.vaults, vault_name)
}

// === Admin Functions ===

// whitelist whitelists a new coin by creating a new vault for the coin type
public fun whitelist<T>(gateway: &mut Gateway, _cap: &AdminCap) {
    assert!(is_whitelisted<T>(gateway) == false, EAlreadyWhitelisted);
    let vault_name = get_coin_name<T>();
    let vault = Vault<T> {
        balance: balance::zero<T>(),
    };
    bag::add(&mut gateway.vaults, vault_name, vault);
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
