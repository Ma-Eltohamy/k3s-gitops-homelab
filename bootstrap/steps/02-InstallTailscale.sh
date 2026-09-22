#!/usr/bin/env bash
# SSH into the server with a sudo-capable user to install Tailscale.
# LOCAL_IP, USERNAME, USERPASSWORD come from bootstrap.sh

# ---- Check required variables ----
[[ -z "$USERNAME" ]]       && fail "USERNAME is not set"
[[ -z "$USERPASSWORD" ]]   && fail "USERPASSWORD is not set"
[[ -z "$LOCAL_IP" ]]    && fail "LOCAL_IP is not set"

if sshpass -p "$USERPASSWORD" ssh -o StrictHostKeyChecking=no -tt "$USERNAME@$LOCAL_IP" "
set -e

echo '====================================='
echo '[+] Installing curl...'
echo '$USERPASSWORD' | sudo -S -p '' apt update
echo '$USERPASSWORD' | sudo -S -p '' apt install -y curl
echo '====================================='

echo '[+] Installing Tailscale...'
curl -fsSL https://tailscale.com/install.sh | sh

echo '[+] Starting and enabling Tailscale service...'
echo '$USERPASSWORD' | sudo -S -p '' systemctl enable --now tailscaled

echo '----------------------------------------'
echo '[+] Tailscale installed successfully!'
echo '[+] Opening login prompt...'
echo '----------------------------------------'

echo '$USERPASSWORD' | sudo -S -p '' tailscale up
"
then
  echo "Installing Tailscale done successfully."
else
  echo "Failed to install Tailscale." >&2
  exit 1
fi
