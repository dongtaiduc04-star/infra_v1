[CmdletBinding()]
param(
    [string]$ResourceGroup = "rg-getlink-dtd-example-mw",
    [string]$VmName = "vm-getlink-dtd-example-sonarqube",
    [string]$PublicUrl = "https://sonar.example.com",
    # Offline tests inject a delay without shadowing the built-in cmdlet.
    [ValidateNotNull()]
    [scriptblock]$PublicRetryDelay = {
        param([int]$Seconds)
        Microsoft.PowerShell.Utility\Start-Sleep -Seconds $Seconds
    }
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) is not installed or is not on PATH."
}

Write-Host "Starting $VmName..."
az vm start `
    --resource-group $ResourceGroup `
    --name $VmName `
    --only-show-errors `
    --output none

if ($LASTEXITCODE -ne 0) {
    throw "Azure could not start $VmName."
}

$RemoteCheck = @'
set -euo pipefail
sudo /usr/local/sbin/getlink-sonarqube-up
sonarqube_ready=false
for attempt in $(seq 1 90); do
  if curl --fail --silent --max-time 5 http://127.0.0.1:9000/api/system/status | grep -q '"status":"UP"'; then
    sonarqube_ready=true
    break
  fi
  if (( attempt < 90 )); then
    sleep 10
  fi
done

if [[ "${sonarqube_ready}" != true ]]; then
  echo "SonarQube did not report UP before the startup retry limit." >&2
  sudo docker compose --project-directory /opt/getlink-sonarqube --file /opt/getlink-sonarqube/docker-compose.yaml --profile tunnel ps || true
  exit 1
fi

# Compose can report cloudflared as started before its readiness endpoint is
# listening. Retry the full status helper, which checks both SonarQube and the
# configured tunnel, rather than treating the first connection reset as fatal.
stack_deadline=$((SECONDS + 120))
stack_status=""
while (( SECONDS < stack_deadline )); do
  remaining=$((stack_deadline - SECONDS))
  if stack_status=$(timeout --kill-after=5s "${remaining}s" sudo /usr/local/sbin/getlink-sonarqube-status 2>&1); then
    printf '%s\n' "${stack_status}"
    echo "GETLINK_SONARQUBE_INTERNAL_HEALTH_OK"
    exit 0
  fi

  remaining=$((stack_deadline - SECONDS))
  if (( remaining <= 0 )); then
    break
  elif (( remaining > 5 )); then
    sleep 5
  else
    sleep "${remaining}"
  fi
done

echo "SonarQube reported UP, but stack/tunnel readiness did not pass within 120 seconds." >&2
printf 'Last stack/tunnel check:\n%s\n' "${stack_status}" >&2
sudo docker compose --project-directory /opt/getlink-sonarqube --file /opt/getlink-sonarqube/docker-compose.yaml --profile tunnel ps || true
exit 1
'@
$RemoteCheckB64 = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($RemoteCheck.Replace("`r`n", "`n"))
)
$RemoteLauncher = "printf '%s' '$RemoteCheckB64' | base64 -d | bash"

$Message = az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name $VmName `
    --command-id RunShellScript `
    --scripts $RemoteLauncher `
    --query "value[].message" `
    --output tsv
$RunCommandExitCode = $LASTEXITCODE

# Azure can return exit code 0 even when the guest script failed. Print all
# returned stdout/stderr before cleanup, and still require the success marker.
if ($Message) {
    $Message
}

if (
    $RunCommandExitCode -ne 0 -or
    (($Message -join "`n") -notmatch '(?m)^GETLINK_SONARQUBE_INTERNAL_HEALTH_OK\r?$')
) {
    Write-Warning "The VM started, but the SonarQube stack/tunnel check failed (Azure CLI exit code: $RunCommandExitCode). See the output above. Deallocating it to avoid unattended compute cost."
    az vm deallocate `
        --resource-group $ResourceGroup `
        --name $VmName `
        --only-show-errors `
        --output none

    if ($LASTEXITCODE -ne 0) {
        throw "SonarQube health verification failed, and automatic deallocation also failed. Deallocate $VmName manually."
    }

    throw "SonarQube stack/tunnel health verification failed; $VmName was deallocated. Review the Run Command output above before retrying."
}

$PublicStatusUrl = "$($PublicUrl.TrimEnd('/'))/api/system/status"
$PublicReady = $false

for ($Attempt = 1; $Attempt -le 12; $Attempt++) {
    $PublicStatus = curl.exe -sS --fail --max-time 15 $PublicStatusUrl
    if (
        $LASTEXITCODE -eq 0 -and
        (($PublicStatus -join "`n") -match '"status"\s*:\s*"UP"')
    ) {
        $PublicReady = $true
        break
    }

    & $PublicRetryDelay 5
}

if ($PublicReady) {
    Write-Host "Public SonarQube API is UP: $PublicStatusUrl"
}
else {
    Write-Warning "SonarQube is healthy inside the VM, but its public status API is not UP. Deallocating the VM because the public endpoint is unavailable."
    az vm deallocate `
        --resource-group $ResourceGroup `
        --name $VmName `
        --only-show-errors `
        --output none

    if ($LASTEXITCODE -ne 0) {
        throw "The public endpoint check failed, and automatic deallocation also failed. Deallocate $VmName manually."
    }

    throw "The public SonarQube API check failed; $VmName was deallocated. Check the dedicated Cloudflare Tunnel route before starting it again."
}
