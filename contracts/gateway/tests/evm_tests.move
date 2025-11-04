#[test_only]
module gateway::evm_tests;

use gateway::evm;
use std::ascii::string;

#[test]
fun test_is_valid_evm_address() {
    // valid addresses
    assert!(evm::is_valid_evm_address(string(b"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")));
    assert!(evm::is_valid_evm_address(string(b"0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")));
    assert!(evm::is_valid_evm_address(string(b"0x0000000000000000000000000000000000000000")));
    assert!(evm::is_valid_evm_address(string(b"0x1234567890123456789012345678901234567890")));
    assert!(evm::is_valid_evm_address(string(b"0x8531a5aB847ff5B22D855633C25ED1DA3255247e")));

    // invalid addresses
    assert!(!evm::is_valid_evm_address(string(b"")));
    assert!(!evm::is_valid_evm_address(string(b"invalid")));
    assert!(!evm::is_valid_evm_address(string(b"0x8531a5aB847ff5B22D855633C25ED1DA3255247ea")));
    assert!(!evm::is_valid_evm_address(string(b"0xg531a5aB847ff5B22D855633C25ED1DA3255247e")));
    assert!(!evm::is_valid_evm_address(string(b"008531a5aB847ff5B22D855633C25ED1DA3255247e")));
}
