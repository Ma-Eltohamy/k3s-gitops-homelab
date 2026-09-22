#!/usr/bin/env bash
# Install Argo CD, set the admin password, and bootstrap the app-of-apps.
# MACHINENAME comes from bootstrap.sh (it's also the kube context name)
# set -euo pipefail

is_rfc1123() { [[ "$1" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; }

[[ -z "$MACHINENAME" ]] && fail "MACHINENAME is not set"

command -v htpasswd >/dev/null 2>&1 || fail "htpasswd is not installed (install apache2-utils)"

# Ask for all required info oncce, so the process doesn't stop at middle
read -rsp "Enter desired initial Argo CD password: " ARGOCD_PASSWORD
echo
[[ -z "$ARGOCD_PASSWORD" ]] && fail "Password cannot be empty"

read -rp "Argo CD AppProject name (must match 'project:' in your repo's apps) (default: k3s-homelab-project): " APP_PROJECT_NAME
APP_PROJECT_NAME="${APP_PROJECT_NAME:-k3s-homelab-project}"
is_rfc1123 "$APP_PROJECT_NAME" || fail "Invalid project name '$APP_PROJECT_NAME': lowercase letters, digits and '-' only"

read -rp "Enter repo name (default: k3s-gitops-homelab): " REPO_NAME
REPO_NAME="${REPO_NAME:-k3s-gitops-homelab}"
is_rfc1123 "$REPO_NAME" || fail "Invalid repo name: must be a lowercase RFC 1123 label"

read -rp "Enter repo URL: " REPO_URL
[[ -z "$REPO_URL" ]] && fail "Repo URL cannot be empty"

echo "-------------------------------------"
echo "[=] Installing Argo CD"
echo "-------------------------------------"

# Only create the namespace if it doesn't exist, so re-running the script works
if ! $KUBECTL get namespace argocd >/dev/null 2>&1; then
  $KUBECTL create namespace argocd || fail "Could not create argocd namespace"
fi
echo "[=] argocd namespace ready."

$KUBECTL apply -n argocd --server-side \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  || fail "Could not apply Argo CD manifests"
echo "[=] Argo CD manifests applied."

$KUBECTL -n argocd patch configmap argocd-cmd-params-cm \
  --type merge -p '{"data": {"server.insecure": "true"}}' \
  || fail "Could not set server.insecure"

$KUBECTL -n argocd rollout restart deploy/argocd-server \
  || fail "Could not restart argocd-server"

$KUBECTL -n argocd rollout status deploy/argocd-server --timeout=5m \
  || fail "argocd-server did not become ready in time"
echo "[=] argocd-server running in insecure HTTP mode."

echo "-------------------------------------"
echo "[=] Setting admin password"
echo "-------------------------------------"

HASH=$(htpasswd -nbBC 10 "" "$ARGOCD_PASSWORD" | tr -d ':\n' | sed 's/$2y/$2a/') \
  || fail "Could not hash the password"
[[ -z "$HASH" ]] && fail "Password hash is empty"

$KUBECTL -n argocd patch secret argocd-secret \
  -p "{\"stringData\": {\"admin.password\": \"$HASH\", \"admin.passwordMtime\": \"$(date -u +%FT%TZ)\"}}" \
  || fail "Could not set admin password"
echo "[=] Admin password set."

echo "-------------------------------------"
echo "[=] Creating AppProject, repo, and app-of-apps"
echo "-------------------------------------"

$KUBECTL apply -f - <<EOF || fail "Could not apply AppProject"
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: "${APP_PROJECT_NAME}"
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  description: k3s-homelab
  sourceRepos:
    - "*"
  destinations:
    - namespace: "*"
      server: "*"
  clusterResourceWhitelist:
    - group: "*"
      kind: "*"
EOF
echo "[=] AppProject ${APP_PROJECT_NAME} applied."

$KUBECTL apply -f - <<EOF || fail "Could not apply repository secret"
apiVersion: v1
kind: Secret
metadata:
  name: "${REPO_NAME}"
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: "${REPO_URL}"
  project: "${APP_PROJECT_NAME}"
EOF
echo "[=] Repository ${REPO_NAME} registered."

$KUBECTL apply -f - <<EOF || fail "Could not apply app-of-apps Application"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: "${APP_PROJECT_NAME}-app-of-apps"
  namespace: argocd
spec:
  project: "${APP_PROJECT_NAME}"
  source:
    repoURL: "${REPO_URL}"
    targetRevision: main
    path: kubernetes/argocd-applications
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
EOF

echo "-------------------------------------"
echo "[=] Argo CD bootstrap applied for project ${APP_PROJECT_NAME}."
echo "-------------------------------------"
