#!/bin/bash
# setup-keys.sh — Generate SSH key pairs for all 5 Minecraft servers
# and write them into .env so docker-compose can inject them.
#
# Run once before first "docker compose up":
#   chmod +x setup-keys.sh && ./setup-keys.sh
#
# Distribute to students:
#   keys/mc1/sftp_key   → FileZilla private key  (student 1)
#   keys/mc1/ctrl_key   → PuTTY private key       (student 1)
#   ... repeat for mc2–mc5

set -e

mkdir -p keys

# Start fresh .env (keep any existing non-key lines if present)
> .env

for i in 1 2 3 4 5; do
    dir="keys/mc${i}"
    mkdir -p "$dir"

    # SFTP key (FileZilla)
    if [ ! -f "${dir}/sftp_key" ]; then
        ssh-keygen -t ed25519 -f "${dir}/sftp_key" -N '' -C "mc${i}-sftp" -q
        echo "Generated SFTP key for mc${i}"
    fi

    # Control key (PuTTY — start server)
    if [ ! -f "${dir}/ctrl_key" ]; then
        ssh-keygen -t ed25519 -f "${dir}/ctrl_key" -N '' -C "mc${i}-ctrl" -q
        echo "Generated control key for mc${i}"
    fi

    # Append to .env (public key content, one line each)
    echo "MC${i}_SFTP_PUBKEY=$(cat "${dir}/sftp_key.pub")" >> .env
    echo "MC${i}_CTRL_PUBKEY=$(cat "${dir}/ctrl_key.pub")" >> .env
done

# Protect private keys
chmod 600 keys/mc*/sftp_key keys/mc*/ctrl_key

echo ""
echo "Done. Keys written to keys/mc{1-5}/"
echo ".env has been populated with all public keys."
echo ""
echo "Student handout summary:"
echo "  Server  | MC port | SSH port | Files"
for i in 1 2 3 4 5; do
    MC_PORT=$((25564 + i))
    SSH_PORT=$((2220 + i))
    echo "  mc${i}     | ${MC_PORT}   | ${SSH_PORT}      | keys/mc${i}/sftp_key  keys/mc${i}/ctrl_key"
done
echo ""
echo "To convert keys for PuTTY/WinSCP use: puttygen keys/mc1/ctrl_key -o keys/mc1/ctrl_key.ppk"
