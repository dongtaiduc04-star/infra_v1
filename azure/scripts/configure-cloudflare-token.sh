#!/usr/bin/env bash
set -euo pipefail

: "${TUNNEL_TOKEN:?TUNNEL_TOKEN protected parameter is required}"

namespace="cloudflare-tunnel"

k3s kubectl create namespace "${namespace}" --dry-run=client -o yaml \
  | k3s kubectl apply -f -
k3s kubectl create secret generic tunnel-token \
  --namespace "${namespace}" \
  --from-literal=token="${TUNNEL_TOKEN}" \
  --dry-run=client \
  --output=yaml \
  | k3s kubectl apply -f -

echo "Configured ${namespace}/tunnel-token. Token value was not printed."
