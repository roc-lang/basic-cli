#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

roc='./roc_nightly/roc'

# Use EXAMPLES_DIR if set, otherwise use a default value
examples_dir="${EXAMPLES_DIR:-./examples/}"

# roc check
for roc_file in $examples_dir*.roc; do
    $roc check $roc_file
done

# roc build
architecture=$(uname -m)

for roc_file in $examples_dir*.roc; do
    base_file=$(basename "$roc_file")

    # Skip argsBROKEN.roc
    if [ "$base_file" == "argsBROKEN.roc" ]; then
        continue
    fi

    # Skip env.roc when on aarch64
    if [ "$architecture" == "aarch64" ] && [ "$base_file" == "env.roc" ]; then
        continue
    fi

    $roc build $roc_file
done

# check output
for roc_file in $examples_dir*.roc; do
    base_file=$(basename "$roc_file")

    # Skip argsBROKEN.roc
    if [ "$base_file" == "argsBROKEN.roc" ]; then
        continue
    fi

    # Skip env.roc when on aarch64
    if [ "$architecture" == "aarch64" ] && [ "$base_file" == "env.roc" ]; then
        continue
    fi

    roc_file_only="$(basename "$roc_file")"
    no_ext_name=${roc_file_only%.*}
    expect ci/expect_scripts/$no_ext_name.exp
done

# just build this until we fix it
./roc_nightly/roc build ./ci/file-testBROKEN.roc

# test building website
$roc docs src/main.roc
