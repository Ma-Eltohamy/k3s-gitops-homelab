#!/usr/bin/env bash
# Install the Sealed Secrets controller + kubeseal CLI, and optionally restore an old key.
# MACHINENAME comes from bootstrap.sh (it's also the kube context name, set in 03-InstallK3S.sh)
# set -euo pipefail # to print any curl/tar/sudo command failed to run the error message

[[ -z "$MACHINENAME" ]] && fail "MACHINENAME is not set"

echo "-------------------------------------"
echo "[=] Fetching latest Sealed Secrets version"
echo "-------------------------------------"

VERSION=$(curl -fsSL https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest \
  | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/') \
  || fail "Could not reach GitHub API (network issue or rate limit)"

# Make sure we got a real version like 0.27.1, not garbage
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "Unexpected version value: '$VERSION'"

echo "Latest sealed-secrets version: $VERSION"

echo "-------------------------------------"
echo "[=] Installing Sealed Secrets controller"
echo "-------------------------------------"

$KUBECTL apply -f "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${VERSION}/controller.yaml" \
  || fail "Could not apply controller.yaml"

$KUBECTL rollout status deployment sealed-secrets-controller -n kube-system --timeout=180s \
  || fail "Controller did not become ready in time"

echo "[=] Sealed Secrets controller is running."

echo "-------------------------------------"
echo "[=] Installing kubeseal CLI"
echo "-------------------------------------"

TMP=$(mktemp -d)

curl -fsSL -o "$TMP/kubeseal.tar.gz" \
  "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${VERSION}/kubeseal-${VERSION}-linux-amd64.tar.gz" \
  || fail "Could not download kubeseal"

tar -xzf "$TMP/kubeseal.tar.gz" -C "$TMP" kubeseal || fail "Could not extract kubeseal"
sudo install -m 755 "$TMP/kubeseal" /usr/local/bin/kubeseal || fail "Could not install kubeseal"

rm -rf "$TMP"

kubeseal --version || fail "kubeseal installed but won't run"

echo "-------------------------------------"
echo "[=] Restore existing Sealed Secrets key"
echo "-------------------------------------"

read -r -p "Do you want to restore/import a Sealed Secrets key? [default: yes] (yes/no): " adminAnswer

if [[ -z "$adminAnswer" ]]; then
  adminAnswer="yes"
fi

case "$adminAnswer" in
  yes|y)
    echo "Current path is: $(pwd)"
    read -r -p "Enter the full path of the key backup file: " sealed_secrets_path

    [[ -f "$sealed_secrets_path" ]] || fail "File not found: $sealed_secrets_path"

    $KUBECTL apply -f "$sealed_secrets_path" \
      || fail "Could not apply the key file"

    $KUBECTL rollout restart deployment sealed-secrets-controller -n kube-system \
      || fail "Could not restart the controller"

    $KUBECTL rollout status deployment sealed-secrets-controller -n kube-system --timeout=180s \
      || fail "Controller did not come back after restart"

    echo "[=] Sealed Secrets key restored successfully."
    ;;
  no|n)
    echo "[=] Skipping restore. The controller will use a newly generated key."
    echo "    Remember to back it up, or you won't be able to decrypt your secrets later."
    ;;
  *)
    fail "Invalid answer: '$adminAnswer' (expected yes or no)"
    ;;
esac

echo "-------------------------------------"
echo "[=] Sealed Secrets setup completed."
echo "-------------------------------------"
