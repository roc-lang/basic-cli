#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

if [ -z "${EXAMPLES_DIR}" ]; then
  echo "ERROR: The EXAMPLES_DIR environment variable is not set." >&2
  exit 1
fi

# Install jq if it's not already available
command -v jq &>/dev/null || sudo apt install -y jq

# Get the latest roc nightly
curl -fOL https://github.com/roc-lang/roc/releases/download/nightly/roc_nightly-linux_x86_64-latest.tar.gz

# Rename nightly tar
TAR_NAME=$(ls | grep "roc_nightly.*tar\.gz")
mv "$TAR_NAME" roc_nightly.tar.gz

# Decompress the tar
tar -xzf roc_nightly.tar.gz

# Remove the tar file
rm roc_nightly.tar.gz

# Simplify nightly folder name
NIGHTLY_FOLDER=$(ls -d roc_nightly*/)
mv "$NIGHTLY_FOLDER" roc_nightly

# Print the roc version
./roc_nightly/roc version

# Get the latest basic-cli release file URL
CLI_RELEASES_JSON=$(curl -s https://api.github.com/repos/roc-lang/basic-cli/releases)
CLI_RELEASE_URL=$(echo $CLI_RELEASES_JSON | jq -r '.[0].assets | .[] | select(.name | test("\\.tar\\.br$")) | .browser_download_url')

# Use the latest basic-cli release as the platform for every example
sed -i "s|../platform/main.roc|$CLI_RELEASE_URL|g" $EXAMPLES_DIR/*.roc

# Install required packages for tests if they're not already available
command -v ncat &>/dev/null || sudo apt install -y ncat
command -v expect &>/dev/null || sudo apt install -y expect

ROC=./roc_nightly/roc ./ci/all_tests.sh

