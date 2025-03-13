#[test_only]
module gateway::evm_tests;

use gateway::evm;

use std::ascii::string;


#[test]
fun test_is_valid_eth_address() {
    // valid addresses
    assert!(evm::is_valid_eth_address(string(b"0x1234567890123456789012345678901234567890")));
}