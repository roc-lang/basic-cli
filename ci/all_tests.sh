#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

# Cleanup function to restore examples and stop HTTP server
cleanup() {
    echo ""
    echo "=== Cleaning up ==="

    # Restore examples from backups
    for f in examples/*.roc.bak; do
        if [ -f "$f" ]; then
            mv "$f" "${f%.bak}"
        fi
    done

    # Stop HTTP server if running
    if [ -n "${HTTP_SERVER_PID:-}" ]; then
        kill "$HTTP_SERVER_PID" 2>/dev/null || true
    fi

    # Remove built binaries
    for example in "${MIGRATED_EXAMPLES[@]}"; do
        rm -f "examples/${example}"
    done

    # Remove bundle file
    if [ -n "${BUNDLE_FILE:-}" ] && [ -f "$BUNDLE_FILE" ]; then
        rm -f "$BUNDLE_FILE"
    fi
}

# Set up trap to ensure cleanup runs on exit
trap cleanup EXIT

# Get nightly version info from Cargo.toml
source ci/get_roc_nightly_url.sh
NEED_DOWNLOAD=false

echo "=== basic-cli CI ==="
echo ""

# Check if cached roc exists and matches pinned version
ROC_DIR="roc_nightly-${ROC_NIGHTLY_DATE}-${ROC_NIGHTLY_COMMIT}"
if [ -d "$ROC_DIR" ] && [ -f "$ROC_DIR/roc" ]; then
    CACHED_VERSION=$("./$ROC_DIR/roc" version 2>/dev/null || echo "unknown")
    if echo "$CACHED_VERSION" | grep -q "$ROC_NIGHTLY_COMMIT"; then
        echo "roc already at correct version: $CACHED_VERSION"
    else
        echo "Cached roc ($CACHED_VERSION) doesn't match nightly ($ROC_NIGHTLY_COMMIT)"
        echo "Removing stale roc directory..."
        rm -rf "$ROC_DIR"
        NEED_DOWNLOAD=true
    fi
else
    NEED_DOWNLOAD=true
fi

if [ "$NEED_DOWNLOAD" = true ]; then
    echo "Downloading Roc nightly $ROC_NIGHTLY_COMMIT..."
    echo "URL: $ROC_NIGHTLY_URL"

    # Clean up any old nightly directories
    rm -rf roc_nightly-*

    curl -fOL "$ROC_NIGHTLY_URL"
    tar -xzf "$ROC_NIGHTLY_ARCHIVE"
    rm -f "$ROC_NIGHTLY_ARCHIVE"

    # Find the extracted directory
    ROC_DIR=$(ls -d roc_nightly-*/ 2>/dev/null | head -1 | sed 's|/$||')

    # Add to GITHUB_PATH if running in CI
    if [ -n "${GITHUB_PATH:-}" ]; then
        echo "$(pwd)/$ROC_DIR" >> "$GITHUB_PATH"
    fi
fi

# Ensure roc is in PATH
export PATH="$(pwd)/$ROC_DIR:$PATH"

echo ""
echo "Using roc version: $(roc version)"

if [ "$(uname -s)" = "Darwin" ] && [ -z "${SDKROOT:-}" ]; then
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ -n "$SDKROOT" ]; then
        export SDKROOT
        echo "Using SDKROOT: $SDKROOT"
    fi
fi

# Build the platform
if [ "${NO_BUILD:-}" != "1" ]; then
    echo ""
    echo "=== Building platform ==="
    ./build.sh
else
    echo ""
    echo "=== Skipping platform build (NO_BUILD=1) ==="
fi

# List of migrated examples that have expect tests
MIGRATED_EXAMPLES=(
    "command-line-args"
    "hello-world"
    "stdin-basic"
    "path"
    "command"
    "time"
    "random"
    "locale"
    "tty"
)

EXAMPLES_DIR="${ROOT_DIR}/examples/"
export EXAMPLES_DIR

# Check if all target libraries exist for bundling
ALL_TARGETS_EXIST=true
for target in x64mac arm64mac x64musl arm64musl; do
    if [ ! -f "platform/targets/$target/libhost.a" ]; then
        ALL_TARGETS_EXIST=false
        break
    fi
done

# Bundle and set up HTTP server if all targets exist
BUNDLE_FILE=""
HTTP_SERVER_PID=""
USE_BUNDLE=false

if [ "$ALL_TARGETS_EXIST" = true ]; then
    echo ""
    echo "=== Bundling platform ==="
    BUNDLE_OUTPUT=$(./bundle.sh 2>&1)
    echo "$BUNDLE_OUTPUT"

    # Extract bundle filename from output
    BUNDLE_PATH=$(echo "$BUNDLE_OUTPUT" | grep "^Created:" | awk '{print $2}')
    BUNDLE_FILE=$(basename "$BUNDLE_PATH")

    if [ -n "$BUNDLE_FILE" ] && [ -f "$BUNDLE_FILE" ]; then
        echo ""
        echo "=== Starting HTTP server for bundle testing ==="
        python3 -m http.server 8000 &
        HTTP_SERVER_PID=$!
        sleep 2

        # Verify server is running
        if curl -f -I "http://localhost:8000/$BUNDLE_FILE" > /dev/null 2>&1; then
            echo "HTTP server running at http://localhost:8000"
            echo "Bundle: $BUNDLE_FILE"

            # Modify examples to use bundle URL
            echo ""
            echo "=== Configuring examples to use bundle ==="
            for example in examples/*.roc; do
                sed -i.bak "s|platform \"../platform/main.roc\"|platform \"http://localhost:8000/$BUNDLE_FILE\"|" "$example"
            done
            USE_BUNDLE=true
        else
            echo "Warning: HTTP server failed to start, testing with local platform"
            kill "$HTTP_SERVER_PID" 2>/dev/null || true
            HTTP_SERVER_PID=""
        fi
    else
        echo "Warning: Bundle creation failed, testing with local platform"
    fi
else
    echo ""
    echo "=== Skipping bundle (not all targets built) ==="
    echo "Run './build.sh --all' first to test with bundled platform"
fi

# roc check migrated examples
echo ""
echo "=== Checking examples ==="
for example in "${MIGRATED_EXAMPLES[@]}"; do
    echo "Checking: ${example}.roc"
    roc check "examples/${example}.roc"
done

# roc build migrated examples
echo ""
if [ "$USE_BUNDLE" = true ]; then
    echo "=== Building examples (using bundle) ==="
else
    echo "=== Building examples (using local platform) ==="
fi
for example in "${MIGRATED_EXAMPLES[@]}"; do
    echo "Building: ${example}.roc"
    roc build "examples/${example}.roc"
    mv "./${example}" "examples/"
done

# Run expect tests
echo ""
echo "=== Running expect tests ==="
FAILED=0
for example in "${MIGRATED_EXAMPLES[@]}"; do
    echo ""
    echo "--- Testing: $example ---"
    set +e
    expect "ci/expect_scripts/${example}.exp"
    EXIT_CODE=$?
    set -e
    if [ $EXIT_CODE -eq 0 ]; then
        echo "PASS: $example"
    else
        echo "FAIL: $example (exit code: $EXIT_CODE)"
        FAILED=1
    fi
done

echo ""
if [ $FAILED -eq 0 ]; then
    if [ "$USE_BUNDLE" = true ]; then
        echo "=== All tests passed (with bundle)! ==="
    else
        echo "=== All tests passed! ==="
    fi
else
    echo "=== Some tests failed ==="
    exit 1
fi
