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
	"github.com/block-vision/sui-go-sdk/utils"
	signer2 "github.com/brewmaster012/sui-gateway/signer"
	"github.com/fardream/go-bcs/bcs"
	sui2 "github.com/pattonkan/sui-go/sui"
	"github.com/pattonkan/sui-go/sui/suiptb"
	"github.com/pattonkan/sui-go/suiclient"
	"github.com/pattonkan/sui-go/suisigner"
)

//go:embed gateway.mv
var gatewayBinary []byte

// find one object owned by the address and has the type of typeName
func filterOwnedObject(cli sui.ISuiAPI, address string, typeName string) (objId string, err error) {
	suiObjectResponseQuery := models.SuiObjectResponseQuery{
		// for the filter see JSON-RPC doc: https://docs.sui.io/sui-api-ref#suix_getownedobjects
		Filter: models.SuiObjectDataFilter{
			"StructType": typeName,
		},
		// only fetch the effects field
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
	fmt.Printf("filterning out (of %d) owned object matching typeName=%s", len(resp.Data), typeName)
	for _, data := range resp.Data {
		if data.Data.Type == typeName {
			fmt.Printf("owned objects: %s, %v\n", data.Data.ObjectId, data.Data.Content)
			objId = data.Data.ObjectId
			return objId, nil
		}
	}
	return "", fmt.Errorf("no object of type %s found", typeName)
}

func main() {
	var moduleId string
	cli := sui.NewSuiClient("http://localhost:9000")
	ctx := context.Background()
	signerAccount, err := signer.NewSignertWithMnemonic("used permit actor clarify cook glue size hard coyote wild circle youth")
	if err != nil {
		panic(err)
	}
	fmt.Printf("address: %s\n", signerAccount.Address)
	cli.SuiExecuteTransactionBlock(ctx, models.SuiExecuteTransactionBlockRequest{})

	printBalance(ctx, cli, signerAccount)
	printBalance(ctx, cli, signerAccount)

	coinObjectId, err := filterOwnedObject(cli, signerAccount.Address, "0x2::coin::Coin<0x2::sui::SUI>")

	fmt.Printf("Length of Gateway.mv: %d\n", len(gatewayBinary))
	gatewayBase64 := base64.StdEncoding.EncodeToString(gatewayBinary)
	fmt.Printf("gatewayBase64 len %d\n", len(gatewayBase64))
	var gatewayObjectId string
	var gatewayObjectInitialSharedVersion string
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
				//utils.PrettyPrint(change)
				gatewayObjectInitialSharedVersion = change.Version
				fmt.Printf("gateway obj initial shared version %d\n", gatewayObjectInitialSharedVersion)

			}
		}
	}

	fmt.Printf("moduleId: %s\n", moduleId)
	fmt.Printf("gatewayObjectId: %s\n", gatewayObjectId)
	fmt.Printf("coinObjectId: %s\n", coinObjectId)
	if gatewayObjectId == "" || moduleId == "" {
		panic("failed to create gateway object")
	}

	{ // register vault2 from signer2;
		// first need to transfer the adminCap from signer1 to signer2
		// 	typeName := fmt.Sprintf("%s::gateway::WithdrawCap", moduleId)
		typeName := fmt.Sprintf("%s::gateway::AdminCap", moduleId)
		adminCapId, err := filterOwnedObject(cli, signerAccount.Address, typeName)
		if err != nil {
			panic(err)
		}
		fmt.Printf("adminCapId id %s\n", adminCapId)
		if adminCapId == "" {
			panic("failed to find WithdrawCap object")
		}

		s2 := signer2.NewSignerSecp256k1Random()
		fmt.Printf("signer2 address: %s\n", s2.Address())
		RequestLocalNetSuiFromFaucet(string(s2.Address()))

		{
			tx, err := cli.TransferObject(ctx, models.TransferObjectRequest{
				Signer:    signerAccount.Address,
				ObjectId:  adminCapId,
				Recipient: string(s2.Address()),
				GasBudget: "5000000000",
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

			if resp.Effects.Status.Status != "success" {
				panic("failed to transfer AdminCap")
			}
			fmt.Printf("AdminCap transferred to signer2\n")
		}

		tx, err := cli.MoveCall(ctx, models.MoveCallRequest{
			Signer:          string(s2.Address()),
			PackageObjectId: moduleId,
			Module:          "gateway",
			Function:        "register_vault",
			TypeArguments:   []interface{}{"0x2::sui::SUI"},
			Arguments:       []interface{}{gatewayObjectId, adminCapId},
			GasBudget:       "5000000000",
		})
		if err != nil {
			panic(err)
		}
		resp, err := s2.SignAndExecuteTransactionBlock(ctx, cli, models.SignAndExecuteTransactionBlockRequest{
			TxnMetaData: tx,
			PriKey:      signerAccount.PriKey, // this one is not used as it's ed25119, just for compat
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
		fmt.Printf("SUI vault registered\n")
		// utils.PrettyPrint(resp)
	}

	// Deposit SUI
	{
		zetaEthAddress := "0x7c125C1d515b8945841b3d5144a060115C58725F"
		tx, err := cli.MoveCall(ctx, models.MoveCallRequest{
			Signer:          signerAccount.Address,
			PackageObjectId: moduleId,
			Module:          "gateway",
			Function:        "deposit",
			TypeArguments:   []interface{}{"0x2::sui::SUI"},
			Arguments:       []interface{}{gatewayObjectId, coinObjectId, zetaEthAddress},
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
		if resp.Effects.Status.Status != "success" {
			utils.PrettyPrint(resp)
			panic("failed to deposit")
		}
		amtStr := resp.Events[0].ParsedJson["amount"].(string)
		fmt.Printf("Deposit amount: %s\n", amtStr)
		amount, _ := strconv.Atoi(amtStr)
		if amount == 0 {
			panic("failed to deposit")
		}

		receiverAddrHex := resp.Events[0].ParsedJson["receiver"].(string)
		if receiverAddrHex != zetaEthAddress {
			panic("receiver address mismatch")
		} else {
			fmt.Printf("event match! receiver address: %s\n", receiverAddrHex)
		}
	}

	// Withdraw SUI
	{
		// acquire the WithdrawCap object first
		typeName := fmt.Sprintf("%s::gateway::WithdrawCap", moduleId)
		withdrawCapId, err := filterOwnedObject(cli, signerAccount.Address, typeName)
		if err != nil {
			panic(err)
		}
		fmt.Printf("withdrawcap id %s\n", withdrawCapId)
		if withdrawCapId == "" {
			panic("failed to find WithdrawCap object")
		}
		bob := "0x12030d7d9a343d7c31856da0bf6c5706b34035a610284ff5a47e11e990ce4c5b"
		amt := "12345"
		nonce := "0"
		tx, err := cli.MoveCall(ctx, models.MoveCallRequest{
			Signer:          signerAccount.Address,
			PackageObjectId: moduleId,
			Module:          "gateway",
			Function:        "withdraw",
			TypeArguments:   []interface{}{"0x2::sui::SUI"},
			Arguments:       []interface{}{gatewayObjectId, amt, nonce, bob, withdrawCapId},
			GasBudget:       "5000000000",
		})
		if err != nil {
			panic(err)
		}

		//utils.PrettyPrint("withdraw tx")
		//utils.PrettyPrint(tx)
		//spew.Dump(tx)

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
		if resp.Effects.Status.Status != "success" {
			utils.PrettyPrint(resp)
			panic("failed to withdraw")
		}
		for _, change := range resp.BalanceChanges {
			if change.Owner.AddressOwner == bob {
				fmt.Printf("Withdraw amount: %s\n", change.Amount)
				if change.Amount != amt {
					panic("withdraw amount mismatch")
				}
			}
		}
	}

	{ // PTB withdraw + transfer
		// acquire the WithdrawCap object first
		typeName := fmt.Sprintf("%s::gateway::WithdrawCap", moduleId)
		withdrawCapId, err := filterOwnedObject(cli, signerAccount.Address, typeName)
		if err != nil {
			panic(err)
		}
		fmt.Printf("withdrawcap id %s\n", withdrawCapId)
		if withdrawCapId == "" {
			panic("failed to find WithdrawCap object")
		}
		withdrawCap := sui2.MustObjectIdFromHex(withdrawCapId)

		//PTB withdraw + transfer
		client := suiclient.NewClient("http://localhost:9000")
		ptb := suiptb.NewTransactionDataTransactionBuilder()
		packId := sui2.MustPackageIdFromHex(moduleId)
		//tag, _ := sui2.StructTagFromString()
		tag := sui2.MustNewTypeTag("0x2::sui::SUI")
		//withdrawCapObjId := sui2.MustObjectIdFromHex(adminCap)
		client.GetObject(context.Background(), &suiclient.GetObjectRequest{
			ObjectId: withdrawCap,
		})
		// turn the address of signer in hex string 0x... to sui2.Address
		sender := sui2.MustAddressFromHex(signerAccount.Address)
		coinPages, err := client.GetCoins(context.Background(), &suiclient.GetCoinsRequest{
			Owner: sender,
			Limit: 3,
		})
		assertNoErr(err)
		coins := suiclient.Coins(coinPages.Data)

		var arg0 suiptb.Argument
		{
			gatewayObjId := sui2.MustObjectIdFromHex(gatewayObjectId)
			objResp, err := client.GetObject(context.Background(), &suiclient.GetObjectRequest{
				ObjectId: gatewayObjId,
				Options:  &suiclient.SuiObjectDataOptions{},
			})
			assertNoErr(err)
			fmt.Printf("gateway object\n")
			utils.PrettyPrint(objResp)
			initVer, err := strconv.ParseInt(gatewayObjectInitialSharedVersion, 10, 64)
			assertNoErr(err)
			arg0 = ptb.MustObj(suiptb.ObjectArg{SharedObject: &suiptb.SharedObjectArg{
				Id: objResp.Data.ObjectId,
				//InitialSharedVersion: objResp.Data.Version.Uint64(),
				InitialSharedVersion: uint64(initVer), // must use initial version, not the current version
				Mutable:              true,
			}})
		}
		arg1 := ptb.MustPure(uint64(1337))
		arg2 := ptb.MustPure(uint64(1))
		arg3 := ptb.MustPure(sender)
		var arg4 suiptb.Argument
		{
			// get withdraw cap obj like the above gateway obj
			withdrawCapObjId := sui2.MustObjectIdFromHex(withdrawCapId)
			objResp, err := client.GetObject(context.Background(), &suiclient.GetObjectRequest{
				ObjectId: withdrawCapObjId,
				Options:  &suiclient.SuiObjectDataOptions{},
			})
			assertNoErr(err)
			fmt.Printf("withdrawCapObjId object\n")
			utils.PrettyPrint(objResp)
			arg4 = ptb.MustObj(suiptb.ObjectArg{ImmOrOwnedObject: &sui2.ObjectRef{
				ObjectId: objResp.Data.ObjectId,
				Version:  objResp.Data.Version.Uint64(),
				Digest:   objResp.Data.Digest,
			}})
		}
		//	public fun withdraw_impl<T>(
		//	gateway: &mut Gateway,
		//	amount: u64,
		//	nonce: u64,
		//	_cap: &WithdrawCap,
		//	ctx: &mut TxContext,
		//): Coin<T> {
		ptb.Command(suiptb.Command{
			MoveCall: &suiptb.ProgrammableMoveCall{
				Package:       packId,
				Module:        "gateway",
				Function:      "withdraw_impl",
				TypeArguments: []sui2.TypeTag{*tag},
				Arguments:     []suiptb.Argument{arg0, arg1, arg2, arg4},
			},
		})
		_ = arg3
		ptb.Command(suiptb.Command{
			TransferObjects: &suiptb.ProgrammableTransferObjects{
				Objects: []suiptb.Argument{{NestedResult: &suiptb.NestedResult{Cmd: 0, Result: 0}}},
				Address: arg3,
			},
		})
		pt := ptb.Finish()

		txData := suiptb.NewTransactionData(sender, pt, []*sui2.ObjectRef{coins[0].Ref()},
			suiclient.DefaultGasBudget, suiclient.DefaultGasPrice)
		txBytes, err := bcs.Marshal(txData)
		assertNoErr(err)
		fmt.Printf("coins[0]\n")
		utils.PrettyPrint(coins[0].Ref())
		//simulate, err := client.DryRunTransaction(context.Background(), txBytes)
		//assertNoErr(err)
		//utils.PrettyPrint(simulate)
		keypair := suisigner.NewKeypairEd25519(signerAccount.PriKey, signerAccount.PubKey)

		signer := suisigner.Signer{
			Ed25519Keypair: keypair,
			Address:        sender,
		}
		resp, err := client.SignAndExecuteTransaction(context.Background(), &signer, txBytes, &suiclient.SuiTransactionBlockResponseOptions{
			ShowEffects: true,
		})
		assertNoErr(err)
		assertTrue(resp.Effects.Data.IsSuccess(), "PTB withdraw failed")
		//utils.PrettyPrint(resp)
	}

	fmt.Printf("THE END!\n")
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

func assertNoErr(err error) {
	if err != nil {
		panic(err)
	}
}

func assertTrue(cond bool, msg string) {
	if !cond {
		panic(msg)
	}
}
