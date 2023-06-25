#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

roc='./roc_nightly/roc'

$roc check ./examples/args.roc
$roc check ./examples/command.roc
$roc check ./examples/countdown.roc
$roc check ./examples/echo.roc
$roc check ./examples/env.roc
$roc check ./examples/file-mixedBROKEN.roc
$roc check ./examples/file-read.roc
$roc check ./examples/form.roc
$roc check ./examples/http-get.roc
$roc check ./examples/record-builder.roc
$roc check ./examples/stdin.roc
$roc check ./examples/tcp-client.roc
$roc check ./examples/time.roc

# test building website
$roc docs src/main.roc
