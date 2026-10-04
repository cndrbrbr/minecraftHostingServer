#!/bin/bash
# setup-keys.sh — replaced by setup.sh, which generates the SSH keys for all
# configured servers (keeping existing ones) as part of the setup.
# Kept so existing instructions keep working.
exec "$(dirname "$0")/setup.sh" "$@"
