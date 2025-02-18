package main

import (
	"context"
	_ "embed"
	"encoding/base64"
	"fmt"
	"os"

	"github.com/block-vision/sui-go-sdk/constant"
	"github.com/block-vision/sui-go-sdk/models"
	"github.com/block-vision/sui-go-sdk/signer"
	"github.com/block-vision/sui-go-sdk/sui"
	"github.com/stretchr/testify/require"
	tss "github.com/zeta-chain/protocol-contracts-sui/localtest/signer"
)

const (
	endpointLocalnet = "http://localhost:9000"
	tssSeed          = "used permit actor clarify cook glue size hard coyote wild circle youth"
)

//go:embed gateway.mv
var gatewayBinary []byte

type TestSuite struct {
	PackageID       string
	GatewayObjectID string
	Ctx             context.Context
	Client          sui.ISuiAPI
	Signer          *signer.Signer
	TSS             *tss.SignerSecp256k1
}

func main() {
	ts := newTestSuite(endpointLocalnet)

	ts.Log("packageID: %s", ts.PackageID)
	ts.Log("gatewayObjectID: %s", ts.GatewayObjectID)
	ts.Log("Signer Address: %s", ts.Signer.Address)
	ts.Log("TSS Address: %s", ts.TSS.Address())

	ts.Log("Running Deposit")
	TestDeposit(ts)

	ts.Log("Running Withdrawal")
	TestWithdrawal(ts)

	ts.Cleanup(true)
}

func (ts *TestSuite) Log(format string, args ...any) {
	fmt.Printf(format+"\n", args...)
}

func (ts *TestSuite) Errorf(format string, args ...any) {
	ts.Log(format, args...)
	ts.Cleanup(false)
}

func (ts *TestSuite) FailNow() { ts.Cleanup(false) }

func (ts *TestSuite) Cleanup(success bool) {
	fmt.Println("Cleaning up...")

	// todo cleanup local net

	var code int
	if !success {
		code = 1
	} else {
		ts.Log("All tests passed")
	}

	os.Exit(code)
}

func (ts *TestSuite) RequestLocalNetSuiFromFaucet(recipient string) {
	err := requestLocalNetSuiFromFaucet(recipient)
	require.NoError(ts, err)

	fmt.Println("Requested DevNet Sui From Faucet success")
}

func newTestSuite(endpoint string) *TestSuite {
	ctx := context.Background()
	client := sui.NewSuiClient(endpoint)

	// Sui wallet
	signerAccount, err := signer.NewSignertWithMnemonic(tssSeed)
	guard(err)

	// Acquire some gas
	guard(requestLocalNetSuiFromFaucet(signerAccount.Address))

	gatewayBase64 := base64.StdEncoding.EncodeToString(gatewayBinary)

	fmt.Printf("Length of Gateway.mv: %d\n", len(gatewayBinary))
	fmt.Printf("Length of base64(Gateway.mv): %d\n", len(gatewayBase64))

	// Prepare Gateway deployment tx
	tx, err := client.Publish(ctx, models.PublishRequest{
		Sender:          signerAccount.Address,
		CompiledModules: []string{gatewayBase64},
		Dependencies: []string{
			"0x0000000000000000000000000000000000000000000000000000000000000001",
			"0x0000000000000000000000000000000000000000000000000000000000000002",
		},
		GasBudget: "5000000000",
	})
	guard(err)

	// Publish the package
	resp, err := client.SignAndExecuteTransactionBlock(ctx, models.SignAndExecuteTransactionBlockRequest{
		TxnMetaData: tx,
		PriKey:      signerAccount.PriKey,
		Options: models.SuiTransactionBlockOptions{
			ShowInput:         true,
			ShowRawInput:      true,
			ShowEffects:       true,
			ShowObjectChanges: true,
		},
		RequestType: "WaitForLocalExecution",
	})
	guard(err)

	// Retrieve package id
	var packageID string
	for _, change := range resp.ObjectChanges {
		if change.Type == "published" {
			packageID = change.PackageId
		}
	}

	// Retrieve object id of the Gateway struct
	gatewayObjectID := ""
	gatewayType := fmt.Sprintf("%s::gateway::Gateway", packageID)
	for _, change := range resp.ObjectChanges {
		if change.Type == "created" && change.ObjectType == gatewayType {
			gatewayObjectID = change.ObjectId
		}
	}

	if gatewayObjectID == "" || packageID == "" {
		panic("failed to create gateway object")
	}

	// Create "fake" TSS signer that is ECDSA key for localtest
	tssSigner := tss.NewSignerSecp256k1Random()

	return &TestSuite{
		Ctx:             ctx,
		Client:          client,
		PackageID:       packageID,
		GatewayObjectID: gatewayObjectID,
		Signer:          signerAccount,
		TSS:             tssSigner,
	}
}

// find one object owned by the address and has the type of typeName
func filterOwnedObject(cli sui.ISuiAPI, address, typeName string) (objId string, err error) {
	// see https://docs.sui.io/sui-api-ref#suix_getownedobjects
	suiObjectResponseQuery := models.SuiObjectResponseQuery{
		Filter: models.SuiObjectDataFilter{
			"StructType": typeName,
		},
		Options: models.SuiObjectDataOptions{
			ShowType:    true,
			ShowContent: true,
			ShowBcs:     true,
			ShowOwner:   true,
		},
	}

	resp, err := cli.SuiXGetOwnedObjects(context.Background(), models.SuiXGetOwnedObjectsRequest{
		Address: address,
		Query:   suiObjectResponseQuery,
		Limit:   50,
	})
	if err != nil {
		return "", err
	}

	fmt.Printf("filtering out (of %d) owned object matching typeName=%s", len(resp.Data), typeName)

	for _, data := range resp.Data {
		if data.Data.Type == typeName {
			fmt.Printf("owned objects: %s, %v\n", data.Data.ObjectId, data.Data.Content)
			objId = data.Data.ObjectId
			return objId, nil
		}
	}

	return "", fmt.Errorf("no object of type %s found", typeName)
}

func guard(err error) {
	if err != nil {
		panic(err.Error())
	}
}

func requestLocalNetSuiFromFaucet(recipient string) error {
	faucetHost, err := sui.GetFaucetHost(constant.SuiLocalnet)
	if err != nil {
		return err
	}

	header := map[string]string{}
	return sui.RequestSuiFromFaucet(faucetHost, recipient, header)
}
