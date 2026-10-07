#!/usr/bin/env bash
set -euo pipefail

: "${SONARQUBE_IMAGE:?SONARQUBE_IMAGE is required}"
: "${POSTGRES_IMAGE:?POSTGRES_IMAGE is required}"
: "${CLOUDFLARED_IMAGE:?CLOUDFLARED_IMAGE is required}"

case "${SONARQUBE_IMAGE}" in
  sonarqube:*community) ;;
  *) echo "Refusing an unexpected SonarQube image." >&2; exit 1 ;;
esac

case "${POSTGRES_IMAGE}" in
  postgres:18.*-bookworm) ;;
  *) echo "Refusing an unexpected PostgreSQL image." >&2; exit 1 ;;
esac

case "${CLOUDFLARED_IMAGE}" in
  cloudflare/cloudflared:20??.*) ;;
  *) echo "Refusing an unexpected cloudflared image." >&2; exit 1 ;;
esac

cloud-init status --wait
systemctl enable --now docker.service

install -d -m 0755 /opt/getlink-sonarqube
install -d -m 0700 /etc/getlink-sonarqube/secrets

create_secret() {
  local destination="$1"
  local bytes="$2"

  if [[ ! -s "${destination}" ]]; then
    umask 077
    openssl rand -base64 "${bytes}" | tr -d '\n' >"${destination}"
  fi

  chown root:root "${destination}"
  chmod 0444 "${destination}"
}

create_secret /etc/getlink-sonarqube/secrets/postgres-password 48
create_secret /etc/getlink-sonarqube/secrets/sonar-auth-jwt-secret 32

# The remotely managed tunnel is intentionally dormant until its token is
# supplied through an Azure Managed Run Command protected parameter.
if [[ ! -e /etc/getlink-sonarqube/secrets/cloudflared-token ]]; then
  install -o root -g root -m 0444 /dev/null \
    /etc/getlink-sonarqube/secrets/cloudflared-token
fi

cat >/opt/getlink-sonarqube/sonarqube-entrypoint.sh <<'SCRIPT'
#!/bin/sh
set -eu

SONAR_JDBC_PASSWORD="$(cat /run/secrets/postgres_password)"
SONAR_AUTH_JWTBASE64HS256SECRET="$(cat /run/secrets/sonar_auth_jwt_secret)"
export SONAR_JDBC_PASSWORD SONAR_AUTH_JWTBASE64HS256SECRET

exec /opt/sonarqube/docker/entrypoint.sh "$@"
SCRIPT
chmod 0555 /opt/getlink-sonarqube/sonarqube-entrypoint.sh

cat >/opt/getlink-sonarqube/docker-compose.yaml <<COMPOSE
name: getlink-sonarqube

services:
  postgresql:
    image: ${POSTGRES_IMAGE}
    restart: unless-stopped
    shm_size: 256m
    environment:
      POSTGRES_DB: sonar
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
    secrets:
      - postgres_password
    volumes:
      - postgresql_data:/var/lib/postgresql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -d \$\${POSTGRES_DB} -U \$\${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 20s
    security_opt:
      - no-new-privileges:true
    mem_limit: 1536m
    networks:
      - sonarqube

  sonarqube:
    image: ${SONARQUBE_IMAGE}
    restart: unless-stopped
    read_only: true
    depends_on:
      postgresql:
        condition: service_healthy
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://postgresql:5432/sonar
      SONAR_JDBC_USERNAME: sonar
    entrypoint:
      - /usr/local/bin/sonarqube-with-secrets
    secrets:
      - postgres_password
      - sonar_auth_jwt_secret
    volumes:
      - sonarqube_data:/opt/sonarqube/data
      - sonarqube_extensions:/opt/sonarqube/extensions
      - sonarqube_logs:/opt/sonarqube/logs
      - sonarqube_temp:/opt/sonarqube/temp
      - type: bind
        source: /opt/getlink-sonarqube/sonarqube-entrypoint.sh
        target: /usr/local/bin/sonarqube-with-secrets
        read_only: true
    tmpfs:
      - /tmp:size=256M,mode=1777
    ports:
      - "127.0.0.1:9000:9000"
    healthcheck:
      test: ["CMD-SHELL", "curl --fail --silent http://localhost:9000/api/system/status | grep -Eq '\"status\":\"(UP|DB_MIGRATION_NEEDED|DB_MIGRATION_RUNNING)\"'"]
      interval: 15s
      timeout: 5s
      retries: 40
      start_period: 90s
    ulimits:
      nofile:
        soft: 131072
        hard: 131072
      nproc:
        soft: 8192
        hard: 8192
    security_opt:
      - no-new-privileges:true
    mem_limit: 5g
    networks:
      - sonarqube

  cloudflared:
    image: ${CLOUDFLARED_IMAGE}
    profiles:
      - tunnel
    restart: unless-stopped
    depends_on:
      sonarqube:
        condition: service_healthy
    command:
      - tunnel
      - --no-autoupdate
      - --metrics
      - 0.0.0.0:2000
      - run
      - --token-file
      - /run/secrets/cloudflared_token
    secrets:
      - cloudflared_token
    ports:
      - "127.0.0.1:2000:2000"
    security_opt:
      - no-new-privileges:true
    mem_limit: 256m
    networks:
      - sonarqube

secrets:
  postgres_password:
    file: /etc/getlink-sonarqube/secrets/postgres-password
  sonar_auth_jwt_secret:
    file: /etc/getlink-sonarqube/secrets/sonar-auth-jwt-secret
  cloudflared_token:
    file: /etc/getlink-sonarqube/secrets/cloudflared-token

volumes:
  postgresql_data:
  sonarqube_data:
  sonarqube_extensions:
  sonarqube_logs:
  sonarqube_temp:

networks:
  sonarqube:
    driver: bridge
    enable_ipv6: false
COMPOSE

cat >/usr/local/sbin/getlink-sonarqube-up <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

compose=(docker compose --project-directory /opt/getlink-sonarqube --file /opt/getlink-sonarqube/docker-compose.yaml)

if [[ -s /etc/getlink-sonarqube/secrets/cloudflared-token ]]; then
  "${compose[@]}" --profile tunnel up --detach --remove-orphans
else
  "${compose[@]}" up --detach --remove-orphans postgresql sonarqube
fi
SCRIPT
chmod 0750 /usr/local/sbin/getlink-sonarqube-up

cat >/usr/local/sbin/getlink-sonarqube-status <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

compose=(docker compose --project-directory /opt/getlink-sonarqube --file /opt/getlink-sonarqube/docker-compose.yaml)

echo "vm.max_map_count=$(sysctl -n vm.max_map_count)"
echo "fs.file-max=$(sysctl -n fs.file-max)"
"${compose[@]}" --profile tunnel ps

echo
echo "SonarQube system status:"
status_response="$(curl --fail --silent --show-error --max-time 10 \
  http://127.0.0.1:9000/api/system/status)"
printf '%s\n' "${status_response}"

if ! grep -q '"status":"UP"' <<<"${status_response}"; then
  echo "SonarQube is reachable but is not UP." >&2
  exit 1
fi
echo

if [[ -s /etc/getlink-sonarqube/secrets/cloudflared-token ]]; then
  echo
  echo "Cloudflare Tunnel readiness:"
  curl --fail --silent --show-error --max-time 10 \
    http://127.0.0.1:2000/ready
  echo
else
  echo
  echo "Cloudflare Tunnel token is not configured yet."
fi
SCRIPT
chmod 0750 /usr/local/sbin/getlink-sonarqube-status

cat >/etc/systemd/system/getlink-sonarqube.service <<'UNIT'
[Unit]
Description=Getlink SonarQube Community Build stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/getlink-sonarqube
ExecStart=/usr/local/sbin/getlink-sonarqube-up
ExecStop=/usr/bin/docker compose --project-directory /opt/getlink-sonarqube --file /opt/getlink-sonarqube/docker-compose.yaml --profile tunnel stop
TimeoutStartSec=15min
TimeoutStopSec=3min

[Install]
WantedBy=multi-user.target
UNIT

sysctl --system
docker compose --project-directory /opt/getlink-sonarqube \
  --file /opt/getlink-sonarqube/docker-compose.yaml \
  --profile tunnel config --quiet

systemctl daemon-reload
# Enabling an already-active Type=oneshot unit does not run ExecStart again.
# Always restart so an extension rerun reconciles changed Compose settings or
# pinned image versions instead of reporting success with stale containers.
systemctl enable getlink-sonarqube.service
systemctl restart getlink-sonarqube.service

for attempt in $(seq 1 60); do
  if curl --fail --silent --max-time 5 \
    http://127.0.0.1:9000/api/system/status \
    | grep -Eq '"status":"(UP|DB_MIGRATION_NEEDED|DB_MIGRATION_RUNNING)"'; then
    echo "SonarQube is ready."
    exit 0
  fi

  sleep 10
done

echo "SonarQube did not become ready before the bootstrap timeout." >&2
docker compose --project-directory /opt/getlink-sonarqube \
  --file /opt/getlink-sonarqube/docker-compose.yaml ps >&2
docker compose --project-directory /opt/getlink-sonarqube \
  --file /opt/getlink-sonarqube/docker-compose.yaml logs --tail 100 sonarqube >&2
exit 1
