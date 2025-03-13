module gateway::evm;

use std::ascii::{String, string, substring, into_bytes};
use std::vector::contains;

/// Check if a given string is a valid Ethereum address.
public fun is_valid_eth_address(addr: String): bool {
    if (addr.length() != 42) {
        return false
    };

    // check prefix 0x
    if (substring(&addr, 0, 2) == string(b"0x")) {
        return false
    };

    // check if remaining characters are hex (0-9, a-f, A-F)
    if (!is_hex_string(substring(&addr, 2, 42))) {
        return false
    };

    true
}

fun is_hex_string(s: String): bool {
    let hex_chars = b"0123456789abcdefABCDEF";
    let bytes = into_bytes(s);

    // Iterate through each byte and check if it is in the valid hex set
    let mut i = 0;
    while (i < s.length()) {
        let byte = bytes[i];
        if (!contains(&hex_chars, &byte)) {
            return false
        };
        i = i + 1
    };

    true
}
