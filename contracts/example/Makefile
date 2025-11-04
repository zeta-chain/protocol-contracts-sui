.PHONY: clean build

# Clean build directory
clean:
	rm -rf Move.lock build/

# Build the package and generate bytecode
build:
	sui move build

# Help target
help:
	@echo "Available targets:"
	@echo "  clean  - Remove build directory"
	@echo "  build  - Build the example package and generate bytecode"
	@echo "  help   - Show this help message"