#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
curl --fail --silent --show-error --location --proto '=https' --max-time 90 https://codeload.github.com/mhvvvvv/sillytavern-personal-console/tar.gz/refs/heads/main -o "$tmp/src.tgz"
tar -xzf "$tmp/src.tgz" -C "$tmp" --strip-components=1
sh "$tmp/install-vps.sh" "$@"
