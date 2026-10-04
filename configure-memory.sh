#!/bin/bash
# configure-memory.sh — replaced by setup.sh, which also sets the number of
# servers and the admin page. Kept so existing instructions keep working.
exec "$(dirname "$0")/setup.sh" "$@"
