#!/bin/sh
# Copies the SSH keys (mounted read-only from the host, owned by the host
# user) to a private directory for the unprivileged app user, then drops root.
set -e
rm -rf /run/keys && mkdir -p /run/keys
for dir in /keys/mc*; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    mkdir -p "/run/keys/$name"
    for k in ctrl_key sftp_key; do
        [ -f "$dir/$k" ] && cp "$dir/$k" "/run/keys/$name/$k"
    done
done
chown -R app:app /run/keys /data
chmod -R go-rwx /run/keys
cd /app
exec setpriv --reuid=app --regid=app --init-groups \
    uvicorn app.main:get_app --factory --host 0.0.0.0 --port 8000 \
    --proxy-headers --forwarded-allow-ips='*' --no-server-header
