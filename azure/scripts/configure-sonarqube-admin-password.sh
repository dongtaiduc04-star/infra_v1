#!/usr/bin/env bash
set -euo pipefail

: "${SONAR_ADMIN_PASSWORD:?SONAR_ADMIN_PASSWORD protected parameter is required}"

if [[ ${#SONAR_ADMIN_PASSWORD} -lt 16 || "${SONAR_ADMIN_PASSWORD}" =~ [[:space:]] ]]; then
  echo "SONAR_ADMIN_PASSWORD must contain at least 16 non-whitespace characters." >&2
  exit 1
fi

sonarqube_url=http://127.0.0.1:9000
temporary_directory="$(mktemp -d)"
response_file="${temporary_directory}/response"
curl_config="${temporary_directory}/curl-config"

cleanup() {
  rm -rf "${temporary_directory}"
}
trap cleanup EXIT

for attempt in $(seq 1 60); do
  if curl --fail --silent --max-time 5 \
    "${sonarqube_url}/api/system/status" \
    | grep -q '"status":"UP"'; then
    break
  fi

  if [[ ${attempt} -eq 60 ]]; then
    echo "SonarQube is not ready; the administrator password was not changed." >&2
    exit 1
  fi

  sleep 5
done

# First make the operation safely repeatable. Keep the new credential out of
# the process list by placing only its Basic-auth representation in a root-only
# temporary curl config file.
new_auth="$(printf 'admin:%s' "${SONAR_ADMIN_PASSWORD}" | base64 --wrap=0)"
umask 077
printf 'header = "Authorization: Basic %s"\n' "${new_auth}" >"${curl_config}"
unset new_auth

if curl --config "${curl_config}" \
  --fail --silent --show-error --max-time 10 \
  "${sonarqube_url}/api/authentication/validate" \
  | grep -q '"valid":true'; then
  echo "The SonarQube administrator password is already configured."
  exit 0
fi

# Ensure the factory credential is still valid. If it is not, fail without
# attempting to overwrite an administrator password chosen by another user.
if ! curl --user admin:admin \
  --fail --silent --show-error --max-time 10 \
  "${sonarqube_url}/api/authentication/validate" \
  | grep -q '"valid":true'; then
  echo "The factory administrator password is no longer active and the supplied password did not authenticate. No change was made." >&2
  exit 1
fi

# Read the protected password from stdin so it does not appear in curl's
# command line. SonarQube expects form-encoded POST parameters for this API.
http_code="$({
  printf '%s' "${SONAR_ADMIN_PASSWORD}"
} | curl --user admin:admin \
  --silent --show-error --max-time 30 \
  --request POST \
  --data 'login=admin' \
  --data 'previousPassword=admin' \
  --data-urlencode 'password@-' \
  --output "${response_file}" \
  --write-out '%{http_code}' \
  "${sonarqube_url}/api/users/change_password")"

if [[ "${http_code}" != "200" && "${http_code}" != "204" ]]; then
  echo "SonarQube rejected the administrator password change with HTTP ${http_code}." >&2
  sed -E 's/(password|token|secret)[^,}]*/\1=[REDACTED]/gi' "${response_file}" >&2 || true
  exit 1
fi

if ! curl --config "${curl_config}" \
  --fail --silent --show-error --max-time 10 \
  "${sonarqube_url}/api/authentication/validate" \
  | grep -q '"valid":true'; then
  echo "SonarQube accepted the change, but validation with the new password failed." >&2
  exit 1
fi

echo "Changed the SonarQube administrator password; the value was not stored or printed."
