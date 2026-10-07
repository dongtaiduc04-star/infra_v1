#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_USERNAME:?GITHUB_USERNAME protected parameter is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN protected parameter is required}"

# Optional private-repository registration; public helm_v1 needs no Git token.
namespace="argocd"
secret_name="getlink-dtd-helm-repo"
repo_url="${HELM_REPO_URL:?HELM_REPO_URL must explicitly name your private deployment repository}"

k3s kubectl create secret generic "${secret_name}" \
  --namespace "${namespace}" \
  --from-literal=type=git \
  --from-literal=url="${repo_url}" \
  --from-literal=username="${GITHUB_USERNAME}" \
  --from-literal=password="${GITHUB_TOKEN}" \
  --dry-run=client \
  --output=yaml \
  | k3s kubectl apply -f -

k3s kubectl label secret "${secret_name}" \
  --namespace "${namespace}" \
  argocd.argoproj.io/secret-type=repository \
  --overwrite

echo "Configured private Argo CD repository ${repo_url}."
