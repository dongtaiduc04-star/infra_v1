#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${GHCR_USERNAME:?GHCR_USERNAME protected parameter is required}"
: "${GHCR_TOKEN:?GHCR_TOKEN protected parameter is required}"

ghcr_username="${GHCR_USERNAME}"
ghcr_token="${GHCR_TOKEN}"
unset GHCR_USERNAME GHCR_TOKEN

namespace="getlink-dtd"
secret_name="ghcr-pull-secret"

cleanup() {
  unset ghcr_username ghcr_token
}
trap cleanup EXIT

k3s kubectl create namespace "${namespace}" --dry-run=client -o yaml \
  | k3s kubectl apply -f -

render_secret() {
  GHCR_USERNAME="${ghcr_username}" GHCR_TOKEN="${ghcr_token}" python3 - <<'PY'
import base64
import json
import os
import sys

username = os.environ["GHCR_USERNAME"]
token = os.environ["GHCR_TOKEN"]
auth = base64.b64encode(f"{username}:{token}".encode("utf-8")).decode("ascii")

docker_config = json.dumps(
    {"auths": {"ghcr.io": {"auth": auth}}},
    separators=(",", ":"),
).encode("utf-8")

manifest = {
    "apiVersion": "v1",
    "kind": "Secret",
    "metadata": {
        "name": "ghcr-pull-secret",
        "namespace": "getlink-dtd",
    },
    "type": "kubernetes.io/dockerconfigjson",
    "data": {
        ".dockerconfigjson": base64.b64encode(docker_config).decode("ascii"),
    },
}

json.dump(manifest, sys.stdout, separators=(",", ":"))
PY
}

render_secret \
  | k3s kubectl apply \
      --server-side \
      --force-conflicts \
      --field-manager=getlink-ghcr-bootstrap \
      --filename=- >/dev/null

echo "Configured private GHCR pull credentials in ${namespace}/${secret_name}."
