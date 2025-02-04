module gateway_sui::fake_usdc;

use sui::coin::{Self};

public struct FAKE_USDC has drop {}

fun init(witness: FAKE_USDC, ctx: &mut TxContext) {
    let (treasury_cap, coin_metadata) = coin::create_currency(witness, 8, b"fUSDC", b"FAKEUSDC", b"fake usdc for testing", option::none(), ctx);
    transfer::public_share_object(coin_metadata);
    transfer::public_share_object(treasury_cap);

}

#[test_only]
public(package) fun init_for_testing(ctx: &mut TxContext) {
    init(FAKE_USDC{}, ctx)
}
