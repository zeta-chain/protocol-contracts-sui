package signer

import (
	"context"
	"crypto/ecdsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"log"
	"math/big"

	"github.com/block-vision/sui-go-sdk/models"
	"github.com/block-vision/sui-go-sdk/sui"
	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	crypto2 "github.com/ethereum/go-ethereum/crypto"
	"golang.org/x/crypto/blake2b"
)

const (
	// Flag bytes for different signature schemes
	FLAG_ED25519   = 0x00
	FLAG_SECP256K1 = 0x01
	FLAG_SECP256R1 = 0x02
	FLAG_MULTISIG  = 0x03

	// Length of Sui address in bytes
	SUI_ADDRESS_LENGTH = 32
)

type SignerSecp256k1 struct {
	privkey *ecdsa.PrivateKey
}

func NewSignerSecp256k1FromSecretKey(secret []byte) *SignerSecp256k1 {
	priv := new(ecdsa.PrivateKey)
	priv.D = new(big.Int).SetBytes(secret)
	priv.PublicKey.Curve = secp256k1.S256() // Use secp256k1 curve
	// Calculate public key point
	priv.PublicKey.X, priv.PublicKey.Y = priv.PublicKey.Curve.ScalarBaseMult(secret)
	return &SignerSecp256k1{privkey: priv}
}

func NewSignerSecp256k1Random() *SignerSecp256k1 {
	// Generate a new private key
	privKey, err := secp256k1.GeneratePrivateKey()
	if err != nil {
		panic(err) // In practice, you might want to handle this error differently
	}

	// Convert to ECDSA private key
	ecdsaPrivKey := &ecdsa.PrivateKey{
		PublicKey: ecdsa.PublicKey{
			Curve: secp256k1.S256(),
			X:     privKey.PubKey().X(),
			Y:     privKey.PubKey().Y(),
		},
		D: privKey.ToECDSA().D,
	}

	return &SignerSecp256k1{
		privkey: ecdsaPrivKey,
	}
}

// GetPublicKey returns the compressed public key bytes
func (s *SignerSecp256k1) GetPublicKey() []byte {
	pub := s.privkey.Public().(*ecdsa.PublicKey)

	// Create compressed public key format:
	// 0x02/0x03 | x-coordinate (32 bytes)
	x := pub.X.Bytes()

	// Ensure x coordinate is 32 bytes with leading zeros if needed
	paddedX := make([]byte, 32)
	copy(paddedX[32-len(x):], x)

	// Prefix with 0x02 for even Y or 0x03 for odd Y
	prefix := byte(0x02)
	if pub.Y.Bit(0) == 1 {
		prefix = 0x03
	}

	return append([]byte{prefix}, paddedX...)
}

func (s *SignerSecp256k1) Address() string {
	// Get the public key bytes
	pubKeyBytes := s.GetPublicKey()

	// Prepare the input for hashing: flag byte + public key bytes
	input := make([]byte, len(pubKeyBytes)+1)
	input[0] = FLAG_SECP256K1
	copy(input[1:], pubKeyBytes)

	// Create BLAKE2b hash
	hash, err := blake2b.New256(nil)
	if err != nil {
		panic(err) // This should never happen with nil key
	}

	// Write input to hash
	hash.Write(input)

	// Get the final hash
	addrBytes := hash.Sum(nil)
	// convert to 0x hex
	return "0x" + hex.EncodeToString(addrBytes)
}

type SignedMessageSerializedSig struct {
	Message   string `json:"message"`
	Signature string `json:"signature"`
}

// // https://docs.sui.io/concepts/cryptography/transaction-auth/signatures
// func (s *SignerSecp256k1) SignMessage(data string, scope constant.IntentScope) (*SignedMessageSerializedSig, error) {
// 	txBytes, _ := base64.StdEncoding.DecodeString(data)
// 	message := models.NewMessageWithIntent(txBytes, scope)
// 	digest := blake2b.Sum256(message)
// 	var noHash crypto.Hash
// 	sigBytes, err := s.privkey.Sign(rand.Reader, digest[:], noHash)
// 	if err != nil {
// 		return nil, err
// 	}

// 	ret := &SignedMessageSerializedSig{
// 		Message:   data,
// 		Signature: ToSerializedSignature(sigBytes, s.GetPublicKey()),
// 	}
// 	return ret, nil
// }

// func (s *SignerSecp256k1) SignTransaction(b64TxBytes string) (*models.SignedTransactionSerializedSig, error) {
// 	result, err := s.SignMessage(b64TxBytes, constant.PersonalMessageIntentScope)
// 	if err != nil {
// 		return nil, err
// 	}

// 	return &models.SignedTransactionSerializedSig{
// 		TxBytes:   result.Message,
// 		Signature: result.Signature,
// 	}, nil
// }

// func (s *SignerSecp256k1) SignPersonalMessage(message string) (*SignedMessageSerializedSig, error) {
// 	b64Message := base64.StdEncoding.EncodeToString([]byte(message))
// 	return s.SignMessage(b64Message, constant.PersonalMessageIntentScope)
// }

func ToSerializedSignature(signature, pubKey []byte) string {
	signatureLen := len(signature)
	pubKeyLen := len(pubKey)
	serializedSignature := make([]byte, 1+signatureLen+pubKeyLen)
	serializedSignature[0] = byte(FLAG_SECP256K1)
	copy(serializedSignature[1:], signature)
	copy(serializedSignature[1+signatureLen:], pubKey)
	return base64.StdEncoding.EncodeToString(serializedSignature)
}

// SignAndExecuteTransactionBlock sign a transaction block and submit to the Fullnode for execution.
// adapted from sui-go-sdk/sui/signer.go for secp256k1
func (s *SignerSecp256k1) SignAndExecuteTransactionBlock(ctx context.Context, cli sui.ISuiAPI, req models.SignAndExecuteTransactionBlockRequest) (models.SuiTransactionBlockResponse, error) {
	txBytes, _ := base64.StdEncoding.DecodeString(req.TxnMetaData.TxBytes)
	message := messageWithIntent(txBytes)
	digest1 := blake2b.Sum256(message)
	// var noHash crypto.Hash
	digest2 := sha256.Sum256(digest1[:]) // this additional hash is required for secp256k1 but not ed25519

	// privBytes := crypto.FromECDSA(s.privkey)
	sigBytes, err := crypto2.Sign(digest2[:], s.privkey)
	if err != nil {
		log.Printf("SignAndExecuteTransactionBlock: %v", err)
		return models.SuiTransactionBlockResponse{}, err
	}
	sigBytes = sigBytes[:64]

	signature := ToSerializedSignature(sigBytes, s.GetPublicKey())

	return cli.SuiExecuteTransactionBlock(ctx, models.SuiExecuteTransactionBlockRequest{
		TxBytes:     req.TxnMetaData.TxBytes,
		Signature:   []string{signature},
		Options:     req.Options,
		RequestType: req.RequestType,
	})

}

func messageWithIntent(message []byte) []byte {
	intent := IntentBytes
	intentMessage := make([]byte, len(intent)+len(message))
	copy(intentMessage, intent)
	copy(intentMessage[len(intent):], message)
	return intentMessage
}

var IntentBytes = []byte{0, 0, 0}
