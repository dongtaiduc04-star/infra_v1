#!/usr/bin/env bash
set -euo pipefail

namespace="getlink-dtd"
secret_name="getlink-dtd-secrets"

k3s kubectl create namespace "${namespace}" --dry-run=client -o yaml \
  | k3s kubectl apply -f -

if k3s kubectl get secret "${secret_name}" --namespace "${namespace}" >/dev/null 2>&1; then
  echo "Secret ${namespace}/${secret_name} already exists; leaving it unchanged."
  exit 0
fi

mysql_root_password="$(openssl rand -base64 36 | tr -d '\r\n')"
auth_db_password="$(openssl rand -base64 36 | tr -d '\r\n')"
link_db_password="$(openssl rand -base64 36 | tr -d '\r\n')"
jwt_secret="$(openssl rand -base64 48 | tr -d '\r\n')"

k3s kubectl create secret generic "${secret_name}" \
  --namespace "${namespace}" \
  --from-literal=mysql-root-password="${mysql_root_password}" \
  --from-literal=auth-db-password="${auth_db_password}" \
  --from-literal=link-db-password="${link_db_password}" \
  --from-literal=jwt-secret="${jwt_secret}"

unset mysql_root_password auth_db_password link_db_password jwt_secret
echo "Created ${namespace}/${secret_name}. Secret values were not printed."
