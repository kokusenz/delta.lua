.PHONY: setup setup-silent test test-file clean

setup:
	@mkdir -p deps
	@if [ ! -d "deps/mini.test" ]; then \
		echo "Installing mini.test for testing..."; \
		git clone --filter=blob:none https://github.com/nvim-mini/mini.test deps/mini.test; \
	else \
		echo "mini.test already installed"; \
	fi

setup-silent:
	@mkdir -p deps
	@if [ ! -d "deps/mini.test" ]; then \
		git clone --filter=blob:none https://github.com/nvim-mini/mini.test deps/mini.test; \
	fi

# Run all tests
test: setup-silent
	nvim --headless --noplugin -u scripts/minimal_init.lua -c "luafile scripts/test.lua"

# Run a specific test file
# Usage: make test-file FILE=tests/deltaview/test_diff.lua
test-file: setup-silent
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE is not set. Usage: make test-file FILE=tests/deltaview/test_diff.lua"; \
		exit 1; \
	fi
	nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')" -c "quit"

# Clean generated files and deps (next make test will reclone)
clean:
	find . -name "*.swp" -delete
	find . -name "*~" -delete
	rm -rf deps

help:
	@echo "Available targets:"
	@echo "  make setup          - Clone and install mini.test if not installed"
	@echo "  make setup-silent   - Clone and install mini.test if not installed, no messaging"
	@echo "  make test           - Run all tests"
	@echo "  make test-file FILE=<path> - Run a specific test file"
	@echo "  make clean          - Clean temporary files"
	@echo ""
	@echo "Examples:"
	@echo "  make test"
	@echo "  make test-file FILE=tests/deltaview/test_diff.lua"
