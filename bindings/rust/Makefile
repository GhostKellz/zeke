# Makefile for Zeke Rust Bindings
# Provides convenient targets for building, testing, and managing the Rust integration

.PHONY: all build test clean doc bench install lint fmt check help
.DEFAULT_GOAL := help

# Build configuration
CARGO := cargo
BUILD_TYPE ?= release
FEATURES ?= 
VERBOSE ?= 

# Directories
ROOT_DIR := $(shell pwd)
WORKSPACE_DIR := $(ROOT_DIR)
SCRIPT_DIR := $(ROOT_DIR)/../../scripts

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

# Build flags
ifeq ($(BUILD_TYPE), debug)
    CARGO_BUILD_FLAGS := 
    TARGET_DIR := target/debug
else
    CARGO_BUILD_FLAGS := --release
    TARGET_DIR := target/release
endif

ifdef FEATURES
    CARGO_BUILD_FLAGS += --features $(FEATURES)
endif

ifdef VERBOSE
    CARGO_BUILD_FLAGS += --verbose
endif

# Help target
help: ## Show this help message
	@echo "Zeke Rust Bindings - Available targets:"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-15s$(NC) %s\n", $$1, $$2}'
	@echo
	@echo "Variables:"
	@echo "  BUILD_TYPE    Build type: debug or release (default: release)"
	@echo "  FEATURES      Comma-separated feature list (default: empty)"
	@echo "  VERBOSE       Enable verbose output (default: empty)"
	@echo
	@echo "Examples:"
	@echo "  make build BUILD_TYPE=debug"
	@echo "  make test FEATURES=ghostllm,async"
	@echo "  make all VERBOSE=1"

# Main targets
all: build test doc ## Build everything and run tests

build: ## Build all crates
	@echo -e "$(BLUE)🔨 Building Rust bindings...$(NC)"
	$(CARGO) build --workspace $(CARGO_BUILD_FLAGS)
	@echo -e "$(GREEN)✅ Build complete$(NC)"

test: ## Run all tests
	@echo -e "$(BLUE)🧪 Running tests...$(NC)"
	$(CARGO) test --workspace $(CARGO_BUILD_FLAGS)
	@echo -e "$(GREEN)✅ Tests complete$(NC)"

clean: ## Clean build artifacts
	@echo -e "$(BLUE)🧹 Cleaning build artifacts...$(NC)"
	$(CARGO) clean
	@echo -e "$(GREEN)✅ Clean complete$(NC)"

doc: ## Generate documentation
	@echo -e "$(BLUE)📚 Generating documentation...$(NC)"
	$(CARGO) doc --workspace --no-deps $(CARGO_BUILD_FLAGS)
	@echo -e "$(GREEN)✅ Documentation generated$(NC)"
	@echo "Open: $(TARGET_DIR)/doc/zeke/index.html"

bench: ## Run benchmarks
	@echo -e "$(BLUE)🏃 Running benchmarks...$(NC)"
	$(CARGO) bench --workspace $(CARGO_BUILD_FLAGS)

lint: check ## Alias for check

check: ## Run clippy linter
	@echo -e "$(BLUE)🔍 Running clippy...$(NC)"
	$(CARGO) clippy --workspace --all-targets --all-features -- -D warnings

fmt: ## Format code
	@echo -e "$(BLUE)🎨 Formatting code...$(NC)"
	$(CARGO) fmt --all

fmt-check: ## Check code formatting
	@echo -e "$(BLUE)🎨 Checking code formatting...$(NC)"
	$(CARGO) fmt --all -- --check

# Installation targets
install: ## Install crates locally
	@echo -e "$(BLUE)📦 Installing crates...$(NC)"
	$(CARGO) install --path zeke --force $(CARGO_BUILD_FLAGS)
	@echo -e "$(GREEN)✅ Installation complete$(NC)"

uninstall: ## Uninstall crates
	@echo -e "$(BLUE)🗑️  Uninstalling crates...$(NC)"
	$(CARGO) uninstall zeke || true
	@echo -e "$(GREEN)✅ Uninstall complete$(NC)"

# Development targets
dev: ## Quick development build (debug mode)
	$(MAKE) build BUILD_TYPE=debug

dev-test: ## Run tests in development mode
	$(MAKE) test BUILD_TYPE=debug

watch: ## Watch for changes and rebuild
	@echo -e "$(BLUE)👁️  Watching for changes...$(NC)"
	$(CARGO) watch -x "build --workspace"

watch-test: ## Watch for changes and run tests
	@echo -e "$(BLUE)👁️  Watching for changes and running tests...$(NC)"
	$(CARGO) watch -x "test --workspace"

# Feature-specific builds
build-ghostllm: ## Build with GhostLLM features
	$(MAKE) build FEATURES=ghostllm

build-async: ## Build with async features
	$(MAKE) build FEATURES=async

build-full: ## Build with all features
	$(MAKE) build FEATURES=ghostllm,async,streaming

test-ghostllm: ## Test GhostLLM features
	$(MAKE) test FEATURES=ghostllm

test-async: ## Test async features
	$(MAKE) test FEATURES=async

test-full: ## Test all features
	$(MAKE) test FEATURES=ghostllm,async,streaming

# Release targets
release: ## Build optimized release
	$(MAKE) build BUILD_TYPE=release

release-test: ## Test release build
	$(MAKE) test BUILD_TYPE=release

# Package targets
package: ## Create distribution packages
	@echo -e "$(BLUE)📦 Creating packages...$(NC)"
	$(CARGO) package --workspace
	@echo -e "$(GREEN)✅ Packages created$(NC)"

publish-dry-run: ## Dry run package publishing
	@echo -e "$(BLUE)🚀 Dry run publish...$(NC)"
	$(CARGO) publish --workspace --dry-run

# Utility targets
deps: ## Update dependencies
	@echo -e "$(BLUE)📥 Updating dependencies...$(NC)"
	$(CARGO) update
	@echo -e "$(GREEN)✅ Dependencies updated$(NC)"

tree: ## Show dependency tree
	@echo -e "$(BLUE)🌳 Dependency tree:$(NC)"
	$(CARGO) tree --workspace

outdated: ## Check for outdated dependencies
	@echo -e "$(BLUE)📊 Checking for outdated dependencies...$(NC)"
	$(CARGO) outdated --workspace

audit: ## Security audit
	@echo -e "$(BLUE)🔒 Running security audit...$(NC)"
	$(CARGO) audit

# Docker targets (if needed)
docker-build: ## Build in Docker container
	@echo -e "$(BLUE)🐳 Building in Docker...$(NC)"
	docker run --rm -v $(PWD):/workspace -w /workspace rust:latest \
		cargo build --workspace --release

# Cross-compilation targets
build-linux: ## Cross-compile for Linux
	$(CARGO) build --workspace --target x86_64-unknown-linux-gnu $(CARGO_BUILD_FLAGS)

build-macos: ## Cross-compile for macOS
	$(CARGO) build --workspace --target x86_64-apple-darwin $(CARGO_BUILD_FLAGS)

build-windows: ## Cross-compile for Windows
	$(CARGO) build --workspace --target x86_64-pc-windows-gnu $(CARGO_BUILD_FLAGS)

# CI/CD helpers
ci: clean fmt-check check test ## Run CI pipeline locally

coverage: ## Generate test coverage report (requires cargo-tarpaulin)
	@echo -e "$(BLUE)📊 Generating coverage report...$(NC)"
	$(CARGO) tarpaulin --workspace --out Html --output-dir coverage/
	@echo -e "$(GREEN)✅ Coverage report: coverage/tarpaulin-report.html$(NC)"

# Setup targets
setup: ## Setup development environment
	@echo -e "$(BLUE)⚙️  Setting up development environment...$(NC)"
	rustup component add clippy rustfmt
	cargo install cargo-watch cargo-outdated cargo-audit cargo-tarpaulin || true
	@echo -e "$(GREEN)✅ Development environment setup complete$(NC)"

check-setup: ## Check development environment setup
	@echo -e "$(BLUE)🔍 Checking development environment...$(NC)"
	@command -v rustc >/dev/null && echo -e "$(GREEN)✅ Rust compiler$(NC)" || echo -e "$(RED)❌ Rust compiler$(NC)"
	@command -v cargo >/dev/null && echo -e "$(GREEN)✅ Cargo$(NC)" || echo -e "$(RED)❌ Cargo$(NC)"
	@command -v zig >/dev/null && echo -e "$(GREEN)✅ Zig compiler$(NC)" || echo -e "$(YELLOW)⚠️  Zig compiler (optional)$(NC)"
	@command -v clang >/dev/null && echo -e "$(GREEN)✅ Clang (for bindgen)$(NC)" || echo -e "$(YELLOW)⚠️  Clang (for bindgen)$(NC)"
	@cargo clippy --version >/dev/null 2>&1 && echo -e "$(GREEN)✅ Clippy$(NC)" || echo -e "$(YELLOW)⚠️  Clippy$(NC)"
	@cargo fmt --version >/dev/null 2>&1 && echo -e "$(GREEN)✅ Rustfmt$(NC)" || echo -e "$(YELLOW)⚠️  Rustfmt$(NC)"

# Information targets
info: ## Show build information
	@echo -e "$(BLUE)ℹ️  Build Information$(NC)"
	@echo "Workspace: $(WORKSPACE_DIR)"
	@echo "Build type: $(BUILD_TYPE)"
	@echo "Features: $(FEATURES)"
	@echo "Target directory: $(TARGET_DIR)"
	@echo "Cargo flags: $(CARGO_BUILD_FLAGS)"
	@echo
	@echo -e "$(BLUE)📊 Workspace Status$(NC)"
	@echo "Crates:"
	@$(CARGO) metadata --format-version 1 | grep -o '"name":"[^"]*"' | grep -o '[^"]*$$' | sort | uniq | sed 's/^/  - /'

size: ## Show binary sizes
	@echo -e "$(BLUE)📏 Binary sizes:$(NC)"
	@find $(TARGET_DIR) -name "*.rlib" -o -name "*.so" -o -name "*.dylib" -o -name "*.dll" | \
		xargs ls -lh | awk '{print $$9 ": " $$5}'