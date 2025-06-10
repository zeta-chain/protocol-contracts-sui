
<a name="gateway_evm"></a>

# Module `gateway::evm`



-  [Function `is_valid_evm_address`](#gateway_evm_is_valid_evm_address)
-  [Function `is_hex_vec`](#gateway_evm_is_hex_vec)


<pre><code><b>use</b> <a href="../dependencies/std/ascii.md#std_ascii">std::ascii</a>;
<b>use</b> <a href="../dependencies/std/option.md#std_option">std::option</a>;
<b>use</b> <a href="../dependencies/std/vector.md#std_vector">std::vector</a>;
</code></pre>



<a name="gateway_evm_is_valid_evm_address"></a>

## Function `is_valid_evm_address`

Check if a given string is a valid Ethereum address.


<pre><code><b>public</b> <b>fun</b> <a href="../gateway/evm.md#gateway_evm_is_valid_evm_address">is_valid_evm_address</a>(addr: <a href="../dependencies/std/ascii.md#std_ascii_String">std::ascii::String</a>): bool
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="../gateway/evm.md#gateway_evm_is_valid_evm_address">is_valid_evm_address</a>(addr: String): bool {
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
    <a href="../gateway/evm.md#gateway_evm_is_hex_vec">is_hex_vec</a>(addrBytes)
}
</code></pre>



</details>

<a name="gateway_evm_is_hex_vec"></a>

## Function `is_hex_vec`

Check that vector contains only hex chars (0-9, a-f, A-F).


<pre><code><b>fun</b> <a href="../gateway/evm.md#gateway_evm_is_hex_vec">is_hex_vec</a>(input: vector&lt;u8&gt;): bool
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="../gateway/evm.md#gateway_evm_is_hex_vec">is_hex_vec</a>(input: vector&lt;u8&gt;): bool {
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
