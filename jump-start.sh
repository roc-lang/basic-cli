#!/usr/bin/env bash

## This script is only needed in the event of a breaking change in the
## Roc compiler that prevents build.roc from running.
## This script builds a local prebuilt binary for the native target,
## so that the build.roc script can be run. 
##
## To use this, change the build.roc script to use the platform locally..

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

roc build --lib ./platform/libapp.roc

roc glue glue.roc crates ./platform/main.roc

cargo build --release

cp target/release/libhost.a ./platform/libhost.a

roc build --linker=legacy build.roc
