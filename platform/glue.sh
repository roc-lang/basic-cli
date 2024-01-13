#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

echo "Removing old glue files..."
rm -rf platform/glue

echo "Generating glue files..."
roc glue ../roc/crates/glue/src/RustGlue.roc platform/glue platform/main-glue.roc

# Manually fixup glue errors

# Determine OS type
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS (BSD $SED_COMMAND)
    SED_COMMAND="sed -i ''"
else
    # Assuming Linux (GNU sed)
    SED_COMMAND="sed -i"
fi

for file in platform/glue/roc_app/src/*.rs; do
    $SED_COMMAND '/const _SIZE_CHECK_union_ReadErr/s/^/\/\//' "$file"
    $SED_COMMAND '/const _SIZE_CHECK_union_ConnectErr/s/^/\/\//' "$file"
    $SED_COMMAND '/const _SIZE_CHECK_union_StreamErr/s/^/\/\//' "$file"
    $SED_COMMAND '/const _SIZE_CHECK_union_ReadErr/s/^/\/\//' "$file"
    $SED_COMMAND '/const _SIZE_CHECK_union_WriteErr/s/^/\/\//' "$file"
done


