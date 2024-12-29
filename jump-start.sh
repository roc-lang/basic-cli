#!/usr/bin/env bash

## This script is only needed in the event of a breaking change in the
## Roc compiler that prevents build.roc from running.
## This script builds a local prebuilt binary for the native target,
## so that the build.roc script can be run.
##
## To use this, change the build.roc script to use the platform locally..

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -exo pipefail

if [ -z "${ROC}" ]; then
  echo "Warning: ROC environment variable is not set... I'll try with just 'roc'."

  ROC="roc"
fi

$ROC build --lib ./platform/libapp.roc

cargo build --release

if [ -n "$CARGO_BUILD_TARGET" ]; then
    cp target/$CARGO_BUILD_TARGET/release/libhost.a ./platform/libhost.a
else
    cp target/release/libhost.a ./platform/libhost.a
fi

$ROC build --linker=legacy build.roc

./build
