#!/bin/bash

sui move build --doc
rm -rf docs
mkdir -p docs
rsync -a build/gateway/docs/gateway/ docs/