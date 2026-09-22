#!/usr/bin/bash

set -euo pipefail # to print any curl/tar/sudo command failed to run the error message
# asked once here, exported so every script below just uses them
fail() {
  echo "[!] $1" >&2
  exit 1
}

export -f fail

read -p "Username: " USERNAME
read -sp "Password: " USERPASSWORD; echo
read -p "Local IP: " LOCAL_IP

export USERNAME USERPASSWORD LOCAL_IP

# ./01-SetupSSH.sh
./02-InstallTailscale.sh || fail "Step 02 failed"

read -p "Machine name: " MACHINENAME
read -p "Tailscale IP: " MACHINEIP
read -p "Tailscale FQDN: " TAILSCALE_FQDN

export MACHINENAME MACHINEIP TAILSCALE_FQDN

./03-InstallK3S.sh || fail "Step 03 failed"
KUBECTL="kubectl --context $MACHINENAME"
export KUBECTL
./04-InstallSealedSecrets.sh || fail "Step 04 failed"
./05-InstallArgoCD.sh || fail "Step 05 failed"
./06-InstallPiHole.sh || fail "Step 06 failed"
