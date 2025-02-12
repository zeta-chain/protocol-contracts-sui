
## Prerequisites
install SUI toolchain: https://github.com/MystenLabs/sui

## Unit test

```
sui move test
```

## Integration Test

First compile and run the validator
```
./localhost/run-sui.sh
```
Then run the test program
```
cd localhost && go run .
```

If successful you will not see any panic.

## TODO
- [ ] cryptography: native multisig
- [ ] call user specified contract
