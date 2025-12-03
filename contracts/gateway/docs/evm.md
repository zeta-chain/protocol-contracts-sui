


# Module `gateway::evm`



-  [Function `is_valid_evm_address`](#gateway_evm_is_valid_evm_address)
-  [Function `is_hex_vec`](#gateway_evm_is_hex_vec)


<pre><code><b>use</b> std::ascii;
<b>use</b> std::option;
<b>use</b> std::vector;
</code></pre>





## Function `is_valid_evm_address`

Check if a given string is a valid Ethereum address.


<pre><code><b>public</b> <b>fun</b> is_valid_evm_address(addr: std::ascii::String): bool
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> is_valid_evm_address(addr: String): bool {
    <b>if</b> (addr.length() != 42) {
        <b>return</b> <b>false</b>
    };
    <b>let</b> <b>mut</b> addrBytes = addr.into_bytes();
    // check prefix 0x, 0=48, x=120
    <b>if</b> (addrBytes[0] != 48 || addrBytes[1] != 120) {
        <b>return</b> <b>false</b>
    };
    // remove 0x prefix
    addrBytes.remove(0);
    addrBytes.remove(0);
    // check <b>if</b> remaining characters are hex (0-9, a-f, A-F)
    is_hex_vec(addrBytes)
}
</code></pre>



</details>



## Function `is_hex_vec`

Check that vector contains only hex chars (0-9, a-f, A-F).


<pre><code><b>fun</b> is_hex_vec(input: vector&lt;u8&gt;): bool
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> is_hex_vec(input: vector&lt;u8&gt;): bool {
    <b>let</b> <b>mut</b> i = 0;
    <b>let</b> len = input.length();
    <b>while</b> (i &lt; len) {
        <b>let</b> c = input[i];
        <b>let</b> is_hex = (c &gt;= 48 && c &lt;= 57) ||  // '0' to '9'
                     (c &gt;= 97 && c &lt;= 102) || // 'a' to 'f'
                     (c &gt;= 65 && c &lt;= 70);    // 'A' to 'F'
        <b>if</b> (!is_hex) {
            <b>return</b> <b>false</b>
        };
        i = i + 1;
    };
    <b>true</b>
}
</code></pre>



</details>
