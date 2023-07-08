#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

base_url="https://www.roc-lang.org/packages/basic-cli/"

timeout=15 #timeout in seconds 

broken_links=()

extract_links() {
  curl -s "$1" | grep -Eo 'href="([^"#]+)"' | cut -d'"' -f2
}

links=$(extract_links "$base_url")

for link in "${links[@]}"; do
  full_link="${base_url}${link}"
  status=$(curl -o /dev/null -s -w "%{http_code}" --connect-timeout $timeout "$full_link")
  if [[ $status != 200 ]]; then
    broken_links+=("$full_link")
  fi
done

if [[ ${#broken_links[@]} -gt 0 ]]; then
  echo "Broken links found:"
  printf '%s\n' "${broken_links[@]}"
  exit 1
fi