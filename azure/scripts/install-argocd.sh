#!/usr/bin/env bash
set -euo pipefail

argocd_version="${ARGOCD_VERSION:-v3.5.3}"

if [[ ! "${argocd_version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ARGOCD_VERSION must be an exact release tag such as v3.5.3" >&2
  exit 1
fi

manifest_url="https://raw.githubusercontent.com/argoproj/argo-cd/${argocd_version}/manifests/install.yaml"

k3s kubectl create namespace argocd --dry-run=client -o yaml \
  | k3s kubectl apply -f -
k3s kubectl apply --server-side --force-conflicts \
  --namespace argocd \
  --filename "${manifest_url}"

k3s kubectl wait \
  --namespace argocd \
  --for=condition=Available \
  deployment \
  --all \
  --timeout=10m
k3s kubectl rollout status \
  --namespace argocd \
  statefulset/argocd-application-controller \
  --timeout=10m

k3s kubectl get pods --namespace argocd --output wide
