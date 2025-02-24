module gateway::gateway;

use std::ascii::String;
use std::type_name::{get, into_string};
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::event;
use sui::sui::SUI;
use sui::hex::decode;

use sui::bls12381::{bls12381_min_sig_verify,};
// === Errors ===

const EAlreadyWhitelisted: u64 = 0;
const EInvalidReceiverAddress: u64 = 1;
const ENotWhitelisted: u64 = 2;
const ENonceMismatch: u64 = 3;
const EPayloadTooLong: u64 = 4;
const EInactiveWithdrawCap: u64 = 5;
const EInactiveWhitelistCap: u64 = 6;
const EDepositPaused: u64 = 7;

const ReceiverAddressLength: u64 = 42;
const PayloadMaxLength: u64 = 1024;

// === Structs ===

// Vault stores the balance of a specific coin type
public struct Vault<phantom T> has store {
    balance: Balance<T>,
    whitelisted: bool,
}

// Gateway stores the vaults and the nonce for withdrawals
public struct Gateway has key {
    id: UID,
    vaults: Bag,
    nonce: u64,
    active_withdraw_cap: ID,
    active_whitelist_cap: ID,
    deposit_paused: bool,
}

// WithdrawCap is a capability object that allows the caller to withdraw tokens from the gateway
public struct WithdrawCap has key, store {
    id: UID,
}

// WhitelistCap is a capability object that allows the caller to whitelist a new vault
public struct WhitelistCap has key, store {
    id: UID,
}

// AdminCap is a capability object that allows to issue new capabilities
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

public struct WithdrawEvent has copy, drop {
    coin_type: String,
    amount: u64,
    sender: address,
    receiver: address,
    nonce: u64,
}

// === Initialization ===

fun init(ctx: &mut TxContext) {
    // to withdraw tokens from the gateway, the caller must have the WithdrawCap
    let withdraw_cap = WithdrawCap {
        id: object::new(ctx),
    };

    // to whitelist a new vault, the caller must have the WhitelistCap
    let whitelist_cap = WhitelistCap {
        id: object::new(ctx),
    };

    // to whitelist a new vault, the caller must have the AdminCap
    let admin_cap = AdminCap {
        id: object::new(ctx),
    };

    // create and share the gateway object
    let mut gateway = Gateway {
        id: object::new(ctx),
        vaults: bag::new(ctx),
        nonce: 0,
        active_withdraw_cap: object::id(&withdraw_cap),
        active_whitelist_cap: object::id(&whitelist_cap),
        deposit_paused: false,
    };

    // whitelist SUI by default
    whitelist_impl<SUI>(&mut gateway, &whitelist_cap);

    transfer::transfer(withdraw_cap, tx_context::sender(ctx));
    transfer::transfer(whitelist_cap, tx_context::sender(ctx));
    transfer::transfer(admin_cap, tx_context::sender(ctx));
    transfer::share_object(gateway);
}

// === Entrypoints ===

// withdraw allows the TSS to withdraw tokens from the gateway
entry fun withdraw<T>(
    gateway: &mut Gateway,
    amount: u64,
    nonce: u64,
    receiver: address,
    cap: &WithdrawCap,
    ctx: &mut TxContext,
) {
    let coin = withdraw_impl<T>(gateway, amount, nonce, cap, ctx);

    transfer::public_transfer(coin, receiver);

    // Emit event
    event::emit(WithdrawEvent {
        coin_type: coin_name<T>(),
        amount: amount,
        sender: tx_context::sender(ctx),
        receiver: receiver,
        nonce: nonce,
    });
}

// whitelist whitelists a new coin by creating a new vault for the coin type
entry fun whitelist<T>(gateway: &mut Gateway, cap: &WhitelistCap) {
    whitelist_impl<T>(gateway, cap)
}

// unwhitelist unwhitelists a coin by setting the whitelisted flag to false
entry fun unwhitelist<T>(gateway: &mut Gateway, cap: &AdminCap) {
    unwhitelist_impl<T>(gateway, cap)
}

// issue_withdraw_and_whitelist_cap issues a new WithdrawCap and WhitelistCap and revokes the old ones
entry fun issue_withdraw_and_whitelist_cap(
    gateway: &mut Gateway,
    _cap: &AdminCap,
    ctx: &mut TxContext,
) {
    let (withdraw_cap, whitelist_cap) = issue_withdraw_and_whitelist_cap_impl(gateway, _cap, ctx);
    transfer::transfer(withdraw_cap, tx_context::sender(ctx));
    transfer::transfer(whitelist_cap, tx_context::sender(ctx));
}

// pause pauses the deposit functionality
entry fun pause(gateway: &mut Gateway, cap: &AdminCap) {
    pause_impl(gateway, cap)
}

// unpause unpauses the deposit functionality
entry fun unpause(gateway: &mut Gateway, cap: &AdminCap) {
    unpause_impl(gateway, cap)
}

// === Deposit Functions ===

// deposit allows the user to deposit tokens into the gateway
public entry fun deposit<T>(
    gateway: &mut Gateway,
    coin: Coin<T>,
    receiver: String,
    ctx: &mut TxContext,
) {
    let amount = coin.value();
    let coin_name = coin_name<T>();

    check_receiver_and_deposit_to_vault(gateway, coin, receiver);

    // Emit deposit event
    event::emit(DepositEvent {
        coin_type: coin_name,
        amount: amount,
        sender: tx_context::sender(ctx),
        receiver: receiver,
    });
}

// deposit_and_call allows the user to deposit tokens into the gateway and call a contract
public entry fun deposit_and_call<T>(
    gateway: &mut Gateway,
    coin: Coin<T>,
    receiver: String,
    payload: vector<u8>,
    ctx: &mut TxContext,
) {
    assert!(payload.length() <= PayloadMaxLength, EPayloadTooLong);

    let amount = coin.value();
    let coin_name = coin_name<T>();

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
    assert!(!gateway.deposit_paused, EDepositPaused);

    // Deposit the coin into the vault
    let coin_name = coin_name<T>();
    let vault = bag::borrow_mut<String, Vault<T>>(&mut gateway.vaults, coin_name);
    balance::join(&mut vault.balance, coin.into_balance());
}

// === Withdraw Functions ===

public fun withdraw_impl<T>(
    gateway: &mut Gateway,
    amount: u64,
    nonce: u64,
    cap: &WithdrawCap,
    ctx: &mut TxContext,
): Coin<T> {
    assert!(gateway.active_withdraw_cap == object::id(cap), EInactiveWithdrawCap);
    assert!(is_whitelisted<T>(gateway), ENotWhitelisted);
    assert!(nonce == gateway.nonce, ENonceMismatch); // prevent replay
    gateway.nonce = nonce + 1;

    // Withdraw the coin from the vault
    let coin_name = coin_name<T>();
    let vault = bag::borrow_mut<String, Vault<T>>(&mut gateway.vaults, coin_name);
    let coin_out = coin::take(&mut vault.balance, amount, ctx);

    coin_out
}

// === Admin Functions ===

public fun whitelist_impl<T>(gateway: &mut Gateway, cap: &WhitelistCap) {
    assert!(gateway.active_whitelist_cap == object::id(cap), EInactiveWhitelistCap);
    assert!(is_whitelisted<T>(gateway) == false, EAlreadyWhitelisted);

    // if the vault already exists, set it to whitelisted, otherwise create a new vault
    if (bag::contains_with_type<String, Vault<T>>(&gateway.vaults, coin_name<T>())) {
        let vault = bag::borrow_mut<String, Vault<T>>(&mut gateway.vaults, coin_name<T>());
        vault.whitelisted = true;
    } else {
        let vault_name = coin_name<T>();
        let vault = Vault<T> {
            balance: balance::zero<T>(),
            whitelisted: true,
        };
        bag::add(&mut gateway.vaults, vault_name, vault);
    }
}

public fun unwhitelist_impl<T>(gateway: &mut Gateway, _cap: &AdminCap) {
    assert!(is_whitelisted<T>(gateway), ENotWhitelisted);
    let vault = bag::borrow_mut<String, Vault<T>>(&mut gateway.vaults, coin_name<T>());
    vault.whitelisted = false;
}

public fun issue_withdraw_and_whitelist_cap_impl(
    gateway: &mut Gateway,
    _cap: &AdminCap,
    ctx: &mut TxContext,
): (WithdrawCap, WhitelistCap) {
    let withdraw_cap = WithdrawCap {
        id: object::new(ctx),
    };
    let whitelist_cap = WhitelistCap {
        id: object::new(ctx),
    };
    gateway.active_withdraw_cap = object::id(&withdraw_cap);
    gateway.active_whitelist_cap = object::id(&whitelist_cap);
    (withdraw_cap, whitelist_cap)
}

public fun pause_impl(gateway: &mut Gateway, _cap: &AdminCap) {
    gateway.deposit_paused = true;
}

public fun unpause_impl(gateway: &mut Gateway, _cap: &AdminCap) {
    gateway.deposit_paused = false;
}

// === View Functions ===

public fun nonce(gateway: &Gateway): u64 {
    gateway.nonce
}

public fun active_withdraw_cap(gateway: &Gateway): ID {
    gateway.active_withdraw_cap
}

public fun active_whitelist_cap(gateway: &Gateway): ID {
    gateway.active_whitelist_cap
}

public fun vault_balance<T>(gateway: &Gateway): u64 {
    if (!is_whitelisted<T>(gateway)) {
        return 0
    };
    let coin_name = coin_name<T>();
    let vault = bag::borrow<String, Vault<T>>(&gateway.vaults, coin_name);
    balance::value(&vault.balance)
}

public fun is_paused(gateway: &Gateway): bool {
    gateway.deposit_paused
}

// is_whitelisted returns true if a given coin type is whitelisted
public fun is_whitelisted<T>(gateway: &Gateway): bool {
    let vault_name = coin_name<T>();
    if (!bag::contains_with_type<String, Vault<T>>(&gateway.vaults, vault_name)) {
        return false
    };
    let vault = bag::borrow<String, Vault<T>>(&gateway.vaults, vault_name);
    vault.whitelisted
}

// === Helpers ===

// coin_name returns the name of the coin type to index the vault
fun coin_name<T>(): String {
    into_string(get<T>())
}



// === Test Helpers ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public fun create_test_withdraw_cap(ctx: &mut TxContext): WithdrawCap {
    WithdrawCap {
        id: object::new(ctx),
    }
}

#[test_only]
public fun create_test_whitelist_cap(ctx: &mut TxContext): WhitelistCap {
    WhitelistCap {
        id: object::new(ctx),
    }
}

#[test]
public fun test_bls12381_min_sig_verify() {
    let msg  = b"Hello BLS";
    let sig = decode(b"94138847ea1e9b6723bbdfc689b3f106a36d1630f13a87e5dcb542d84dc95c56b961a6b6a5564c371723c355e1a87e3c");
    let pk = decode(b"83bd626a1f81bfe207032acac50127ad0807bd469c24d03fe006bb94a46047705e5f10f5ff7b93077dbeef7c4886c78b0158128021c5e33394166b8458a20bf6883ba90b1bc810343ef8104d1da2a801cae9cf354eb1a3c9c57025dffb971419");
    assert!(sig.length() == 48, 1);
    assert!(pk.length() == 96, 2);
    let valid = bls12381_min_sig_verify(&sig, &pk, &msg);
    assert!(valid, 3);
}
