#!/usr/bin/env bash
# Install k3s on the remote machine and merge its kubeconfig locally.
# $MACHINENAME is resolved by MagicDNS through the tailnet.
# USERNAME, USERPASSWORD, MACHINENAME, MACHINEIP, TAILSCALE_FQDN come from bootstrap.sh

# ---- Check required variables ----
[[ -z "$USERNAME" ]]       && fail "USERNAME is not set"
[[ -z "$USERPASSWORD" ]]   && fail "USERPASSWORD is not set"
[[ -z "$MACHINENAME" ]]    && fail "MACHINENAME is not set"
[[ -z "$MACHINEIP" ]]      && fail "MACHINEIP is not set"
[[ -z "$TAILSCALE_FQDN" ]] && fail "TAILSCALE_FQDN is not set"

echo "-------------------------------------"
echo "[=] Installing k3s & kubectl on $MACHINENAME"
echo "-------------------------------------"

sshpass -p "$USERPASSWORD" ssh -o StrictHostKeyChecking=no -tt "$USERNAME@$MACHINENAME" "
set -e
echo '$USERPASSWORD' | sudo -S -p '' -v
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--write-kubeconfig-mode 644 --tls-san $TAILSCALE_FQDN --tls-san $MACHINEIP' sh -
" || fail "k3s installation failed"

echo "-------------------------------------"
echo "[=] k3s has been installed successfully."
echo "-------------------------------------"

echo "-------------------------------------"
echo "[=] Fetching kubeconfig"
echo "-------------------------------------"

mkdir -p ~/.kube || fail "Could not create ~/.kube"

# Step 1: download the raw kubeconfig
sshpass -p "$USERPASSWORD" ssh -o StrictHostKeyChecking=no "$USERNAME@$MACHINENAME" \
  "cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/${MACHINENAME}.raw.yaml \
  || fail "Could not read kubeconfig from $MACHINENAME"

# Step 2: make sure it's not empty
[[ -s ~/.kube/${MACHINENAME}.raw.yaml ]] || fail "Downloaded kubeconfig is empty"

# Step 3: point it at the Tailscale name and rename 'default' entries
sed -e "s#https://127.0.0.1:6443#https://${TAILSCALE_FQDN}:6443#" \
    -e "s/default/${MACHINENAME}/g" \
    ~/.kube/${MACHINENAME}.raw.yaml > ~/.kube/${MACHINENAME}.yaml \
  || fail "Could not edit kubeconfig"

rm -f ~/.kube/${MACHINENAME}.raw.yaml
chmod 600 ~/.kube/${MACHINENAME}.yaml

echo "-------------------------------------"
echo "[=] Merging into ~/.kube/config"
echo "-------------------------------------"

# Back up the current config before touching it
if [[ -f ~/.kube/config ]]; then
  cp ~/.kube/config ~/.kube/config.bak || fail "Could not back up ~/.kube/config"
  KUBECONFIG=~/.kube/${MACHINENAME}.yaml:~/.kube/config \
    kubectl config view --flatten > ~/.kube/config.tmp \
    || fail "Could not merge kubeconfig (original is untouched)"
else
  cp ~/.kube/${MACHINENAME}.yaml ~/.kube/config.tmp || fail "Could not create ~/.kube/config"
fi

mv ~/.kube/config.tmp ~/.kube/config || fail "Could not replace ~/.kube/config"
chmod 600 ~/.kube/config

echo "-------------------------------------"
echo "[=] Verifying cluster access"
echo "-------------------------------------"

kubectl --context "$MACHINENAME" get nodes \
  || fail "Cluster not reachable. Your previous config is saved at ~/.kube/config.bak"

echo "-------------------------------------"
echo "[=] k3s is ready on $MACHINENAME"
echo "-------------------------------------"
