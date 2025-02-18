
This repository hosts the smart contract deployed on the SUI network to enable ZetaChain's cross-chain functionality.

## Prerequisites
install SUI toolchain: https://github.com/MystenLabs/sui

## Unit test

```sh
sui move test
```

## Integration Test

First compile and run the validator
```sh
./localtest/run-sui.sh
```
Then run the test program
```sh
cd localtest && go run ./...
```

You can also keep Sui localnet after test runs 
```sh
cd localtest && go run ./... -keep-running
```

If successful you will not see any panic.
