#!/usr/bin/env bash
set -euo pipefail

install -d -m 0755 /usr/local/sbin

cat >/usr/local/sbin/azure-self-deallocate <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

metadata_root="http://169.254.169.254/metadata"

resource_id="$(${CURL:-curl} \
  --noproxy "*" \
  --fail \
  --silent \
  --show-error \
  --connect-timeout 2 \
  --max-time 10 \
  --header "Metadata: true" \
  "${metadata_root}/instance/compute/resourceId?api-version=2021-02-01&format=text")"

access_token="$(${CURL:-curl} \
  --noproxy "*" \
  --fail \
  --silent \
  --show-error \
  --connect-timeout 2 \
  --max-time 10 \
  --header "Metadata: true" \
  "${metadata_root}/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F" \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["access_token"])')"

test -n "${resource_id}"
test -n "${access_token}"

logger --tag azure-self-deallocate "Requesting Azure deallocation for ${resource_id}"

curl \
  --fail-with-body \
  --silent \
  --show-error \
  --max-time 30 \
  --request POST \
  --header "Authorization: Bearer ${access_token}" \
  --header "Content-Length: 0" \
  "https://management.azure.com${resource_id}/deallocate?api-version=2024-07-01"
SCRIPT

chmod 0750 /usr/local/sbin/azure-self-deallocate
chown root:root /usr/local/sbin/azure-self-deallocate

cat >/etc/systemd/system/azure-self-deallocate.service <<'UNIT'
[Unit]
Description=Deallocate this Azure VM to stop compute billing
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/azure-self-deallocate
Restart=on-failure
RestartSec=5min
TimeoutStartSec=2min
UNIT

cat >/etc/systemd/system/azure-self-deallocate.timer <<'UNIT'
[Unit]
Description=Azure VM cost-control deallocation guard

[Timer]
# Count from timer activation instead of the original OS boot time. This avoids
# an immediate deallocation when the guard is first installed on a VM that has
# already been running for more than three hours.
OnActiveSec=3h
OnCalendar=*-*-* 01:00:00 Asia/Ho_Chi_Minh
AccuracySec=1min
Persistent=false
Unit=azure-self-deallocate.service

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now azure-self-deallocate.timer
systemctl --no-pager status azure-self-deallocate.timer
