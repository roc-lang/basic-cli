#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROC_BIN="${ROC:-roc}"
PLATFORM_FILE="${PLATFORM_FILE:-platform/main.roc}"
GLUE_OUT_DIR="${GLUE_OUT_DIR:-src}"
MODE="write"

usage() {
    cat <<'EOF'
Usage: ci/regenerate_glue.sh [--check]

Regenerate Rust ABI bindings for the basic-cli Roc platform.

Environment overrides:
  ROC             Roc executable to run. Default: roc
  ROC_SRC         Path to a Roc source checkout containing src/glue/src/RustGlue.roc
  ROC_GLUE_SPEC   Explicit path to RustGlue.roc
  PLATFORM_FILE   Platform file to analyze. Default: platform/main.roc
  GLUE_OUT_DIR    Output directory. Default: src

By default the script looks for RustGlue.roc in ROC_GLUE_SPEC, ROC_SRC,
next to the ROC binary if it is from a source checkout, then sibling ../roc.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
elif [ "${1:-}" = "--check" ]; then
    MODE="check"
elif [ "${1:-}" != "" ]; then
    usage >&2
    exit 2
fi

find_glue_spec() {
    if [ -n "${ROC_GLUE_SPEC:-}" ]; then
        echo "$ROC_GLUE_SPEC"
        return 0
    fi

    candidates=()

    if [ -n "${ROC_SRC:-}" ]; then
        candidates+=("${ROC_SRC%/}/src/glue/src/RustGlue.roc")
    fi

    roc_path="$(command -v "$ROC_BIN" 2>/dev/null || true)"
    if [ -n "$roc_path" ]; then
        roc_bin_dir="$(cd "$(dirname "$roc_path")" 2>/dev/null && pwd || true)"
        if [ -n "$roc_bin_dir" ]; then
            roc_source_root="$(cd "$roc_bin_dir/../.." 2>/dev/null && pwd || true)"
            if [ -n "$roc_source_root" ]; then
                candidates+=("$roc_source_root/src/glue/src/RustGlue.roc")
            fi

            if [ "$(basename "$roc_bin_dir")" = "bin" ] && [ "$(basename "$(dirname "$roc_bin_dir")")" = "zig-out" ]; then
                roc_checkout_root="$(cd "$roc_bin_dir/../../.." 2>/dev/null && pwd || true)"
                if [ -n "$roc_checkout_root" ]; then
                    candidates+=("$roc_checkout_root/src/glue/src/RustGlue.roc")
                fi
            fi
        fi
    fi

    candidates+=(
        "../roc/src/glue/src/RustGlue.roc"
        "../../roc/src/glue/src/RustGlue.roc"
    )

    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    echo "Could not find RustGlue.roc." >&2
    echo "Set ROC_SRC=/path/to/roc or ROC_GLUE_SPEC=/path/to/RustGlue.roc." >&2
    return 1
}

GLUE_SPEC="$(find_glue_spec)"

if ! command -v "$ROC_BIN" >/dev/null 2>&1; then
    echo "Could not find roc executable '$ROC_BIN'. Set ROC=/path/to/roc." >&2
    exit 1
fi

if [ ! -f "$PLATFORM_FILE" ]; then
    echo "Platform file not found: $PLATFORM_FILE" >&2
    exit 1
fi

run_glue() {
    local out_dir=$1
    mkdir -p "$out_dir"
    "$ROC_BIN" glue --no-cache "$GLUE_SPEC" "$out_dir" "$PLATFORM_FILE"
}

if [ "$MODE" = "check" ]; then
    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/basic-cli-glue.XXXXXX")"
    cleanup() { rm -rf "$tmp_dir"; }
    trap cleanup EXIT

    run_glue "$tmp_dir"

    generated="$tmp_dir/roc_platform_abi.rs"
    committed="$GLUE_OUT_DIR/roc_platform_abi.rs"

    if [ ! -f "$committed" ]; then
        echo "Missing generated glue file: $committed" >&2
        exit 1
    fi

    if ! diff -u "$committed" "$generated"; then
        echo "Generated Rust glue is stale. Run ci/regenerate_glue.sh and commit the result." >&2
        exit 1
    fi

    echo "Rust glue is up to date: $committed"
else
    echo "Using roc: $ROC_BIN"
    echo "Using glue spec: $GLUE_SPEC"
    echo "Platform: $PLATFORM_FILE"
    echo "Output dir: $GLUE_OUT_DIR"
    run_glue "$GLUE_OUT_DIR"
    echo "Generated: $GLUE_OUT_DIR/roc_platform_abi.rs"
fi
