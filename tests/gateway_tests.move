#[test_only]
module gateway::gateway_tests;

use gateway::fake_usdc::{FAKE_USDC, init_for_testing as init_fake_usdc};
use gateway::gateway::{
    Gateway,
    whitelist_impl,
    unwhitelist_impl,
    deposit,
    deposit_and_call,
    issue_withdraw_and_whitelist_cap_impl,
    pause,
    unpause,
    is_paused,
    reset_nonce,
    increase_nonce,
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
    EAlreadyWhitelisted,
    EDepositPaused
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

    ts::next_tx(scenario, @0xB);
    {
        // deposit SUI
        let mut gateway = scenario.take_shared<Gateway>();
        let coin = test_coin(scenario);
        let eth_addr = ValidEthAddr.to_string().to_ascii();
        deposit(&mut gateway, coin, eth_addr, scenario.ctx());
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

        deposit_and_call(&mut gateway, coin, eth_addr, b"hello", scenario.ctx());

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

        deposit(&mut gateway, coin, eth_addr, scenario.ctx());

        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EInvalidReceiverAddress)]
fun test_deposit_invalid_address_2() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();

        let coin = test_coin(&mut scenario);
        let eth_addr = b"0xg531a5aB847ff5B22D855633C25ED1DA3255247e".to_string().to_ascii();

        deposit(&mut gateway, coin, eth_addr, scenario.ctx());

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

        deposit(&mut gateway, coin, eth_addr, scenario.ctx());

        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EDepositPaused)]
fun test_deposit_paused() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, @0xA);

        let coin = test_coin(&mut scenario);
        let eth_addr = ValidEthAddr.to_string().to_ascii();

        pause(&mut gateway, &admin_cap);
        deposit(&mut gateway, coin, eth_addr, scenario.ctx());

        ts::return_to_address(@0xA, admin_cap);
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

        deposit_and_call(&mut gateway, coin, eth_addr, b"hello", scenario.ctx());

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

        deposit_and_call(&mut gateway, coin, eth_addr, b"hello", scenario.ctx());

        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EDepositPaused)]
fun test_deposit_and_call_paused() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, @0xA);

        let coin = test_coin(&mut scenario);
        let eth_addr = ValidEthAddr.to_string().to_ascii();

        pause(&mut gateway, &admin_cap);
        deposit_and_call(&mut gateway, coin, eth_addr, b"hello", scenario.ctx());

        ts::return_to_address(@0xA, admin_cap);
        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test]
fun test_pause_and_resume_deposit() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, @0xA);

        let coin = test_coin(&mut scenario);
        let eth_addr = ValidEthAddr.to_string().to_ascii();

        pause(&mut gateway, &admin_cap);
        assert!(is_paused(&gateway));
        unpause(&mut gateway, &admin_cap);
        assert!(!is_paused(&gateway));
        deposit(&mut gateway, coin, eth_addr, scenario.ctx());

        ts::return_to_address(@0xA, admin_cap);
        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test]
fun test_reset_nonce() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, @0xA);
        assert!(gateway.nonce() == 0);
        reset_nonce(&mut gateway, 10, &admin_cap);
        assert!(gateway.nonce() == 10);
                reset_nonce(&mut gateway, 42, &admin_cap);
        assert!(gateway.nonce() == 42);
                reset_nonce(&mut gateway, 0, &admin_cap);
        assert!(gateway.nonce() == 0);
        ts::return_shared(gateway);
        ts::return_to_address(@0xA, admin_cap);
    };
    ts::end(scenario);
}

#[test]
fun test_increase_nonce() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let cap = ts::take_from_address<WithdrawCap>(&scenario, @0xA);
        let nonce = gateway.nonce();
        increase_nonce(&mut gateway, nonce, &cap, scenario.ctx());
        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
    };
    ts::next_tx(&mut scenario, @0xA);
    {
        let gateway = scenario.take_shared<Gateway>();
        assert!(gateway.nonce() == 1);
        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EInactiveWithdrawCap)]
fun test_test_increase_nonce_inactive_withdraw_cap() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let cap = create_test_withdraw_cap(scenario.ctx());
        let nonce = gateway.nonce();
        increase_nonce(&mut gateway, nonce, &cap, scenario.ctx());
        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = ENonceMismatch)]
fun test_test_increase_nonce_wrong_nonce() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let cap = ts::take_from_address<WithdrawCap>(&scenario, @0xA);
        let nonce = gateway.nonce() + 1; // intentially create a mismatch
        increase_nonce(&mut gateway, nonce, &cap, scenario.ctx());
        ts::return_to_address(@0xA, cap);
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
        let (coins, coins_gas) = withdraw_impl<SUI>(
            &mut gateway,
            10,
            nonce,
            5,
            &cap,
            scenario.ctx(),
        );
        assert!(coin::value(&coins) == 10);
        assert!(coin::value(&coins_gas) == 5);
        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
        transfer::public_transfer(coins, @0xA);
        transfer::public_transfer(coins_gas, @0xB);
    };
    ts::next_tx(&mut scenario, @0xA);
    {
        // check nonce and received coins
        let gateway = scenario.take_shared<Gateway>();
        assert!(gateway.nonce() == 1);
        let coin = ts::take_from_address<Coin<SUI>>(&scenario, @0xA);
        assert!(coin::value(&coin) == 10);
        let coin_gas = ts::take_from_address<Coin<SUI>>(&scenario, @0xB);
        assert!(coin::value(&coin_gas) == 5);
        ts::return_to_address(@0xA, coin);
        ts::return_to_address(@0xB, coin_gas);
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
        let (coins, coins_gas) = withdraw_impl<SUI>(
            &mut gateway,
            10,
            nonce,
            5,
            &cap,
            scenario.ctx(),
        );
        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
        transfer::public_transfer(coins, @0xA);
        transfer::public_transfer(coins_gas, @0xA);
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
        let (coins, coins_gas) = withdraw_impl<SUI>(
            &mut gateway,
            10,
            nonce,
            5,
            &cap,
            scenario.ctx(),
        );
        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
        transfer::public_transfer(coins, @0xA);
        transfer::public_transfer(coins_gas, @0xA);
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
        let (coins, coins_gas) = withdraw_impl<SUI>(
            &mut gateway,
            10,
            nonce,
            5,
            &withdraw_cap,
            scenario.ctx(),
        );
        transfer::public_transfer(coins, @0xA);
        transfer::public_transfer(coins_gas, @0xA);

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
        let (coins, coins_gas) = withdraw_impl<SUI>(
            &mut gateway,
            10,
            nonce,
            5,
            &old_withdraw_cap,
            scenario.ctx(),
        );
        transfer::public_transfer(coins, @0xA);
        transfer::public_transfer(coins_gas, @0xA);

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
fun test_unwhitelist() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let cap = ts::take_from_address<AdminCap>(&scenario, @0xA);
        unwhitelist_impl<SUI>(&mut gateway, &cap);

        assert!(!is_whitelisted<SUI>(&gateway));

        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = ENotWhitelisted)]
fun test_unwhitelist_not_whitelisted() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();
        let cap = ts::take_from_address<AdminCap>(&scenario, @0xA);
        unwhitelist_impl<FAKE_USDC>(&mut gateway, &cap);

        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = ENotWhitelisted)]
fun test_withdraw_not_whitelist() {
    let mut scenario = ts::begin(@0xA);
    setup(&mut scenario);

    ts::next_tx(&mut scenario, @0xA);
    {
        let mut gateway = scenario.take_shared<Gateway>();

        // unwhitelist
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, @0xA);
        unwhitelist_impl<SUI>(&mut gateway, &admin_cap);

        // try withdraw
        let withdraw_cap = ts::take_from_address<WithdrawCap>(&scenario, @0xA);
        let nonce = gateway.nonce();
        let (coins, coins_gas) = withdraw_impl<SUI>(
            &mut gateway,
            10,
            nonce,
            5,
            &withdraw_cap,
            scenario.ctx(),
        );

        ts::return_to_address(@0xA, admin_cap);
        ts::return_to_address(@0xA, withdraw_cap);
        ts::return_shared(gateway);
        transfer::public_transfer(coins, @0xA);
        transfer::public_transfer(coins_gas, @0xA);
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
        // deposit SUI
        let mut gateway = scenario.take_shared<Gateway>();
        let coin = test_coin(&mut scenario);
        let eth_addr = ValidEthAddr.to_string().to_ascii();
        deposit(&mut gateway, coin, eth_addr, scenario.ctx());
        assert!(vault_balance<SUI>(&gateway) == AmountTest);

        ts::return_shared(gateway);
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
        deposit(&mut gateway, coin, ethAddr, scenario.ctx());
        assert!(vault_balance<FAKE_USDC>(&gateway) == AmountTest);

        ts::return_shared(gateway);
    };
    ts::next_tx(&mut scenario, @0xA);
    {
        // withdraw FAKE_USDC
        let mut gateway = scenario.take_shared<Gateway>();
        let cap = ts::take_from_address<WithdrawCap>(&scenario, @0xA);
        let nonce = gateway.nonce();
        let (coins, coins_gas) = withdraw_impl<FAKE_USDC>(
            &mut gateway,
            13,
            nonce,
            2,
            &cap,
            scenario.ctx(),
        );
        assert!(coin::value(&coins) == 13);
        assert!(coin::value(&coins_gas) == 2);

        ts::return_to_address(@0xA, cap);
        ts::return_shared(gateway);
        transfer::public_transfer(coins, @0xA);
        transfer::public_transfer(coins_gas, @0xA);
    };
    ts::next_tx(&mut scenario, @0xA);
    {
        // can unwhitelist FAKE_USDC and still withdraw SUI
        let mut gateway = scenario.take_shared<Gateway>();
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, @0xA);
        let withdraw_cap = ts::take_from_address<WithdrawCap>(&scenario, @0xA);

        unwhitelist_impl<FAKE_USDC>(&mut gateway, &admin_cap);

        let sui_coin = test_coin(&mut scenario);
        let eth_addr = ValidEthAddr.to_string().to_ascii();
        deposit(&mut gateway, sui_coin, eth_addr, scenario.ctx());

        let nonce = gateway.nonce();
        let (coins, coins_gas) = withdraw_impl<SUI>(
            &mut gateway,
            13,
            nonce,
            2,
            &withdraw_cap,
            scenario.ctx(),
        );
        assert!(coin::value(&coins) == 13);
        assert!(coin::value(&coins_gas) == 2);

        ts::return_to_address(@0xA, admin_cap);
        ts::return_to_address(@0xA, withdraw_cap);
        ts::return_shared(gateway);
        transfer::public_transfer(coins, @0xA);
        transfer::public_transfer(coins_gas, @0xA);
    };
    ts::next_tx(&mut scenario, @0xA);
    {
        // can re-whitelist and withdraw FAKE_USDC
        let mut gateway = scenario.take_shared<Gateway>();
        let whitelist_cap = ts::take_from_address<WhitelistCap>(&scenario, @0xA);
        let withdraw_cap = ts::take_from_address<WithdrawCap>(&scenario, @0xA);

        whitelist_impl<FAKE_USDC>(&mut gateway, &whitelist_cap);

        let nonce = gateway.nonce();
        let (coins, coins_gas) = withdraw_impl<FAKE_USDC>(
            &mut gateway,
            13,
            nonce,
            2,
            &withdraw_cap,
            scenario.ctx(),
        );
        assert!(coin::value(&coins) == 13);
        assert!(coin::value(&coins_gas) == 2);

        ts::return_to_address(@0xA, whitelist_cap);
        ts::return_to_address(@0xA, withdraw_cap);
        ts::return_shared(gateway);
        transfer::public_transfer(coins, @0xA);
        transfer::public_transfer(coins_gas, @0xA);
    };
    ts::end(scenario);
}
