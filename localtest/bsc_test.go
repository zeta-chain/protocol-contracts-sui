package main

import (
	"bytes"
	"encoding/hex"
	"fmt"
	"testing"

	"github.com/block-vision/sui-go-sdk/utils"
	"github.com/brewmaster012/sui-gateway/bcs"
	"github.com/pattonkan/sui-go/sui/suiptb"
)

// this test case is from main.go PTB transaction data
var txDataHex = "00000701010288a47061dbe9a24863997f387d8611b510f68748b980714101f159d11424510b000000000000000100083905000000000000000802000000000000000020b9f23a3a3f204ed98c87cad43ead245a70fcb6842d90bafae9e2f6db78a1574d01002ce7e127024212bc545c67121f13528bb4b9a54c213ec051ebac8f512db3e51210000000000000002030ca2a4875dd92c258e4e92b19e7e3e1761040013640972697bcbca2fc7ab74b01019617a2aa64c473a2e15c131b208a500b803440d746b059ff0fee2bff3f78a3191300000000000000010020f6dba1ffc93d4b2c596b29bf780fe5b62b102bb2c95de12e1979431e61f6e6e00300652e7eff9c90949abcbbbfa64ed324e170e61a76164c9c9fd3b2b73342d118ff07676174657761790d77697468647261775f696d706c01070000000000000000000000000000000000000000000000000000000000000002037375690353554900040100000101000102000104000022a2f9147a20209101f4258457a30dfcea113e83d5029900b632526dd64e56b0047377617008737761705f7375690107aa98372d77eaeb2c63b6178aa33c92c4028c4b2b563e88193da80ab697774f310874657374636f696e0854455354434f494e000201050003000000000101020100010600b9f23a3a3f204ed98c87cad43ead245a70fcb6842d90bafae9e2f6db78a1574d013864572229a15da5d0c55a7fc8e7bad0d2e69eb8634fae5c874c83358463f1001300000000000000200004dc0ee4b184fe75ff0fa6cd4926b21f1d1be4bcde9bd84f8109236edecc35b9f23a3a3f204ed98c87cad43ead245a70fcb6842d90bafae9e2f6db78a1574de803000000000000809698000000000000"

func TestDecodeTxData(t *testing.T) {
	txData, err := hex.DecodeString(txDataHex)
	assertNoError(t, err)
	assertTrueTest(t, len(txData) == 636)

	// Decode txData
	// the first bytes are ULEB128Decode encoded integer; read it first
	// then decode the rest of the bytes
	reader := bytes.NewReader(txData)
	enumInt, numBytes, err := bcs.ULEB128Decode[int](reader)
	assertNoError(t, err)
	fmt.Printf("enumInt: %d, numBytes: %d\n", enumInt, numBytes)

	tx := &suiptb.TransactionData{}
	numBytes, err = bcs.Unmarshal(txData, tx)
	assertNoError(t, err)
	assertTrueTest(t, numBytes == len(txData))
	utils.PrettyPrint(tx)

	txBytes, err := bcs.Marshal(tx)
	assertNoError(t, err)
	assertTrueTest(t, len(txBytes) == len(txData))
}

func assertNoError(t *testing.T, err error) {
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func assertTrueTest(t *testing.T, condition bool) {
	if !condition {
		t.Fatalf("expected true, got false")
	}
}
