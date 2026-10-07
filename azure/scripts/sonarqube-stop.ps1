[CmdletBinding()]
param(
    [string]$ResourceGroup = "rg-getlink-dtd-example-mw",
    [string]$VmName = "vm-getlink-dtd-example-sonarqube"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) is not installed or is not on PATH."
}

Write-Host "Deallocating $VmName to stop compute billing..."
az vm deallocate `
    --resource-group $ResourceGroup `
    --name $VmName `
    --only-show-errors `
    --output none

if ($LASTEXITCODE -ne 0) {
    throw "Azure could not deallocate $VmName."
}

$PowerState = az vm get-instance-view `
    --resource-group $ResourceGroup `
    --name $VmName `
    --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus | [0]" `
    --output tsv

if ($LASTEXITCODE -ne 0) {
    throw "The deallocate request completed, but Azure power state could not be read."
}

Write-Host "${VmName}: $PowerState"
