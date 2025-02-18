package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

// RunLocalnet builds smart-contracts and runs Sui node locally
func RunLocalnet() (*exec.Cmd, []byte) {
	// Build Sui Move package
	buildCmd := exec.Command("sui", "move", "build")
	err := buildCmd.Run()
	guard(err)

	gwBinary, err := os.ReadFile("../build/gateway/bytecode_modules/gateway.mv")
	guard(err)

	fmt.Println("Built contract binary")

	// Prepare Sui start command with environment variables
	suiCmd := exec.Command("sui", "start", "--with-faucet", "--force-regenesis")
	suiCmd.Env = append(os.Environ(), "RUST_LOG=off,sui_node=info")
	suiCmd.Stdout = os.Stdout
	suiCmd.Stderr = os.Stderr

	// Start Sui process
	err = suiCmd.Start()
	guard(err)

	fmt.Printf("Sui node started, PID: %d\n", suiCmd.Process.Pid)

	waitForLocalnet()

	return suiCmd, gwBinary
}

func waitForLocalnet() {
	fmt.Println("Waiting for Sui node to bootstrap...")

	for i := 0; i < 100; i++ {
		err := requestLocalNetSuiFromFaucet("0x")
		if err != nil && strings.Contains(err.Error(), "connection refused") {
			fmt.Println("Retrying...")
			time.Sleep(2 * time.Second)
			continue
		}
		break
	}
}
