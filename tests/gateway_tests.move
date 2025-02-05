#[test_only]
module gateway::gateway_tests;

use gateway::fake_usdc::{FAKE_USDC, init_for_testing as init_fake_usdc};
use gateway::gateway::{
    Gateway,
    whitelist_impl,
    deposit_impl,
    deposit_and_call_impl,
    withdraw_impl,
    is_whitelisted,
    WithdrawCap,
    WhitelistCap,
    init_for_testing,
    ENonceMismatch,
    get_vault_balance
};
use sui::coin::{Self, Coin};

#[test_only]
const AmountTest: u64 = 42;

#[test_only]
use sui::sui::SUI;
#[test_only]
use sui::test_scenario::{Self as ts, Scenario};
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
        let ethAddr = b"0x7c125C1d515b8945841b3d5144a060115C58725F".to_string().to_ascii();
        deposit_impl(&mut gateway, coin, ethAddr, scenario.ctx());
        assert!(get_vault_balance<SUI>(&gateway) == AmountTest);

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
        let ethAddr = b"0x7c125C1d515b8945841b3d5144a060115C58725F".to_string().to_ascii();

        let balance_before = get_vault_balance<SUI>(&gateway);

        deposit_and_call_impl(&mut gateway, coin, ethAddr, b"hello", scenario.ctx());

        let balance_after = get_vault_balance<SUI>(&gateway);
        assert!(balance_after == balance_before + AmountTest);

        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test]
fun test_whitelist_deposit_withdraw() {
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

#[test]
fun test_fake_usdc_coin() {
    let mut scenario = ts::begin(@0xA);
    ts::next_tx(&mut scenario, @0xA);
    {
        init_for_testing(scenario.ctx());
        init_fake_usdc(scenario.ctx());
    };

    ts::next_tx(&mut scenario, @0xA);
    {
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
        let mut gateway = scenario.take_shared<Gateway>();
        // ts::take_from_address< sui::coin::TreasuryCap<gateway::fake_usdc::FAKE_USDC>>(&scenario, @0xA);
        let coin = coin::mint_for_testing<FAKE_USDC>(AmountTest, scenario.ctx());
        assert!(coin::value(&coin) == AmountTest);

        let ethAddr = b"0x7c125C1d515b8945841b3d5144a060115C58725F".to_string().to_ascii();
        deposit_impl(&mut gateway, coin, ethAddr, scenario.ctx());
        assert!(get_vault_balance<FAKE_USDC>(&gateway) == AmountTest);

        ts::return_shared(gateway);
    };
    ts::next_tx(&mut scenario, @0xA);
    {
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
