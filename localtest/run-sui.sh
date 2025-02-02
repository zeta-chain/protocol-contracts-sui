#!/bin/bash
# Function to clean up child processes
cleanup() {
  kill "$child_pid" "$timer_pid" 2>/dev/null
  exit 1
}
# Trap SIGINT (Ctrl-C) so we can do cleanup
trap cleanup INT


# Start the Sui process in the background
RUST_LOG="off,sui_node=info" sui start --with-faucet --force-regenesis &
child_pid=$!

# In a separate background job, sleep for 1 hour and then kill the Sui process
{
  sleep 3600  # 1 hour
  kill $child_pid 2>/dev/null
} &
timer_pid=$!

# Wait for the Sui process to finish, then kill the timer background job
wait $child_pid
kill $timer_pid 2>/dev/null
