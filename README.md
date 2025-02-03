
## Prerequisites
install SUI toolchain: https://github.com/MystenLabs/sui


## Test

First compile and run the validator
```
./localhost/run-sui.sh
```
Then run the test program
```
cd localhost && go run main.go
```

If successful you will not see any panic.

## TODO
- [ ] cryptography: native multisig
- [ ] call user specified contract
