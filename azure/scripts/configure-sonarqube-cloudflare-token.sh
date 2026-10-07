#!/usr/bin/env bash
set -euo pipefail

: "${TUNNEL_TOKEN:?TUNNEL_TOKEN protected parameter is required}"

if [[ ${#TUNNEL_TOKEN} -lt 50 || "${TUNNEL_TOKEN}" =~ [[:space:]] ]]; then
  echo "TUNNEL_TOKEN is invalid or contains whitespace." >&2
  exit 1
fi

allow_factory_admin_with_ip_allowlist="${ALLOW_FACTORY_ADMIN_WITH_IP_ALLOWLIST:-false}"
if [[ "${allow_factory_admin_with_ip_allowlist}" != false &&
      "${allow_factory_admin_with_ip_allowlist}" != true ]]; then
  echo "ALLOW_FACTORY_ADMIN_WITH_IP_ALLOWLIST must be exactly true or false." >&2
  exit 1
fi

sonarqube_url=http://127.0.0.1:9000
secret_directory=/etc/getlink-sonarqube/secrets
secret_path="${secret_directory}/cloudflared-token"
temporary_path="${secret_directory}/.cloudflared-token.$$"
backup_path="${secret_directory}/.cloudflared-token.backup.$$"
compose=(
  docker compose
  --project-directory /opt/getlink-sonarqube
  --file /opt/getlink-sonarqube/docker-compose.yaml
  --profile tunnel
)

cleanup() {
  rm -f "${temporary_path}" "${backup_path}"
}
trap cleanup EXIT

# Never publish a fresh SonarQube installation with the factory credential.
# Require a conclusive authentication response before changing the tunnel.
factory_auth_response="$(curl --user admin:admin \
  --fail --silent --show-error --max-time 10 \
  "${sonarqube_url}/api/authentication/validate")" || {
  echo "Could not verify the SonarQube administrator credential; the tunnel was not changed." >&2
  exit 1
}

if grep -q '"valid":true' <<<"${factory_auth_response}"; then
  if [[ "${allow_factory_admin_with_ip_allowlist}" != true ]]; then
    echo "Refusing to publish SonarQube while the factory admin/admin credential is active." >&2
    exit 1
  fi

  echo "WARNING: Starting the tunnel with factory credentials because the operator explicitly confirmed an active Cloudflare IP allowlist." >&2
elif ! grep -q '"valid":false' <<<"${factory_auth_response}"; then
  echo "SonarQube returned an unexpected authentication response; the tunnel was not changed." >&2
  exit 1
fi
unset factory_auth_response

install -d -m 0700 "${secret_directory}"

had_previous_token=false
if [[ -s "${secret_path}" ]]; then
  cp --preserve=mode,ownership "${secret_path}" "${backup_path}"
  had_previous_token=true
fi

umask 077
printf '%s' "${TUNNEL_TOKEN}" >"${temporary_path}"
chown root:root "${temporary_path}"
chmod 0444 "${temporary_path}"
mv -f "${temporary_path}" "${secret_path}"

connector_started=true
if ! "${compose[@]}" up --detach --force-recreate --no-deps cloudflared; then
  echo "The cloudflared container could not be recreated with the new token; rolling back." >&2
  connector_started=false
fi

if [[ "${connector_started}" == true ]]; then
  for attempt in $(seq 1 30); do
    if curl --fail --silent --max-time 5 http://127.0.0.1:2000/ready >/dev/null; then
      rm -f "${backup_path}"
      echo "Configured the SonarQube Cloudflare Tunnel token; connector is ready."
      exit 0
    fi

    sleep 2
  done
fi

echo "The new Cloudflare Tunnel token did not become ready; rolling back." >&2
"${compose[@]}" logs --tail 50 cloudflared >&2 || true

if [[ "${had_previous_token}" == true ]]; then
  mv -f "${backup_path}" "${secret_path}"
  if ! "${compose[@]}" up --detach --force-recreate --no-deps cloudflared; then
    echo "The previous token was restored, but its connector could not be recreated." >&2
    exit 1
  fi

  rollback_ready=false
  for attempt in $(seq 1 30); do
    if curl --fail --silent --max-time 5 http://127.0.0.1:2000/ready >/dev/null; then
      rollback_ready=true
      break
    fi
    sleep 2
  done

  if [[ "${rollback_ready}" == true ]]; then
    echo "Restored the previous Cloudflare Tunnel token." >&2
  else
    echo "The previous token was restored, but its connector is not ready." >&2
  fi
else
  install -o root -g root -m 0444 /dev/null "${secret_path}"
  "${compose[@]}" stop cloudflared >/dev/null 2>&1 || true
  echo "Removed the failed initial token and stopped the tunnel connector." >&2
fi

exit 1
