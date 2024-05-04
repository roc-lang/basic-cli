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

# remove Dir example directorys if they exist
rm -rf dirExampleE
rm -rf dirExampleA
rm -rf dirExampleD

# roc dev (some expects only run with `roc dev`)
for roc_file in $EXAMPLES_DIR*.roc; do
    base_file=$(basename "$roc_file")

    # Skip argsBROKEN.roc
    #      countdown, echo, form, piping, stdin require user input
    #      dir.roc hits `index out of bounds: the len is...`
    ignore_list=("argsBROKEN.roc" "countdown.roc" "echo.roc" "form.roc" "piping.roc" "stdin.roc")

    # check if base_file matches something from ignore_list
    for file in "${ignore_list[@]}"; do
        if [ "$base_file" == "$file" ]; then
            continue 2 # continue the outer loop if a match is found
        fi
    done

    # Skip env.roc when on aarch64
    if [ "$architecture" == "aarch64" ] && [ "$base_file" == "env.roc" ]; then
        continue
    fi

    # For path.roc we need be inside the EXAMPLES_DIR
    if [ "$base_file" == "path.roc" ]; then
        absolute_roc=$(which $ROC | xargs realpath)
        cd $EXAMPLES_DIR
        $absolute_roc dev $base_file $ROC_BUILD_FLAGS
        cd ..
    else
        $ROC dev $roc_file $ROC_BUILD_FLAGS
    fi
done

# remove Dir example directorys if they exist
rm -rf dirExampleE
rm -rf dirExampleA
rm -rf dirExampleD

# `roc test` every roc file if it contains a test, skip roc_nightly folder
find . -type d -name "roc_nightly" -prune -o -type f -name "*.roc" -print | while read file; do
    # Arg.roc hits github.com/roc-lang/roc/issues/5701
    if [[ $file != *"Arg.roc" ]]; then
    
        if grep -qE '^\s*expect(\s+|$)' "$file"; then

            # don't exit script if test_command fails
            set +e
            test_command=$($ROC test "$file")
            test_exit_code=$?
            set -e

            if [[ $test_exit_code -ne 0 && $test_exit_code -ne 2 ]]; then
                exit $test_exit_code
            fi
        fi
    fi
done

# test building website
$ROC docs platform/main.roc
