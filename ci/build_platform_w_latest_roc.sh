#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

# get the url of the latest release for linux_x86_64
RELEASE_URL=$(./ci/get_latest_release_url.sh $1)

# get the archive from the url
mkdir roc_nightly && cd roc_nightly && curl -OL $RELEASE_URL

# decompress the tar
ls | grep "roc_nightly.*tar\.gz" | xargs tar -xzvf

# back to root dir
cd ..

# build the basic cli platform
./roc_nightly/roc build examples/file.roc
