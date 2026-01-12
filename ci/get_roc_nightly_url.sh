#!/usr/bin/env bash
# Parse Cargo.toml to get Roc nightly info and construct download URL.
# This script exports: ROC_NIGHTLY_URL, ROC_NIGHTLY_ARCHIVE, ROC_NIGHTLY_COMMIT

set -eo pipefail

# Find Cargo.toml relative to this script or current directory
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CARGO_TOML="$SCRIPT_DIR/../Cargo.toml"
else
    # Fallback when sourced in unusual ways
    CARGO_TOML="Cargo.toml"
fi

# Parse nightly date from comment: # roc-nightly: 2026-01-12
ROC_NIGHTLY_DATE=$(grep -E '^# roc-nightly:' "$CARGO_TOML" | sed 's/.*: *//')
if [ -z "$ROC_NIGHTLY_DATE" ]; then
    echo "Error: Could not find '# roc-nightly:' comment in Cargo.toml" >&2
    exit 1
fi

# Parse commit from roc_std_new rev (take first 7 chars)
ROC_NIGHTLY_COMMIT=$(grep -E 'roc-lang/roc.*rev' "$CARGO_TOML" | sed 's/.*rev *= *"\([0-9a-fA-F]*\)".*/\1/' | cut -c1-7)
if [ -z "$ROC_NIGHTLY_COMMIT" ]; then
    echo "Error: Could not find roc commit in Cargo.toml" >&2
    exit 1
fi

# Convert month number to name for release tag
# Date format: YYYY-MM-DD -> YYYY-MonthName-DD
YEAR=$(echo "$ROC_NIGHTLY_DATE" | cut -d'-' -f1)
MONTH_NUM=$(echo "$ROC_NIGHTLY_DATE" | cut -d'-' -f2)
DAY=$(echo "$ROC_NIGHTLY_DATE" | cut -d'-' -f3)

case "$MONTH_NUM" in
    01) MONTH_NAME="January" ;;
    02) MONTH_NAME="February" ;;
    03) MONTH_NAME="March" ;;
    04) MONTH_NAME="April" ;;
    05) MONTH_NAME="May" ;;
    06) MONTH_NAME="June" ;;
    07) MONTH_NAME="July" ;;
    08) MONTH_NAME="August" ;;
    09) MONTH_NAME="September" ;;
    10) MONTH_NAME="October" ;;
    11) MONTH_NAME="November" ;;
    12) MONTH_NAME="December" ;;
    *)
        echo "Error: Invalid month number: $MONTH_NUM" >&2
        exit 1
        ;;
esac

# Detect platform
OS=$(uname -s)
ARCH=$(uname -m)

case "$OS" in
    Darwin)
        case "$ARCH" in
            arm64) PLATFORM="macos_apple_silicon" ;;
            x86_64) PLATFORM="macos_x86_64" ;;
            *)
                echo "Error: Unsupported macOS architecture: $ARCH" >&2
                exit 1
                ;;
        esac
        EXT="tar.gz"
        ;;
    Linux)
        case "$ARCH" in
            aarch64) PLATFORM="linux_arm64" ;;
            x86_64) PLATFORM="linux_x86_64" ;;
            *)
                echo "Error: Unsupported Linux architecture: $ARCH" >&2
                exit 1
                ;;
        esac
        EXT="tar.gz"
        ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
        case "$ARCH" in
            aarch64|arm64) PLATFORM="windows_arm64" ;;
            x86_64|AMD64) PLATFORM="windows_x86_64" ;;
            *)
                echo "Error: Unsupported Windows architecture: $ARCH" >&2
                exit 1
                ;;
        esac
        EXT="zip"
        ;;
    *)
        echo "Error: Unsupported OS: $OS" >&2
        exit 1
        ;;
esac

# Construct release tag: nightly-2026-January-12-36e9ff2
RELEASE_TAG="nightly-${YEAR}-${MONTH_NAME}-${DAY}-${ROC_NIGHTLY_COMMIT}"

# Construct archive name: roc_nightly-macos_apple_silicon-2026-01-12-36e9ff2.tar.gz
ROC_NIGHTLY_ARCHIVE="roc_nightly-${PLATFORM}-${ROC_NIGHTLY_DATE}-${ROC_NIGHTLY_COMMIT}.${EXT}"

# Construct full URL
ROC_NIGHTLY_URL="https://github.com/roc-lang/nightlies/releases/download/${RELEASE_TAG}/${ROC_NIGHTLY_ARCHIVE}"

# Export variables for use by calling scripts
export ROC_NIGHTLY_URL
export ROC_NIGHTLY_ARCHIVE
export ROC_NIGHTLY_COMMIT
export ROC_NIGHTLY_DATE
