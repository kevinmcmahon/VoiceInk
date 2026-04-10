# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build

.PHONY: all clean whisper fix-whisper setup build local check healthcheck help dev run

# Default target
all: check build

# Development workflow
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi
	@$(MAKE) fix-whisper

# Fix whisper.xcframework macOS framework structure.
# Upstream build-xcframework.sh produces a flat (iOS-style) framework for
# macOS and omits ggml headers that whisper.h depends on. This target patches
# the xcframework in-place so Xcode can consume it on macOS.
fix-whisper:
	@MACOS_FW=$$(find $(FRAMEWORK_PATH) -path "*/macos-*/whisper.framework" -type d 2>/dev/null | head -1); \
	if [ -z "$$MACOS_FW" ]; then \
		echo "No macOS whisper.framework found in xcframework, skipping fix"; \
		exit 0; \
	fi; \
	GGML_INCLUDE=$(WHISPER_CPP_DIR)/ggml/include; \
	echo "Fixing whisper.xcframework macOS framework..."; \
	\
	if [ ! -d "$$MACOS_FW/Versions" ]; then \
		echo "  Converting flat framework to versioned macOS structure..."; \
		mkdir -p "$$MACOS_FW/Versions/A/Headers" \
		         "$$MACOS_FW/Versions/A/Modules" \
		         "$$MACOS_FW/Versions/A/Resources"; \
		mv "$$MACOS_FW/Headers/"* "$$MACOS_FW/Versions/A/Headers/"; \
		mv "$$MACOS_FW/Modules/"* "$$MACOS_FW/Versions/A/Modules/"; \
		mv "$$MACOS_FW/Info.plist" "$$MACOS_FW/Versions/A/Resources/Info.plist"; \
		mv "$$MACOS_FW/whisper" "$$MACOS_FW/Versions/A/whisper"; \
		rmdir "$$MACOS_FW/Headers" "$$MACOS_FW/Modules"; \
		ln -sf A "$$MACOS_FW/Versions/Current"; \
		ln -sf Versions/Current/Headers "$$MACOS_FW/Headers"; \
		ln -sf Versions/Current/Modules "$$MACOS_FW/Modules"; \
		ln -sf Versions/Current/Resources "$$MACOS_FW/Resources"; \
		ln -sf Versions/Current/whisper "$$MACOS_FW/whisper"; \
	fi; \
	\
	HEADER_DIR="$$MACOS_FW/Versions/A/Headers"; \
	if [ ! -f "$$HEADER_DIR/ggml.h" ]; then \
		echo "  Copying missing ggml headers..."; \
		cp "$$GGML_INCLUDE/ggml.h"         "$$HEADER_DIR/"; \
		cp "$$GGML_INCLUDE/ggml-alloc.h"   "$$HEADER_DIR/"; \
		cp "$$GGML_INCLUDE/ggml-backend.h" "$$HEADER_DIR/"; \
		cp "$$GGML_INCLUDE/ggml-metal.h"   "$$HEADER_DIR/"; \
		cp "$$GGML_INCLUDE/ggml-cpu.h"     "$$HEADER_DIR/"; \
		cp "$$GGML_INCLUDE/ggml-blas.h"    "$$HEADER_DIR/"; \
		cp "$$GGML_INCLUDE/gguf.h"         "$$HEADER_DIR/"; \
	fi; \
	echo "  whisper.xcframework macOS fix applied"

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" build

# Build for local use without Apple Developer certificate
local: check setup
	@echo "Building VoiceInk for local use (no Apple Developer certificate required)..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/VoiceInk.app" && \
	if [ -d "$$APP_PATH" ]; then \
		echo "Copying VoiceInk.app to ~/Downloads..."; \
		rm -rf "$$HOME/Downloads/VoiceInk.app"; \
		ditto "$$APP_PATH" "$$HOME/Downloads/VoiceInk.app"; \
		xattr -cr "$$HOME/Downloads/VoiceInk.app"; \
		echo ""; \
		echo "Build complete! App saved to: ~/Downloads/VoiceInk.app"; \
		echo "Run with: open ~/Downloads/VoiceInk.app"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built VoiceInk.app at $$APP_PATH"; \
		exit 1; \
	fi

# Run application
run:
	@if [ -d "$$HOME/Downloads/VoiceInk.app" ]; then \
		echo "Opening ~/Downloads/VoiceInk.app..."; \
		open "$$HOME/Downloads/VoiceInk.app"; \
	else \
		echo "Looking for VoiceInk.app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "VoiceInk.app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "VoiceInk.app not found. Please run 'make build' or 'make local' first."; \
			exit 1; \
		fi; \
	fi

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  fix-whisper        Patch xcframework for macOS (headers + versioned structure)"
	@echo "  setup              Copy whisper XCFramework to VoiceInk project"
	@echo "  build              Build the VoiceInk Xcode project"
	@echo "  local              Build for local use (no Apple Developer certificate needed)"
	@echo "  run                Launch the built VoiceInk app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
