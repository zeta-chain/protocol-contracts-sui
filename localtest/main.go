package main

import (
	"context"
	_ "embed"
	"encoding/base64"
	"fmt"
	"strconv"

	"github.com/block-vision/sui-go-sdk/constant"
	"github.com/block-vision/sui-go-sdk/models"
	"github.com/block-vision/sui-go-sdk/signer"
	"github.com/block-vision/sui-go-sdk/sui"
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
	var coinObjectId string
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
		for _, data := range resp.Data {
			fmt.Printf("%s \n", data.Data.Type)
			if data.Data.Type == "0x2::coin::Coin<0x2::sui::SUI>" {
				fmt.Printf("owned objects: %s, %v\n", data.Data.ObjectId, data.Data.Content)
				coinObjectId = data.Data.ObjectId
				break
			}
		}
	}

	fmt.Printf("Length of Gateway.mv: %d\n", len(gatewayBinary))
	gatewayBase64 := base64.StdEncoding.EncodeToString(gatewayBinary)
	fmt.Printf("gatewayBase64 len %d\n", len(gatewayBase64))
	var gatewayObjectId string
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
			// fmt.Printf("%s %s %s %s\n", change.Type, change.ObjectType, change.ObjectId)
			if change.Type == "published" {
				moduleId = change.PackageId
			}
		}
		gatewayType := fmt.Sprintf("%s::gateway::Gateway", moduleId)
		for _, change := range resp.ObjectChanges {
			if change.Type == "created" && change.ObjectType == gatewayType {
				gatewayObjectId = change.ObjectId
			}
		}
	}

	fmt.Printf("moduleId: %s\n", moduleId)
	fmt.Printf("gatewayObjectId: %s\n", gatewayObjectId)
	fmt.Printf("coinObjectId: %s\n", coinObjectId)
	if gatewayObjectId == "" || moduleId == "" {
		panic("failed to create gateway object")
	}

	{
		tx, err := cli.MoveCall(ctx, models.MoveCallRequest{
			Signer:          signerAccount.Address,
			PackageObjectId: moduleId,
			Module:          "gateway",
			Function:        "register_vault",
			TypeArguments:   []interface{}{"0x2::sui::SUI"},
			Arguments:       []interface{}{gatewayObjectId},
			GasBudget:       "5000000000",
		})
		if err != nil {
			panic(err)
		}
		resp, err := cli.SignAndExecuteTransactionBlock(ctx, models.SignAndExecuteTransactionBlockRequest{
			TxnMetaData: tx,
			PriKey:      signerAccount.PriKey,
			Options: models.SuiTransactionBlockOptions{
				ShowEffects: true,
			},
			RequestType: "WaitForLocalExecution",
		})
		if err != nil {
			panic(err)
		}
		// check status of tx
		if resp.Effects.Status.Status != "success" {
			panic("failed to register vault")
		}
		// utils.PrettyPrint(resp)
	}

	// Deposit SUI
	{
		tx, err := cli.MoveCall(ctx, models.MoveCallRequest{
			Signer:          signerAccount.Address,
			PackageObjectId: moduleId,
			Module:          "gateway",
			Function:        "deposit",
			TypeArguments:   []interface{}{"0x2::sui::SUI"},
			Arguments:       []interface{}{gatewayObjectId, coinObjectId},
			GasBudget:       "5000000000",
		})
		if err != nil {
			panic(err)
		}

		resp, err := cli.SignAndExecuteTransactionBlock(ctx, models.SignAndExecuteTransactionBlockRequest{
			TxnMetaData: tx,
			PriKey:      signerAccount.PriKey,
			Options: models.SuiTransactionBlockOptions{
				ShowEffects:        true,
				ShowBalanceChanges: true,
				ShowEvents:         true,
			},
			RequestType: "WaitForLocalExecution",
		})
		if err != nil {
			panic(err)
		}
		// utils.PrettyPrint(resp)
		if resp.Effects.Status.Status != "success" {
			panic("failed to deposit")
		}
		amtStr := resp.Events[0].ParsedJson["amount"].(string)
		fmt.Printf("Deposit amount: %s\n", amtStr)
		amount, _ := strconv.Atoi(amtStr)
		if amount == 0 {
			panic("failed to deposit")
		}
	}

	// Withdraw SUI
	{

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
