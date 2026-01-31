#!/usr/bin/env bash
set -eo pipefail

# Build script for basic-cli platform
# Usage:
#   ./build.sh         - Build for native target only
#   ./build.sh --all   - Build for all targets (cross-compilation)

# Get rust triple for a target name
get_rust_triple() {
    case "$1" in
        x64mac)    echo "x86_64-apple-darwin" ;;
        arm64mac)  echo "aarch64-apple-darwin" ;;
        x64musl)   echo "x86_64-unknown-linux-musl" ;;
        arm64musl) echo "aarch64-unknown-linux-musl" ;;
        *) echo "Unknown target: $1" >&2; exit 1 ;;
    esac
}


# All supported targets
ALL_TARGETS="x64mac arm64mac x64musl arm64musl"

# Detect native target based on current platform
detect_native_target() {
    local arch=$(uname -m)
    local os=$(uname -s)

    if [ "$os" = "Darwin" ]; then
        if [ "$arch" = "arm64" ]; then
            echo "arm64mac"
        else
            echo "x64mac"
        fi
    elif [ "$os" = "Linux" ]; then
        if [ "$arch" = "aarch64" ]; then
            echo "arm64musl"
        else
            echo "x64musl"
        fi
    else
        echo "Unsupported OS: $os" >&2
        exit 1
    fi
}

# Build for a specific target (cross-compile)
build_target_cross() {
    local target_name=$1
    local rust_triple=$(get_rust_triple "$target_name")

    echo "Building for $target_name ($rust_triple)..."
    cargo build --release --lib --target "$rust_triple"

    mkdir -p "platform/targets/$target_name"
    cp "target/$rust_triple/release/libhost.a" "platform/targets/$target_name/"
    echo "  -> platform/targets/$target_name/libhost.a"
}

# Build for native target
# On macOS: no --target needed (native is fine)
# On Linux: must use --target for musl, since default is glibc
build_target_native() {
    local target_name=$1
    local rust_triple=$(get_rust_triple "$target_name")

    echo "Building for $target_name (native)..."

    # On macOS, native build is fine
    # On Linux, we must explicitly target musl (default is glibc)
    if [[ "$target_name" == *"musl"* ]]; then
        # Linux: need explicit musl target
        rustup target add "$rust_triple" 2>/dev/null || true
        cargo build --release --lib --target "$rust_triple"
        mkdir -p "platform/targets/$target_name"
        cp "target/$rust_triple/release/libhost.a" "platform/targets/$target_name/"
    else
        # macOS: native is fine
        cargo build --release --lib
        mkdir -p "platform/targets/$target_name"
        cp "target/release/libhost.a" "platform/targets/$target_name/"
    fi

    echo "  -> platform/targets/$target_name/libhost.a"
}

# Main logic
if [ "${1:-}" = "--all" ]; then
    echo "Building for all targets..."
    echo ""

    # Ensure all rust targets are installed
    echo "Installing Rust targets..."
    for target_name in $ALL_TARGETS; do
        rust_triple=$(get_rust_triple "$target_name")
        rustup target add "$rust_triple" 2>/dev/null || true
    done
    echo ""

    # Build each target (cross-compile)
    for target_name in $ALL_TARGETS; do
        build_target_cross "$target_name"
        echo ""
    done

    echo "All targets built successfully!"
else
    # Build for native target only (no cross-compile)
    TARGET=$(detect_native_target)
    echo "Building for native target: $TARGET"
    echo ""

    build_target_native "$TARGET"

    echo ""
    echo "Build complete!"
fi
