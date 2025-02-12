package main

import (
	"context"
	_ "embed"
	"fmt"

	"github.com/fardream/go-bcs/bcs"
	"github.com/pattonkan/sui-go/sui"
	"github.com/pattonkan/sui-go/sui/suiptb"
	"github.com/pattonkan/sui-go/suiclient"
	"github.com/pattonkan/sui-go/suisigner"
)

//go:embed testcoin.mv
var testcoinBytes []byte

//go:embed swap.mv
var swapBytes []byte

func CreatePool(
	suiClient *suiclient.ClientImpl,
	signer *suisigner.Signer,
	swapPackageId *sui.PackageId,
	testcoinId *sui.ObjectId,
	testCoin *suiclient.Coin,
	suiCoins []*suiclient.Coin,
) (*sui.ObjectId, *sui.BigInt) {
	ptb := suiptb.NewTransactionDataTransactionBuilder()

	arg0 := ptb.MustObj(suiptb.ObjectArg{ImmOrOwnedObject: testCoin.Ref()})
	arg1 := ptb.MustObj(suiptb.ObjectArg{ImmOrOwnedObject: suiCoins[0].Ref()})
	arg2 := ptb.MustPure(uint64(3))

	lspArg := ptb.Command(suiptb.Command{
		MoveCall: &suiptb.ProgrammableMoveCall{
			Package:  swapPackageId,
			Module:   "swap",
			Function: "create_pool",
			TypeArguments: []sui.TypeTag{{Struct: &sui.StructTag{
				Address: testcoinId,
				Module:  "testcoin",
				Name:    "TESTCOIN",
			}}},
			Arguments: []suiptb.Argument{arg0, arg1, arg2},
		}},
	)
	ptb.Command(suiptb.Command{
		TransferObjects: &suiptb.ProgrammableTransferObjects{
			Objects: []suiptb.Argument{lspArg},
			Address: ptb.MustPure(signer.Address),
		},
	})
	pt := ptb.Finish()
	txData := suiptb.NewTransactionData(
		signer.Address,
		pt,
		[]*sui.ObjectRef{suiCoins[1].Ref()},
		suiclient.DefaultGasBudget,
		suiclient.DefaultGasPrice,
	)

	txBytes, err := bcs.Marshal(txData)
	if err != nil {
		panic(err)
	}

	txnResponse, err := suiClient.SignAndExecuteTransaction(
		context.Background(),
		signer,
		txBytes,
		&suiclient.SuiTransactionBlockResponseOptions{
			ShowEffects:       true,
			ShowObjectChanges: true,
		},
	)
	if err != nil || !txnResponse.Effects.Data.IsSuccess() {
		panic(err)
	}
	for _, change := range txnResponse.ObjectChanges {
		if change.Data.Created != nil {
			resource, err := sui.NewResourceType(change.Data.Created.ObjectType)
			if err != nil {
				panic(err)
			}
			if resource.Contains(nil, "swap", "Pool") {
				return &change.Data.Created.ObjectId, change.Data.Created.Version
			}
		}

	}

	return nil, nil
}

func BuildAndPublish(client *suiclient.ClientImpl, signer *suisigner.Signer) *sui.PackageId {
	module := sui.Base64(swapBytes)
	dep1 := sui.MustAddressFromHex("0x1")
	dep2 := sui.MustAddressFromHex("0x2")
	txnBytes, err := client.Publish(
		context.Background(),
		&suiclient.PublishRequest{
			Sender:          signer.Address,
			CompiledModules: []*sui.Base64{&module},
			Dependencies:    []*sui.Address{dep1, dep2},
			GasBudget:       sui.NewBigInt(10 * suiclient.DefaultGasBudget),
		},
	)
	if err != nil {
		panic(err)
	}
	txnResponse, err := client.SignAndExecuteTransaction(
		context.Background(),
		signer,
		txnBytes.TxBytes,
		&suiclient.SuiTransactionBlockResponseOptions{
			ShowEffects:       true,
			ShowObjectChanges: true,
		},
	)
	if err != nil || !txnResponse.Effects.Data.IsSuccess() {
		panic(err)
	}
	packageId, err := txnResponse.GetPublishedPackageId()
	if err != nil {
		panic(err)
	}
	return packageId
}

func BuildDeployMintTestcoin(client *suiclient.ClientImpl, signer *suisigner.Signer) (
	*sui.PackageId,
	*sui.ObjectId,
) {
	module := sui.Base64(testcoinBytes)
	dep1 := sui.MustAddressFromHex("0x1")
	dep2 := sui.MustAddressFromHex("0x2")

	txnBytes, err := client.Publish(
		context.Background(),
		&suiclient.PublishRequest{
			Sender:          signer.Address,
			CompiledModules: []*sui.Base64{&module},
			Dependencies:    []*sui.Address{dep1, dep2},
			GasBudget:       sui.NewBigInt(10 * suiclient.DefaultGasBudget),
		},
	)
	if err != nil {
		panic(err)
	}
	txnResponse, err := client.SignAndExecuteTransaction(
		context.Background(), signer, txnBytes.TxBytes, &suiclient.SuiTransactionBlockResponseOptions{
			ShowEffects:       true,
			ShowObjectChanges: true,
		},
	)
	if err != nil || !txnResponse.Effects.Data.IsSuccess() {
		panic(err)
	}

	packageId, err := txnResponse.GetPublishedPackageId()
	if err != nil {
		panic(err)
	}

	treasuryCap, _, err := txnResponse.GetCreatedObjectInfo("coin", "TreasuryCap")
	if err != nil {
		panic(err)
	}

	mintAmount := uint64(1000000)
	txnResponse, err = client.MintToken(
		context.Background(),
		signer,
		packageId,
		"testcoin",
		treasuryCap,
		mintAmount,
		&suiclient.SuiTransactionBlockResponseOptions{
			ShowEffects:       true,
			ShowObjectChanges: true,
		},
	)
	if err != nil || !txnResponse.Effects.Data.IsSuccess() {
		panic(err)
	}

	return packageId, treasuryCap
}

func SwapSui(
	suiClient *suiclient.ClientImpl,
	swapper *suisigner.Signer,
	swapPackageId *sui.PackageId,
	testcoinId *sui.ObjectId,
	poolObjectId *sui.ObjectId,
	suiCoins []*suiclient.Coin,
) {
	poolGetObjectRes, err := suiClient.GetObject(context.Background(), &suiclient.GetObjectRequest{
		ObjectId: poolObjectId,
		Options: &suiclient.SuiObjectDataOptions{
			ShowType:    true,
			ShowContent: true,
		},
	})
	if err != nil {
		panic(err)
	}

	// swap sui to testcoin
	ptb := suiptb.NewTransactionDataTransactionBuilder()

	arg0 := ptb.MustObj(suiptb.ObjectArg{SharedObject: &suiptb.SharedObjectArg{
		Id:                   poolObjectId,
		InitialSharedVersion: poolGetObjectRes.Data.Ref().Version,
		Mutable:              true,
	}})
	arg1 := ptb.MustObj(suiptb.ObjectArg{ImmOrOwnedObject: suiCoins[0].Ref()})

	retCoinArg := ptb.Command(suiptb.Command{
		MoveCall: &suiptb.ProgrammableMoveCall{
			Package:  swapPackageId,
			Module:   "swap",
			Function: "swap_sui",
			TypeArguments: []sui.TypeTag{{Struct: &sui.StructTag{
				Address: testcoinId,
				Module:  "testcoin",
				Name:    "TESTCOIN",
			}}},
			Arguments: []suiptb.Argument{arg0, arg1},
		}},
	)
	ptb.Command(suiptb.Command{
		TransferObjects: &suiptb.ProgrammableTransferObjects{
			Objects: []suiptb.Argument{retCoinArg},
			Address: ptb.MustPure(swapper.Address),
		},
	})
	pt := ptb.Finish()
	txData := suiptb.NewTransactionData(
		swapper.Address,
		pt,
		[]*sui.ObjectRef{suiCoins[1].Ref()},
		suiclient.DefaultGasBudget,
		suiclient.DefaultGasPrice,
	)
	txBytes, err := bcs.Marshal(txData)
	if err != nil {
		panic(err)
	}

	resp, err := suiClient.SignAndExecuteTransaction(
		context.Background(),
		swapper,
		txBytes,
		&suiclient.SuiTransactionBlockResponseOptions{
			ShowObjectChanges: true,
			ShowEffects:       true,
		},
	)
	if err != nil || !resp.Effects.Data.IsSuccess() {
		panic(err)
	}

	for _, change := range resp.ObjectChanges {
		if change.Data.Created != nil {
			fmt.Println("change.Data.Created.ObjectId: ", change.Data.Created.ObjectId)
			fmt.Println("change.Data.Created.ObjectType: ", change.Data.Created.ObjectType)
			fmt.Println("change.Data.Created.Owner.AddressOwner: ", change.Data.Created.Owner.AddressOwner)
		}
		if change.Data.Mutated != nil {
			fmt.Println("change.Data.Mutated.ObjectId: ", change.Data.Mutated.ObjectId)
			fmt.Println("change.Data.Mutated.ObjectType: ", change.Data.Mutated.ObjectType)
			fmt.Println("change.Data.Mutated.Owner.AddressOwner: ", change.Data.Mutated.Owner.AddressOwner)
		}
	}
}
