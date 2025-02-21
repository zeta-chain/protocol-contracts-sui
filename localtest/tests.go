package main

import (
	"fmt"
	"strconv"

	"github.com/block-vision/sui-go-sdk/models"
	"github.com/stretchr/testify/require"
)

const suiCoin = "0000000000000000000000000000000000000000000000000000000000000002::sui::SUI"

func TestDeposit(ts *TestSuite) {
	// ARRANGE
	// Request some SUI from the faucet
	ts.RequestLocalNetSuiFromFaucet(string(ts.TSS.Address()))

	// Get TSS coin object id
	coinObjectId, err := filterOwnedObject(ts.Client, ts.TSS.Address(), "0x2::coin::Coin<0x2::sui::SUI>")
	require.NoError(ts, err)

	// Given deposit tx
	zetaEthAddress := "0x7c125C1d515b8945841b3d5144a060115C58725F"
	tx, err := ts.Client.MoveCall(ts.Ctx, models.MoveCallRequest{
		Signer:          ts.TSS.Address(),
		PackageObjectId: ts.PackageID,
		Module:          "gateway",
		Function:        "deposit",
		TypeArguments:   []any{suiCoin},
		Arguments:       []any{ts.GatewayObjectID, coinObjectId, zetaEthAddress},
		GasBudget:       "5000000000",
	})
	require.NoError(ts, err)

	// ACT
	// Deposit to the gateway
	resp, err := ts.TSS.SignAndExecuteTransactionBlock(ts.Ctx, ts.Client, models.SignAndExecuteTransactionBlockRequest{
		// not used; the TSS' own private ecdsa key is used
		PriKey:      nil,
		TxnMetaData: tx,
		Options: models.SuiTransactionBlockOptions{
			ShowEffects:        true,
			ShowBalanceChanges: true,
			ShowEvents:         true,
		},
		RequestType: "WaitForLocalExecution",
	})

	// ASSERT
	require.NoError(ts, err)
	require.Equal(ts, "success", resp.Effects.Status.Status)

	// Check amount
	amtStr := resp.Events[0].ParsedJson["amount"].(string)
	ts.Log("Deposit amount: %s", amtStr)

	amount, err := strconv.Atoi(amtStr)
	require.NoError(ts, err)
	require.NotEmpty(ts, amount)

	// Check receiver
	receiverAddrHex := resp.Events[0].ParsedJson["receiver"].(string)
	require.Equal(ts, zetaEthAddress, receiverAddrHex)
}

func TestWithdrawal(ts *TestSuite) {
	// ARRANGE
	// Given "withdraw capability" tx
	withdrawCapType := fmt.Sprintf("%s::gateway::WithdrawCap", ts.PackageID)
	withdrawCapID, err := filterOwnedObject(ts.Client, ts.Signer.Address, withdrawCapType)
	require.NoError(ts, err)

	ts.Log("WithdrawCap object id %s", withdrawCapID)
	require.NotEmpty(ts, withdrawCapID)

	// Note that the Gateway was deployed by SUI wallet (ts.Signer);
	// We want to transfer its ownership to TSS to mimic the real behavior.
	ts.Log("Transfer ownership of WithdrawCap to TSS")

	// Given withdrawCap ownership transfer tx from Signer to TSS
	transferTx, err := ts.Client.MoveCall(ts.Ctx, models.MoveCallRequest{
		Signer:          ts.Signer.Address,
		PackageObjectId: "0x2",
		Module:          "transfer",
		Function:        "public_transfer",
		TypeArguments:   []any{withdrawCapType},
		Arguments:       []any{withdrawCapID, ts.TSS.Address()},
		GasBudget:       "5000000000",
	})
	require.NoError(ts, err)

	// Execute the transfer of withdrawCap ownership
	resp, err := ts.Client.SignAndExecuteTransactionBlock(ts.Ctx, models.SignAndExecuteTransactionBlockRequest{
		PriKey:      ts.Signer.PriKey,
		TxnMetaData: transferTx,
		Options:     models.SuiTransactionBlockOptions{ShowEffects: true},
		RequestType: "WaitForLocalExecution",
	})

	require.NoError(ts, err)
	require.Equal(ts, "success", resp.Effects.Status.Status, "failed %+v", resp.Effects.Status)

	// Given withdraw tx
	var (
		bob   = "0x12030d7d9a343d7c31856da0bf6c5706b34035a610284ff5a47e11e990ce4c5b"
		amt   = "12345"
		nonce = "0"
	)

	tx, err := ts.Client.MoveCall(ts.Ctx, models.MoveCallRequest{
		Signer:          ts.TSS.Address(),
		PackageObjectId: ts.PackageID,
		Module:          "gateway",
		Function:        "withdraw",
		TypeArguments:   []any{suiCoin},
		Arguments:       []any{ts.GatewayObjectID, amt, nonce, bob, withdrawCapID},
		GasBudget:       "5000000000",
	})

	require.NoError(ts, err)

	// ACT
	// Withdraw on behalf of TSS
	resp, err = ts.TSS.SignAndExecuteTransactionBlock(ts.Ctx, ts.Client, models.SignAndExecuteTransactionBlockRequest{
		TxnMetaData: tx,
		Options: models.SuiTransactionBlockOptions{
			ShowEffects:        true,
			ShowBalanceChanges: true,
			ShowEvents:         true,
		},
		RequestType: "WaitForLocalExecution",
	})

	// ASSERT
	require.NoError(ts, err)
	require.Equal(ts, "success", resp.Effects.Status.Status)

	// Check amount
	for _, change := range resp.BalanceChanges {
		if change.Owner.AddressOwner == bob {
			ts.Log("Withdraw amount: %s", change.Amount)
			require.Equal(ts, amt, change.Amount)
		}
	}

	require.Equal(ts, 1, len(resp.Events))
	withdrawEvent := resp.Events[0]

	// Check event
	require.Equal(ts, fmt.Sprintf("%s::gateway::WithdrawEvent", ts.PackageID), withdrawEvent.Type)
	require.Equal(ts, suiCoin, withdrawEvent.ParsedJson["coin_type"])
	require.Equal(ts, amt, withdrawEvent.ParsedJson["amount"])
	require.Equal(ts, nonce, withdrawEvent.ParsedJson["nonce"])
	require.Equal(ts, bob, withdrawEvent.ParsedJson["receiver"])
	require.Equal(ts, ts.TSS.Address(), withdrawEvent.ParsedJson["sender"])
}
