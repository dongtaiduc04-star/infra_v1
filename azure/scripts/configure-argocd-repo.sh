#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_USERNAME:?GITHUB_USERNAME protected parameter is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN protected parameter is required}"

namespace="argocd"
secret_name="getlink-dtd-helm-repo"
repo_url="https://github.com/dongtaiduc04-star/helm.git"

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
