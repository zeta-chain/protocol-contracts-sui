
This repository hosts the smart contract deployed on the SUI network to enable ZetaChain's cross-chain functionality.

## Prerequisites
install SUI toolchain: https://github.com/MystenLabs/sui

## Unit test

```
sui move test
```

## Integration Test

First compile and run the validator
```
./localtest/run-sui.sh
```
Then run the test program
```
cd localtest && go run main.go
```

If successful you will not see any panic.
