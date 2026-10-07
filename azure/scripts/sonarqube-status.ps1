[CmdletBinding()]
param(
    [string]$ResourceGroup = "rg-getlink-dtd-example-mw",
    [string]$VmName = "vm-getlink-dtd-example-sonarqube",
    [string]$PublicUrl = "https://sonar.example.com"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) is not installed or is not on PATH."
}

$PowerStateCode = az vm get-instance-view `
    --resource-group $ResourceGroup `
    --name $VmName `
    --query "instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]" `
    --output tsv

if ($LASTEXITCODE -ne 0) {
    throw "Azure power state could not be read for $VmName."
}

Write-Host "${VmName}: $PowerStateCode"

if ($PowerStateCode -eq "PowerState/deallocated") {
    Write-Host "SonarQube health checks were skipped because the VM is not running."
    return
}

if ($PowerStateCode -eq "PowerState/stopped") {
    throw "$VmName is stopped but not deallocated, so Azure compute billing may continue. Run .\scripts\sonarqube-stop.ps1."
}

if ($PowerStateCode -ne "PowerState/running") {
    throw "Unexpected Azure power state for ${VmName}: $PowerStateCode"
}

$RemoteCheck = @'
set -euo pipefail
sudo /usr/local/sbin/getlink-sonarqube-status
echo
echo "GETLINK_SONARQUBE_STATUS_OK"
'@
$RemoteCheckB64 = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($RemoteCheck)
)
$RemoteLauncher = "printf '%s' '$RemoteCheckB64' | base64 -d | bash"

$Message = az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name $VmName `
    --command-id RunShellScript `
    --scripts $RemoteLauncher `
    --query "value[0].message" `
    --output tsv

if (
    $LASTEXITCODE -ne 0 -or
    (($Message -join "`n") -notmatch '(?m)^GETLINK_SONARQUBE_STATUS_OK\r?$')
) {
    throw "Azure Run Command could not read the SonarQube stack status."
}

$Message

$PublicStatusUrl = "$($PublicUrl.TrimEnd('/'))/api/system/status"
$PublicStatus = curl.exe -sS --fail --max-time 30 $PublicStatusUrl
if (
    $LASTEXITCODE -eq 0 -and
    (($PublicStatus -join "`n") -match '"status"\s*:\s*"UP"')
) {
    Write-Host "Public SonarQube API is UP: $PublicStatusUrl"
}
else {
    throw "The internal stack is running, but the public SonarQube status API is not UP: $PublicStatusUrl"
}
