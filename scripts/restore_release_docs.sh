#!/usr/bin/env bash

set -euo pipefail

docs_root="${1:?usage: restore_release_docs.sh DOCS_ROOT [DOWNLOAD_ROOT]}"
download_root="${2:-${RUNNER_TEMP:-.release}/basic-cli-docs}"
repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"

mkdir -p "$docs_root" "$download_root"

release_names="$(
  gh api --paginate "repos/$repository/releases?per_page=100" \
    --jq '.[] | select(.draft == false and (.tag_name | startswith("linker-inputs-") | not)) | .tag_name'
)"

while IFS= read -r release_name; do
  [ -n "$release_name" ] || continue

  release_download_root="$download_root/$release_name"
  mkdir -p "$release_download_root"

  if gh release download "$release_name" \
    --repo "$repository" \
    --pattern docs.tar.gz \
    --dir "$release_download_root" \
    --clobber
  then
    mkdir -p "$docs_root/$release_name"
    tar -xzf "$release_download_root/docs.tar.gz" \
      -C "$docs_root/$release_name" \
      --strip-components=1
    echo "Restored docs for $release_name"
  else
    echo "No docs.tar.gz asset for $release_name; skipping"
  fi
done <<< "$release_names"

latest_stable="$(
  gh api "repos/$repository/releases/latest" --jq .tag_name 2>/dev/null || true
)"

if [ -n "$latest_stable" ]; then
  sed "s/LATESTVERSION/$latest_stable/g" docs/index.html > "$docs_root/index.html"
else
  sed 's/LATESTVERSION/main/g' docs/index.html > "$docs_root/index.html"
fi
