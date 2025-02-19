package main

import (
	"fmt"
	"strconv"

	"github.com/block-vision/sui-go-sdk/models"
	"github.com/stretchr/testify/require"
)

func TestDeposit(ts *TestSuite) {
	// ARRANGE
	ts.RequestLocalNetSuiFromFaucet(string(ts.TSS.Address()))

	coinObjectId, err := filterOwnedObject(ts.Client, ts.TSS.Address(), "0x2::coin::Coin<0x2::sui::SUI>")
	require.NoError(ts, err)

	zetaEthAddress := "0x7c125C1d515b8945841b3d5144a060115C58725F"
	tx, err := ts.Client.MoveCall(ts.Ctx, models.MoveCallRequest{
		Signer:          ts.TSS.Address(),
		PackageObjectId: ts.PackageID,
		Module:          "gateway",
		Function:        "deposit",
		TypeArguments:   []any{"0x2::sui::SUI"},
		Arguments:       []any{ts.GatewayObjectID, coinObjectId, zetaEthAddress},
		GasBudget:       "5000000000",
	})
	require.NoError(ts, err)

	resp, err := ts.TSS.SignAndExecuteTransactionBlock(ts.Ctx, ts.Client, models.SignAndExecuteTransactionBlockRequest{
		// not used; the TSS' own private scep256k1 key is used
		PriKey:      ts.Signer.PriKey,
		TxnMetaData: tx,
		Options: models.SuiTransactionBlockOptions{
			ShowEffects:        true,
			ShowBalanceChanges: true,
			ShowEvents:         true,
		},
		RequestType: "WaitForLocalExecution",
	})
	require.NoError(ts, err)
	require.Equal(ts, "success", resp.Effects.Status.Status)

	amtStr := resp.Events[0].ParsedJson["amount"].(string)
	ts.Log("Deposit amount: %s", amtStr)

	amount, err := strconv.Atoi(amtStr)
	require.NoError(ts, err)
	require.NotEmpty(ts, amount)

	receiverAddrHex := resp.Events[0].ParsedJson["receiver"].(string)

	require.Equal(ts, zetaEthAddress, receiverAddrHex)

	ts.Log("Event match! receiver address: %s", receiverAddrHex)
}

func TestWithdrawal(ts *TestSuite) {
	// acquire the WithdrawCap object first
	typeName := fmt.Sprintf("%s::gateway::WithdrawCap", ts.PackageID)
	withdrawCapId, err := filterOwnedObject(ts.Client, ts.Signer.Address, typeName)
	require.NoError(ts, err)

	ts.Log("WithdrawCap id %s", withdrawCapId)
	require.NotEmpty(ts, withdrawCapId)

	var (
		bob   = "0x12030d7d9a343d7c31856da0bf6c5706b34035a610284ff5a47e11e990ce4c5b"
		amt   = "12345"
		nonce = "0"
	)

	tx, err := ts.Client.MoveCall(ts.Ctx, models.MoveCallRequest{
		Signer:          ts.Signer.Address,
		PackageObjectId: ts.PackageID,
		Module:          "gateway",
		Function:        "withdraw",
		TypeArguments:   []any{"0x2::sui::SUI"},
		Arguments:       []any{ts.GatewayObjectID, amt, nonce, bob, withdrawCapId},
		GasBudget:       "5000000000",
	})

	require.NoError(ts, err)

	resp, err := ts.Client.SignAndExecuteTransactionBlock(ts.Ctx, models.SignAndExecuteTransactionBlockRequest{
		TxnMetaData: tx,
		PriKey:      ts.Signer.PriKey,
		Options: models.SuiTransactionBlockOptions{
			ShowEffects:        true,
			ShowBalanceChanges: true,
			ShowEvents:         true,
		},
		RequestType: "WaitForLocalExecution",
	})

	require.NoError(ts, err)
	require.Equal(ts, "success", resp.Effects.Status.Status)

	for _, change := range resp.BalanceChanges {
		if change.Owner.AddressOwner == bob {
			ts.Log("Withdraw amount: %s", change.Amount)
			require.Equal(ts, amt, change.Amount)
		}
	}
}
