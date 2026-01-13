#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$root_dir/platform"

# Collect all .roc files
roc_files=(*.roc)

# Collect all host libraries and runtime files from targets directories
lib_files=()
for lib in targets/*/*.a targets/*/*.o; do
    if [[ -f "$lib" ]]; then
        lib_files+=("$lib")
    fi
done

echo "Bundling ${#roc_files[@]} .roc files and ${#lib_files[@]} library files..."
echo ""
echo "Files to bundle:"
for f in "${roc_files[@]}"; do
    echo "  $f"
done
for f in "${lib_files[@]}"; do
    echo "  $f"
done
echo "  THIRD_PARTY_LICENSES.md"
echo ""

# Copy THIRD_PARTY_LICENSES.md into platform dir (roc bundle doesn't allow .. paths)
cp "$root_dir/THIRD_PARTY_LICENSES.md" .
trap 'rm -f THIRD_PARTY_LICENSES.md' EXIT

roc bundle "${roc_files[@]}" "${lib_files[@]}" THIRD_PARTY_LICENSES.md --output-dir "$root_dir" "$@"
