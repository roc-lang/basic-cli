#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -exo pipefail

if [ -z "${EXAMPLES_DIR}" ]; then
  echo "ERROR: The EXAMPLES_DIR environment variable is not set." >&2
  
  exit 1
fi

if [ -z "${ROC}" ]; then
  echo "ERROR: The ROC environment variable is not set.
    Set it to something like:
        /home/username/Downloads/roc_nightly-linux_x86_64-2023-10-30-cb00cfb/roc
        or
        /home/username/gitrepos/roc/target/build/release/roc" >&2

  exit 1
fi

# roc check
for roc_file in $EXAMPLES_DIR*.roc; do
    $ROC check $roc_file
done

# roc build
architecture=$(uname -m)

for roc_file in $EXAMPLES_DIR*.roc; do
    base_file=$(basename "$roc_file")

    # Skip argsBROKEN.roc
    if [ "$base_file" == "argsBROKEN.roc" ]; then
        continue
    fi

    # Skip env.roc when on aarch64
    if [ "$architecture" == "aarch64" ] && [ "$base_file" == "env.roc" ]; then
        continue
    fi

    $ROC build $roc_file $ROC_BUILD_FLAGS
done

# check output
for roc_file in $EXAMPLES_DIR*.roc; do
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

# `roc test` every roc file if it contains a test
find . -type f -name "*.roc" | while read file; do
    # Arg.roc hits github.com/roc-lang/roc/issues/5701
    if [[ $file != *"Arg.roc" ]]; then
    
        if grep -qE '^\s*expect(\s+|$)' "$file"; then
            test_output=$($ROC test "$file" 2>&1)
            test_exit_code=$?

            if [[ $test_exit_code -ne 0 ]]; then
                if ! [[ $test_exit_code -eq 2 && "$test_output" == *"No expectations were found."* ]]; then
                    exit $test_exit_code
                fi
            fi
        fi
    fi
done

# just build this until we fix it
$ROC build ./ci/file-testBROKEN.roc $ROC_BUILD_FLAGS

# test building website
$ROC docs platform/main.roc
