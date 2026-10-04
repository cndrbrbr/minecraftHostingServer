#!/bin/bash
# mc-plugins.sh — Plugin management for the managed Spigot layout.
# Called via sudo by mc-dispatch.sh, and by entrypoint.sh before every start.
#
#   mc-plugins.sh list             installed plugin jars (JSON)
#   mc-plugins.sh catalog          catalog entries for this server's version (JSON)
#   mc-plugins.sh install <id>     install a catalog plugin (and what it requires)
#   mc-plugins.sh remove <file>    remove an installed plugin jar
#   mc-plugins.sh sync <version>   entrypoint: install defaults/locked plugins and
#                                  switch catalog plugins to the jar for <version>
#
# Which catalog plugin was installed as which file is tracked in
# /server/.catalog-state.json. That file is writable by the student over SFTP,
# so everything read from it is validated before use.
set -uo pipefail

CATALOG=/plugin-catalog/catalog.json
FILES=/plugin-catalog/files
PLUGINS=/server/data/plugins
STATE=/server/.catalog-state.json
DEFAULTS_DONE=/server/.catalog-defaults-done
JAR_RE='^[A-Za-z0-9][A-Za-z0-9._+-]*\.jar$'
ID_RE='^[a-z0-9][a-z0-9-]*$'

die() { echo "ERROR: $*"; exit 1; }

if [ "$(cat /server/.servertype 2>/dev/null)" = "custom" ]; then
    die "this server runs custom software — manage plugins via SFTP."
fi

mkdir -p "$PLUGINS"
exec 9>/server/.mc-plugins.lock
flock 9

# ── helpers ───────────────────────────────────────────────────
server_version() {
    local v=""
    [ -f /server/.version ] && v=$(tr -d '[:space:]' < /server/.version)
    [ -z "$v" ] && [ -f /server/.default-version ] && v=$(tr -d '[:space:]' < /server/.default-version)
    echo "${v:-26.3}"
}

state() {
    # Valid JSON object or {} — never trust the file blindly
    jq -c 'if type == "object" then . else {} end' "$STATE" 2>/dev/null || echo '{}'
}

save_state() {
    echo "$1" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    chown mc-sftp:mc-sftp "$STATE" 2>/dev/null || true
}

in_catalog() { jq -e --arg id "$1" '.plugins[] | select(.id == $id)' "$CATALOG" >/dev/null; }
field() { jq -r --arg id "$1" --arg f "$2" '.plugins[] | select(.id == $id) | .[$f] // empty | if type == "array" then .[] else . end' "$CATALOG"; }

# Variant key for <id> on <version>: highest key <= version, else "*", else
# empty (also when <version> is above the plugin's "max")
variant_for() {
    local id="$1" version="$2" best="" max
    max=$(field "$id" max)
    if [ -n "$max" ] && [ "$max" != "$version" ] && \
       [ "$(printf '%s\n%s\n' "$max" "$version" | sort -V | tail -n1)" = "$version" ]; then
        return 0
    fi
    while read -r key; do
        [ "$key" = "*" ] && continue
        if [ "$(printf '%s\n%s\n' "$key" "$version" | sort -V | head -n1)" = "$key" ]; then
            best="$key"
        fi
    done < <(jq -r --arg id "$id" '.plugins[] | select(.id == $id) | .variants | keys[]' "$CATALOG" | sort -V)
    if [ -z "$best" ] && jq -e --arg id "$id" '.plugins[] | select(.id == $id) | .variants["*"]' "$CATALOG" >/dev/null; then
        best="*"
    fi
    echo "$best"
}

variant_jar() {  # path of the jar for <id> <variant>
    local dir="$2"; [ "$dir" = "*" ] && dir="any"
    ls "$FILES/$1/$dir"/*.jar 2>/dev/null | head -n1
}

plugin_yml_field() {  # <jar> <field>
    # strip a UTF-8 BOM and CRLF line ends (both occur in real plugins)
    unzip -p "$1" plugin.yml 2>/dev/null | sed '1s/^\xEF\xBB\xBF//' | tr -d '\r' | grep -m1 "^$2:" | sed -E "s/^$2:[[:space:]]*//; s/^['\"]//; s/['\"][[:space:]]*\$//; s/[[:space:]]+\$//"
}

# Install catalog plugin <id> for <version>; prints what it did.
# Returns non-zero (with an ERROR line) instead of exiting, so a single
# unavailable plugin never blocks the server start in 'sync'.
do_install() {
    local id="$1" version="$2" st variant src file old
    in_catalog "$id" || { echo "ERROR: unknown plugin '$id'."; return 1; }
    for dep in $(field "$id" requires); do
        [[ "$dep" =~ $ID_RE ]] || continue
        do_install "$dep" "$version" || return 1
    done
    variant=$(variant_for "$id" "$version")
    [ -n "$variant" ] || { echo "ERROR: $(field "$id" name) is not available for Minecraft $version."; return 1; }
    src=$(variant_jar "$id" "$variant")
    [ -n "$src" ] || { echo "ERROR: jar for $id ($variant) missing in image."; return 1; }
    file=$(basename "$src")

    st=$(state)
    old=$(echo "$st" | jq -r --arg id "$id" '.[$id].file // empty')
    if [ "$old" = "$file" ] && [ -f "$PLUGINS/$file" ]; then
        echo "==> $(field "$id" name) is already installed."
        return 0
    fi
    # Remove the previously tracked file and foreign copies of this plugin
    if [[ "$old" =~ $JAR_RE ]]; then rm -f "$PLUGINS/$old"; fi
    for glob in $(field "$id" replaces); do
        for f in "$PLUGINS"/$glob; do [ -f "$f" ] && rm -f "$f"; done
    done
    cp "$src" "$PLUGINS/$file"
    chown mc-sftp:mc-sftp "$PLUGINS/$file"
    st=$(echo "$st" | jq -c --arg id "$id" --arg v "$variant" --arg f "$file" '.[$id] = {variant: $v, file: $f}')
    save_state "$st"
    echo "==> Installed $(field "$id" name) ($file)."
}

# ── commands ──────────────────────────────────────────────────
cmd="${1:-}"
case "$cmd" in
    list)
        st=$(state)
        {
            for f in "$PLUGINS"/*.jar; do
                [ -f "$f" ] || continue
                b=$(basename "$f")
                id=$(echo "$st" | jq -r --arg f "$b" 'to_entries[] | select(.value.file == $f) | .key' | head -n1)
                locked=false
                [ -n "$id" ] && [ "$(field "$id" locked)" = "true" ] && locked=true
                jq -n -c --arg file "$b" --arg name "$(plugin_yml_field "$f" name)" \
                    --arg version "$(plugin_yml_field "$f" version)" --arg id "$id" --argjson locked "$locked" \
                    '{file: $file, name: (if $name == "" then $file else $name end), version: $version, catalog_id: $id, locked: $locked}'
            done
        } | jq -s -c '.'
        ;;

    catalog)
        version=$(server_version)
        st=$(state)
        jq -r '.plugins[].id' "$CATALOG" | while read -r id; do
            variant=$(variant_for "$id" "$version")
            installed=false
            f=$(echo "$st" | jq -r --arg id "$id" '.[$id].file // empty')
            [[ "$f" =~ $JAR_RE ]] && [ -f "$PLUGINS/$f" ] && installed=true
            jq -c --arg id "$id" --argjson installed "$installed" --argjson available "$([ -n "$variant" ] && echo true || echo false)" \
                '.plugins[] | select(.id == $id) | {id, name, description, locked: (.locked // false), requires: (.requires // []),
                  category: (.category // "Weitere"), status: (.status // "verified"), max: (.max // ""),
                  installed: $installed, available: $available}' "$CATALOG"
        done | jq -s -c --arg v "$version" '{version: $v, plugins: .}'
        ;;

    install)
        id="${2:-}"
        [[ "$id" =~ $ID_RE ]] || die "invalid plugin id."
        do_install "$id" "$(server_version)" || exit 1
        echo "==> Restart the server to activate it."
        ;;

    remove)
        file="${2:-}"
        [[ "$file" =~ $JAR_RE ]] || die "invalid file name."
        [ -f "$PLUGINS/$file" ] || die "plugin '$file' is not installed."
        st=$(state)
        id=$(echo "$st" | jq -r --arg f "$file" 'to_entries[] | select(.value.file == $f) | .key' | head -n1)
        if [ -n "$id" ]; then
            [ "$(field "$id" locked)" = "true" ] && die "$(field "$id" name) is required and cannot be removed."
            # Refuse if another installed catalog plugin requires this one
            for other in $(echo "$st" | jq -r 'keys[]'); do
                [[ "$other" =~ $ID_RE ]] || continue
                [ "$other" = "$id" ] && continue
                if field "$other" requires | grep -qx "$id"; then
                    die "$(field "$other" name) needs $(field "$id" name) — remove $(field "$other" name) first."
                fi
            done
            st=$(echo "$st" | jq -c --arg id "$id" 'del(.[$id])')
            save_state "$st"
        fi
        rm -f "$PLUGINS/$file"
        echo "==> Removed $file. Restart the server to unload it."
        ;;

    sync)
        version="${2:-$(server_version)}"
        # Fresh server: install the default plugins once (students may remove them later)
        if [ ! -f "$DEFAULTS_DONE" ]; then
            for id in $(jq -r '.plugins[] | select(.default == true) | .id' "$CATALOG"); do
                do_install "$id" "$version" || true
            done
            touch "$DEFAULTS_DONE"
        fi
        # Locked plugins are always present
        for id in $(jq -r '.plugins[] | select(.locked == true) | .id' "$CATALOG"); do
            do_install "$id" "$version" >/dev/null || true
        done
        # Installed catalog plugins follow the server version
        st=$(state)
        for id in $(echo "$st" | jq -r 'keys[]'); do
            [[ "$id" =~ $ID_RE ]] && in_catalog "$id" || continue
            want=$(variant_for "$id" "$version")
            have=$(echo "$st" | jq -r --arg id "$id" '.[$id].variant // empty')
            file=$(echo "$st" | jq -r --arg id "$id" '.[$id].file // empty')
            if [ -z "$want" ]; then
                if [[ "$file" =~ $JAR_RE ]] && [ -f "$PLUGINS/$file" ]; then
                    rm -f "$PLUGINS/$file"
                    echo "==> $(field "$id" name) has no build for Minecraft $version — disabled until the version changes."
                fi
                continue
            fi
            if [ "$want" != "$have" ] || ! { [[ "$file" =~ $JAR_RE ]] && [ -f "$PLUGINS/$file" ]; }; then
                do_install "$id" "$version" || true
            fi
        done
        # PrometheusExporter config (first run / after a wipe)
        if [ ! -f "$PLUGINS/PrometheusExporter/config.yml" ] && [ -f /server-base/prometheus-exporter-config.yml ]; then
            mkdir -p "$PLUGINS/PrometheusExporter"
            cp /server-base/prometheus-exporter-config.yml "$PLUGINS/PrometheusExporter/config.yml"
            chown -R mc-sftp:mc-sftp "$PLUGINS/PrometheusExporter"
        fi
        ;;

    *)
        echo "Usage: mc-plugins.sh list | catalog | install <id> | remove <file> | sync <version>"
        exit 1
        ;;
esac
