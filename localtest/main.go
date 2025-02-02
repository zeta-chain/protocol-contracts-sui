package main

import (
	"context"
	_ "embed"
	"encoding/base64"
	"fmt"

	"github.com/block-vision/sui-go-sdk/constant"
	"github.com/block-vision/sui-go-sdk/models"
	"github.com/block-vision/sui-go-sdk/signer"
	"github.com/block-vision/sui-go-sdk/sui"
	"github.com/block-vision/sui-go-sdk/utils"
)

//go:embed gateway.mv
var gatewayBinary []byte

func main() {
	var moduleId string
	cli := sui.NewSuiClient("http://localhost:9000")
	ctx := context.Background()
	signerAccount, err := signer.NewSignertWithMnemonic("used permit actor clarify cook glue size hard coyote wild circle youth")
	if err != nil {
		panic(err)
	}
	fmt.Printf("address: %s\n", signerAccount.Address)

	printBalance(ctx, cli, signerAccount)
	printBalance(ctx, cli, signerAccount)
	{
		suiObjectResponseQuery := models.SuiObjectResponseQuery{
			// only fetch the effects field
			Options: models.SuiObjectDataOptions{
				ShowType:    true,
				ShowContent: true,
				ShowBcs:     true,
				ShowOwner:   true,
			},
		}
		resp, err := cli.SuiXGetOwnedObjects(ctx, models.SuiXGetOwnedObjectsRequest{
			Address: signerAccount.Address,
			Query:   suiObjectResponseQuery,
			Limit:   5,
		})
		if err != nil {
			panic(err)
		}
		data0 := resp.Data[0].Data
		fmt.Printf("owned objects: %s, %v\n", data0.ObjectId, data0.Content)
	}

	fmt.Printf("Length of Gateway.mv: %d\n", len(gatewayBinary))
	gatewayBase64 := base64.StdEncoding.EncodeToString(gatewayBinary)
	fmt.Printf("gatewayBase64 len %d\n", len(gatewayBase64))
	{
		tx, err := cli.Publish(ctx, models.PublishRequest{
			Sender:          signerAccount.Address,
			CompiledModules: []string{gatewayBase64},
			Dependencies: []string{
				"0x0000000000000000000000000000000000000000000000000000000000000001",
				"0x0000000000000000000000000000000000000000000000000000000000000002",
			},
			GasBudget: "5000000000",
			// Gas:             &gasId,
		})
		if err != nil {
			panic(err)
		}
		resp, err := cli.SignAndExecuteTransactionBlock(ctx, models.SignAndExecuteTransactionBlockRequest{
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
		if err != nil {
			panic(err)
		}
		for _, change := range resp.ObjectChanges {
			if change.Type == "published" {
				moduleId = change.PackageId
			}
		}
	}
	fmt.Printf("moduleId: %s\n", moduleId)

	{
		resp, err := cli.SuiGetMoveFunctionArgTypes(ctx, models.GetMoveFunctionArgTypesRequest{
			Package:  moduleId,
			Module:   "gateway",
			Function: "deposit",
		})
		if err != nil {
			panic(err)
		}
		utils.PrettyPrint(resp)

	}
}

func printBalance(ctx context.Context, cli sui.ISuiAPI, signerAccount *signer.Signer) {
	resp, err := cli.SuiXGetBalance(ctx, models.SuiXGetBalanceRequest{
		Owner:    signerAccount.Address,
		CoinType: "0x2::sui::SUI", // this cannot be ommited, not as the doc says
	})
	if err != nil {
		panic(err)
	}
	fmt.Printf("%s balance: %s\n", resp.CoinType, resp.TotalBalance)
	if resp.TotalBalance == "0" {
		RequestLocalNetSuiFromFaucet(signerAccount.Address)
	}
}

func RequestLocalNetSuiFromFaucet(recipient string) {
	faucetHost, err := sui.GetFaucetHost(constant.SuiLocalnet)
	if err != nil {
		fmt.Println("GetFaucetHost err:", err)
		return
	}

	header := map[string]string{}
	err = sui.RequestSuiFromFaucet(faucetHost, recipient, header)
	if err != nil {
		fmt.Println(err.Error())
		return
	}

	// the successful transaction block url: https://suiexplorer.com/txblock/91moaxbXsQnJYScLP2LpbMXV43ZfngS2xnRgj1CT7jLQ?network=devnet
	fmt.Println("Request DevNet Sui From Faucet success")
}
