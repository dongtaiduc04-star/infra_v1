[CmdletBinding()]
param()

# Read-only source checks. This script NEVER activates a Terraform controller,
# initializes a backend, reads state/tfvars, queries Azure, or runs kubectl.
$ErrorActionPreference = 'Stop'
$AzureRoot = Split-Path $PSScriptRoot -Parent

function Read-SourceText {
    param([string]$RelativePath)
    $SourcePath = Join-Path $AzureRoot $RelativePath
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Required source file is missing: $RelativePath"
    }
    return [IO.File]::ReadAllText($SourcePath).Replace("`r`n", "`n").TrimEnd("`r", "`n") + "`n"
}

function Assert-Source {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$Preparation = (Read-SourceText 'shared-control.preparation.json') | ConvertFrom-Json
Assert-Source ($Preparation.schemaVersion -eq 1) 'Unsupported preparation schema.'
Assert-Source ($Preparation.activationEnabled -ceq $false) 'Preparation must remain inactive; this checker cannot authorize activation.'
Assert-Source ($null -eq $Preparation.selectedController) 'Controller selection must remain unset pending owner review.'
Assert-Source (($Preparation.allowedControllers -join ',') -ceq 'infra,infra_v1') 'Only the existing infra and infra_v1 controllers are allowed.'
Assert-Source ($Preparation.canonicalAzureRootCommit -ceq '6352ee7a2a309425badb76b4c6bf99480a06d532') 'Canonical Azure source baseline changed; review required.'
Assert-Source ($Preparation.subscriptionId -ceq '529b5eb6-35b8-4998-a690-d34b60f28ca7') 'Unexpected Azure subscription.'
Assert-Source ($Preparation.resourceGroup -ceq 'rg-getlink-dtd-portfolio-mw') 'A separate/new resource group is not permitted.'
Assert-Source ($Preparation.appVm -ceq 'vm-getlink-dtd-portfolio') 'A separate/new application VM is not permitted.'
Assert-Source ($Preparation.sonarVm -ceq 'vm-getlink-dtd-portfolio-sonarqube') 'A separate/new SonarQube VM is not permitted.'
Assert-Source ($Preparation.appHostname -ceq 'getlink-azure.dongtaiduc.me') 'Unexpected application hostname.'
Assert-Source ($Preparation.sonarHostname -ceq 'sonar-azure.dongtaiduc.me') 'Unexpected SonarQube hostname.'
Assert-Source ($Preparation.existingStateVerified -ceq $false) 'Local checks must not claim live state verification.'
Assert-Source ($Preparation.liveArgoVerified -ceq $false) 'Local checks must not claim live Argo verification.'

$ExpectedBackend = @{
    resource_group_name = 'rg-getlink-tfstate'
    storage_account_name = 'stgetlinktf498374'
    container_name = 'tfstate'
    key = 'azure-k3s.tfstate'
}
$BackendText = Read-SourceText 'backend.tf'
Assert-Source ([regex]::Matches($BackendText, 'backend\s+"azurerm"').Count -eq 1) 'Expected exactly one Azure backend.'
foreach ($BackendField in $ExpectedBackend.Keys) {
    $FieldPattern = '(?m)^\s*' + [regex]::Escape($BackendField) + '\s*=\s*"([^"]+)"\s*$'
    $FieldMatches = [regex]::Matches($BackendText, $FieldPattern)
    Assert-Source ($FieldMatches.Count -eq 1) "Missing or duplicate backend field: $BackendField"
    Assert-Source ($FieldMatches[0].Groups[1].Value -ceq $ExpectedBackend[$BackendField]) "Different/fresh state backend rejected: $BackendField"
    Assert-Source ($Preparation.backend.$BackendField -ceq $ExpectedBackend[$BackendField]) "Backend record mismatch: $BackendField"
}
foreach ($AuthField in @('use_azuread_auth', 'use_cli')) {
    Assert-Source ([regex]::Matches($BackendText, "(?m)^\s*$AuthField\s*=\s*true\s*$").Count -eq 1) "Expected Azure AD/CLI backend authentication: $AuthField"
    Assert-Source ($Preparation.backend.$AuthField -ceq $true) "Backend authentication record mismatch: $AuthField"
}
Assert-Source ($BackendText -notmatch '(?m)^\s*(access_key|sas_token|client_secret)\s*=') 'Backend credentials must not be committed.'

$ExpectedParityPaths = @(
    'main.tf', 'outputs.tf', 'providers.tf', 'versions.tf', 'variables.tf',
    'terraform.tfvars.example', 'cloud-init.yaml.tftpl', 'sonarqube-cloud-init.yaml',
    'scripts/bootstrap-sonarqube.sh', 'scripts/configure-self-deallocate.sh',
    'scripts/install-argocd.sh', 'scripts/create-app-secrets.sh',
    'scripts/configure-ghcr-pull-secret.sh', 'scripts/configure-cloudflare-token.sh',
    'scripts/configure-sonarqube-admin-password.sh',
    'scripts/configure-sonarqube-cloudflare-token.sh', 'kubernetes/cloudflared.yaml'
)
$RecordedPaths = @($Preparation.canonicalTextSha256.PSObject.Properties.Name)
Assert-Source ((($RecordedPaths | Sort-Object) -join ',') -ceq (($ExpectedParityPaths | Sort-Object) -join ',')) 'Canonical source coverage changed.'
foreach ($RelativePath in $ExpectedParityPaths) {
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $ActualHash = ([BitConverter]::ToString($Hasher.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes((Read-SourceText $RelativePath))
        ))).Replace('-', '').ToLowerInvariant()
    }
    finally { $Hasher.Dispose() }
    Assert-Source ($ActualHash -ceq $Preparation.canonicalTextSha256.$RelativePath) "Original resource/bootstrap semantics changed: $RelativePath"
}

$LockText = Read-SourceText '.terraform.lock.hcl'
Assert-Source ($LockText -match 'version\s*=\s*"4\.81\.0"') 'AzureRM must remain at the reviewed 4.81.0 version.'
Assert-Source ([regex]::Matches($LockText, '"h1:').Count -ge 2) 'Retain the reviewed Windows and Linux provider hashes.'
$ProjectText = Read-SourceText 'kubernetes/argocd-project.yaml'
$ProjectUrls = @([regex]::Matches($ProjectText, '(?m)^\s*-\s+(https://github\.com/[^\s]+)\s*$') | ForEach-Object { $_.Groups[1].Value })
Assert-Source (
    $ProjectUrls.Count -eq 2 -and
    $ProjectUrls -ccontains 'https://github.com/dongtaiduc04-star/helm.git' -and
    $ProjectUrls -ccontains 'https://github.com/dongtaiduc04-star/helm_v1.git'
) 'AppProject must allow only the two existing Helm sources.'
$ApplicationText = Read-SourceText 'kubernetes/argocd-application.yaml'
Assert-Source ($ApplicationText -match '(?m)^\s+repoURL:\s+https://github.com/dongtaiduc04-star/helm_v1\.git\s*$') 'Prepared Application must select helm_v1 only.'
Assert-Source ([regex]::Matches($ApplicationText, '(?m)^\s+namespace:\s+getlink-dtd\s*$').Count -eq 1) 'Keep the existing GetLink destination namespace.'
foreach ($Flag in @('enabled', 'prune', 'selfHeal')) {
    Assert-Source ([regex]::Matches($ApplicationText, "(?m)^\s+$Flag" + ':\s+false\s*$').Count -eq 1) "Source-switch preparation must keep automatic synchronization disabled: $Flag"
}
Write-Host 'SHARED INFRASTRUCTURE PREPARATION PASSED: original resource/bootstrap semantics, exact backend identifiers, reviewed cross-platform lock, one manual-sync Application.'
Write-Host 'INACTIVE: no controller selected or activated; live Argo and existing state have not been verified. No network, backend/state, Azure or Kubernetes operation was performed.'
