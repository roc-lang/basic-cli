#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

mkdir latest-basic-cli-src && cd latest-basic-cli-src

# get basic-cli
git clone --depth 1 https://github.com/roc-lang/basic-cli

cd basic-cli

# Fetch all tags
git fetch --tags

# Get the latest tag matching pattern X.Y*
latestTag=$(git for-each-ref --sort=-version:refname --format '%(refname:short)' refs/tags/ | grep -E '^[0-9]+\.[0-9]+.*' | head -n1)

# Checkout the latest tag
git checkout $latestTag

mv * ../../

cd ../..
