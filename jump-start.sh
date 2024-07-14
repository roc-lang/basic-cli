#!/usr/bin/env bash

## This script is used to build a local prebuilt binary for the native target,
## so that the build.roc script can be run. This is only needed in the event
## of a breaking change in the roc compiler that prevents older version of the
## build script from running.
##
## To use this, change the build.roc script to use the platform locally..

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

roc build --lib ./platform/libapp.roc

roc glue glue.roc crates ./platform/main.roc

cargo build --release

cp target/release/libhost.a ./platform/macos-arm64.a || true
cp target/release/libhost.a ./platform/macos-x64.a || true
cp target/release/libhost.a ./platform/linux-arm64.a || true
cp target/release/libhost.a ./platform/linux-x64.a || true
cp target/release/libhost.lib ./platform/windows-arm64.lib || true
cp target/release/libhost.lib ./platform/windows-x64.lib || true

roc build build.roc
