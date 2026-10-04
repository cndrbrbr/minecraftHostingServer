#!/bin/sh
# Copies the SSH keys and the SMTP password (mounted read-only from the host,
# readable only by root there) to private directories of the unprivileged app
# user, then drops root.
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
# Same for the SMTP password (host file is root-only, mode 600)
rm -rf /run/app-secrets && mkdir -p /run/app-secrets
if [ -n "${SMTP_PASSWORD_FILE:-}" ] && [ -f "$SMTP_PASSWORD_FILE" ]; then
    cp "$SMTP_PASSWORD_FILE" /run/app-secrets/smtp_password
fi
chown -R app:app /run/keys /run/app-secrets /data
chmod -R go-rwx /run/keys /run/app-secrets
[ -f /run/app-secrets/smtp_password ] && export SMTP_PASSWORD_FILE=/run/app-secrets/smtp_password
cd /app
exec env HOME=/home/app setpriv --reuid=app --regid=app --init-groups \
    uvicorn app.main:get_app --factory --host 0.0.0.0 --port 8000 \
    --proxy-headers --forwarded-allow-ips='*' --no-server-header
