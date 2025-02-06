#[test_only]
module gateway::gateway_tests;

use gateway::fake_usdc::{FAKE_USDC, init_for_testing as init_fake_usdc};
use gateway::gateway::{
    Gateway,
    whitelist_impl,
    deposit_impl,
    deposit_and_call_impl,
    issue_withdraw_and_whitelist_cap_impl,
    withdraw_impl,
    is_whitelisted,
    vault_balance,
    active_withdraw_cap,
    active_whitelist_cap,
    WithdrawCap,
    WhitelistCap,
    AdminCap,
    init_for_testing,
    create_test_withdraw_cap,
    create_test_whitelist_cap,
    ENonceMismatch,
    EInvalidReceiverAddress,
    ENotWhitelisted,
    EInactiveWithdrawCap,
    EInactiveWhitelistCap,
    EAlreadyWhitelisted
};
use sui::coin::{Self, Coin};

#[test_only]
use sui::sui::SUI;
#[test_only]
use sui::test_scenario::{Self as ts, Scenario};

#[test_only]
const AmountTest: u64 = 42;

#[test_only]
const ValidEthAddr: vector<u8> = b"0x7c125C1d515b8945841b3d5144a060115C58725F";

#[test_only]
fun test_coin(ts: &mut Scenario): Coin<SUI> {
    coin::mint_for_testing<SUI>(AmountTest, ts.ctx())
}

#[test_only]
fun setup(scenario: &mut Scenario) {
    ts::next_tx(scenario, @0xA);
    {
        init_for_testing(scenario.ctx());
    };
    ts::next_tx(scenario, @0xA);
    {
        // create gateway and whitelist SUI
        let mut gateway = scenario.take_shared<Gateway>();
        let whitelist_cap = ts::take_from_address<WhitelistCap>(scenario, @0xA);
        whitelist_impl<SUI>(&mut gateway, &whitelist_cap);
        assert!(is_whitelisted<SUI>(&gateway));
        ts::return_shared(gateway);
        ts::return_to_address(@0xA, whitelist_cap);
    };

    ts::next_tx(scenario, @0xB);
    {
        // deposit SUI
        let mut gateway = scenario.take_shared<Gateway>();

        // create some test coin
        let coin = test_coin(scenario);
        let eth_addr = ValidEthAddr.to_string().to_ascii();
        deposit_impl(&mut gateway, coin, eth_addr, scenario.ctx());
        assert!(vault_balance<SUI>(&gateway) == AmountTest);

        ts::return_shared(gateway);
    };
}

#[test]
fun test_deposit_and_call() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();

        let coin = test_coin(&mut scenario);
        let eth_addr = ValidEthAddr.to_string().to_ascii();

        let balance_before = vault_balance<SUI>(&gateway);

        deposit_and_call_impl(&mut gateway, coin, eth_addr, b"hello", scenario.ctx());

        let balance_after = vault_balance<SUI>(&gateway);
        assert!(balance_after == balance_before + AmountTest);

        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EInvalidReceiverAddress)]
fun test_deposit_invalid_address() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();

        let coin = test_coin(&mut scenario);
        let eth_addr = b"0x7c125C1d515b8945841b3d5144a060115C58725Fa".to_string().to_ascii();

        deposit_impl(&mut gateway, coin, eth_addr, scenario.ctx());

        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = ENotWhitelisted)]
fun test_deposit_not_whitelisted() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();

        let coin = coin::mint_for_testing<FAKE_USDC>(AmountTest, scenario.ctx());
        let eth_addr = ValidEthAddr.to_string().to_ascii();

        deposit_impl(&mut gateway, coin, eth_addr, scenario.ctx());

        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EInvalidReceiverAddress)]
fun test_deposit_and_call_invalid_address() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();

        let coin = test_coin(&mut scenario);
        let eth_addr = b"0x7c125C1d515b8945841b3d5144a060115C58725Fa".to_string().to_ascii();

        deposit_and_call_impl(&mut gateway, coin, eth_addr, b"hello", scenario.ctx());

        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = ENotWhitelisted)]
fun test_deposit_and_call_not_whitelisted() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();

        let coin = coin::mint_for_testing<FAKE_USDC>(AmountTest, scenario.ctx());
        let eth_addr = ValidEthAddr.to_string().to_ascii();

        deposit_and_call_impl(&mut gateway, coin, eth_addr, b"hello", scenario.ctx());

        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test]
fun test_withdraw() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let cap = ts::take_from_address<WithdrawCap>(&scenario, @0xA);
        let nonce = gateway.nonce();
        let coins = withdraw_impl<SUI>(&mut gateway, 10, nonce, &cap, scenario.ctx());
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

#[test, expected_failure(abort_code = EInactiveWithdrawCap)]
fun test_withdraw_inactive_withdraw_cap() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let cap = create_test_withdraw_cap(scenario.ctx());
        let nonce = gateway.nonce();
        let coins = withdraw_impl<SUI>(&mut gateway, 10, nonce, &cap, scenario.ctx());
        assert!(coin::value(&coins) == 10);
        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
        transfer::public_transfer(coins, @0xA);
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
        let coins = withdraw_impl<SUI>(&mut gateway, 10, nonce, &cap, scenario.ctx());
        assert!(coin::value(&coins) == 10);
        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
        transfer::public_transfer(coins, @0xA);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EInactiveWhitelistCap)]
fun test_whitelist_inactive_whitelist_cap() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let cap = create_test_whitelist_cap(scenario.ctx());
        whitelist_impl<FAKE_USDC>(&mut gateway, &cap);
        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EAlreadyWhitelisted)]
fun test_whitelist_already_whitelisted() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let cap = ts::take_from_address<WhitelistCap>(&scenario, @0xA);
        whitelist_impl<SUI>(&mut gateway, &cap);
        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test]
fun test_issue_withdraw_and_whitelist_cap() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, @0xA);
        let (withdraw_cap, whitelist_cap) = issue_withdraw_and_whitelist_cap_impl(
            &mut gateway,
            &admin_cap,
            scenario.ctx(),
        );
        assert!(active_withdraw_cap(&gateway) == object::id(&withdraw_cap));
        assert!(active_whitelist_cap(&gateway) == object::id(&whitelist_cap));

        // can withdraw with new cap
        let nonce = gateway.nonce();
        let coins = withdraw_impl<SUI>(&mut gateway, 10, nonce, &withdraw_cap, scenario.ctx());
        transfer::public_transfer(coins, @0xA);

        // can whitelist with new cap
        whitelist_impl<FAKE_USDC>(&mut gateway, &whitelist_cap);

        transfer::public_freeze_object(withdraw_cap);
        transfer::public_freeze_object(whitelist_cap);
        ts::return_to_address(@0xA, admin_cap);
        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EInactiveWithdrawCap)]
fun test_issue_withdraw_and_whitelist_cap_revoke_withdraw() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, @0xA);
        let old_withdraw_cap = ts::take_from_address<WithdrawCap>(&scenario, @0xA);

        let (withdraw_cap, whitelist_cap) = issue_withdraw_and_whitelist_cap_impl(
            &mut gateway,
            &admin_cap,
            scenario.ctx(),
        );

        let nonce = gateway.nonce();
        let coins = withdraw_impl<SUI>(&mut gateway, 10, nonce, &old_withdraw_cap, scenario.ctx());
        transfer::public_transfer(coins, @0xA);

        transfer::public_freeze_object(withdraw_cap);
        transfer::public_freeze_object(whitelist_cap);
        ts::return_to_address(@0xA, admin_cap);
        ts::return_to_address(@0xA, old_withdraw_cap);
        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EInactiveWhitelistCap)]
fun test_issue_withdraw_and_whitelist_cap_revoke_whitelist() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, @0xA);
        let old_whitelist_cap = ts::take_from_address<WhitelistCap>(&scenario, @0xA);

        let (withdraw_cap, whitelist_cap) = issue_withdraw_and_whitelist_cap_impl(
            &mut gateway,
            &admin_cap,
            scenario.ctx(),
        );
        whitelist_impl<FAKE_USDC>(&mut gateway, &old_whitelist_cap);

        transfer::public_freeze_object(withdraw_cap);
        transfer::public_freeze_object(whitelist_cap);
        ts::return_to_address(@0xA, admin_cap);
        ts::return_to_address(@0xA, old_whitelist_cap);
        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test]
fun test_custom_coin() {
    let mut scenario = ts::begin(@0xA);
    ts::next_tx(&mut scenario, @0xA);
    {
        init_for_testing(scenario.ctx());
        init_fake_usdc(scenario.ctx());
    };

    ts::next_tx(&mut scenario, @0xA);
    {
        // whitelist FAKE_USDC
        let mut gateway = scenario.take_shared<Gateway>();
        let whitelist_cap = ts::take_from_address<WhitelistCap>(&scenario, @0xA);
        whitelist_impl<FAKE_USDC>(&mut gateway, &whitelist_cap);
        let b = is_whitelisted<FAKE_USDC>(&gateway);
        assert!(b);
        ts::return_shared(gateway);
        ts::return_to_address(@0xA, whitelist_cap);
    };
    ts::next_tx(&mut scenario, @0xA);
    {
        // deposit FAKE_USDC
        let mut gateway = scenario.take_shared<Gateway>();
        // ts::take_from_address< sui::coin::TreasuryCap<gateway::fake_usdc::FAKE_USDC>>(&scenario, @0xA);
        let coin = coin::mint_for_testing<FAKE_USDC>(AmountTest, scenario.ctx());
        assert!(coin::value(&coin) == AmountTest);

        let ethAddr = ValidEthAddr.to_string().to_ascii();
        deposit_impl(&mut gateway, coin, ethAddr, scenario.ctx());
        assert!(vault_balance<FAKE_USDC>(&gateway) == AmountTest);

        ts::return_shared(gateway);
    };
    ts::next_tx(&mut scenario, @0xA);
    {
        // withdraw FAKE_USDC
        let mut gateway = scenario.take_shared<Gateway>();
        let cap = ts::take_from_address<WithdrawCap>(&scenario, @0xA);
        let nonce = gateway.nonce();
        let coins = withdraw_impl<FAKE_USDC>(&mut gateway, 13, nonce, &cap, scenario.ctx());
        assert!(coin::value(&coins) == 13);
        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
        transfer::public_transfer(coins, @0xA);
    };
    ts::end(scenario);
}
