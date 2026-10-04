#!/bin/bash
# fetch-catalog.sh — Download every plugin jar listed in plugin-catalog.json
# into /plugin-catalog/files/<id>/<variant>/ at image build time, so servers
# can install plugins without internet access.
#
# Usage (Dockerfile): /fetch-catalog.sh <catalog.json> <build-context-dir>
set -euo pipefail

CATALOG="$1"
CONTEXT="$2"
DEST=/plugin-catalog

mkdir -p "$DEST/files"
cp "$CATALOG" "$DEST/catalog.json"

jq -r '.plugins[] | .id as $id | .variants | to_entries[] | [$id, .key, .value] | @tsv' "$CATALOG" |
while IFS=$'\t' read -r id key src; do
    dir_key="$key"; [ "$key" = "*" ] && dir_key="any"
    dir="$DEST/files/$id/$dir_key"
    mkdir -p "$dir"
    case "$src" in
        file:*)
            cp "$CONTEXT/${src#file:}" "$dir/"
            ;;
        *)
            echo "==> $id ($key): $src"
            curl -fsSL -o "$dir/$(basename "$src")" "$src"
            ;;
    esac
    # Every variant must contain exactly one jar with a plugin.yml
    jar=$(ls "$dir"/*.jar)
    # (some plugin.yml files start with a UTF-8 BOM and use CRLF line ends)
    unzip -p "$jar" plugin.yml | sed '1s/^\xEF\xBB\xBF//' | tr -d '\r' | grep -q '^name:' \
        || { echo "ERROR: $jar has no plugin.yml"; exit 1; }
done
