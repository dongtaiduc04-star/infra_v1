[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$StartScript = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts/sonarqube-start.ps1"
$Passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

# Extract the actual guest script so the tests cannot drift from production.
$ParseTokens = $null
$ParseErrors = $null
$StartAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $StartScript, [ref]$ParseTokens, [ref]$ParseErrors
)
Assert-True ($ParseErrors.Count -eq 0) "The start helper has PowerShell syntax errors."
$RemoteAssignment = $StartAst.Find({
    param($Node)
    $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $Node.Left.Extent.Text -eq '$RemoteCheck'
}, $true)
Assert-True ($null -ne $RemoteAssignment) "The guest check was not found."
$RemoteLiteral = $RemoteAssignment.Right.Find({
    param($Node)
    $Node -is [System.Management.Automation.Language.StringConstantExpressionAst]
}, $true)
$RemoteCheck = $RemoteLiteral.Value

if ($env:OS -eq "Windows_NT") {
    $GitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    $BashCandidates = @()
    if ($GitCommand) {
        $GitDirectory = Split-Path (Split-Path $GitCommand.Source -Parent) -Parent
        $BashCandidates += Join-Path $GitDirectory "bin/bash.exe"
    }
    if ($env:ProgramFiles) {
        $BashCandidates += Join-Path $env:ProgramFiles "Git/bin/bash.exe"
    }
    $BashPath = $BashCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
else {
    $BashCommand = Get-Command bash -ErrorAction SilentlyContinue
    $BashPath = if ($BashCommand) { $BashCommand.Source } else { $null }
}
Assert-True (-not [string]::IsNullOrWhiteSpace($BashPath)) "Install Git for Windows Bash (or Bash on Linux) to run these offline tests."

# No guest processes, network requests or real delays are used. Advancing the
# Bash clock in sleep also exercises the real 120-second readiness deadline.
$BashFixture = @'
exec 2>&1
export PATH="/usr/bin:/bin:$PATH"
SONAR_CASE='__CASE__'
sudo() {
  case "$1" in
    /usr/local/sbin/getlink-sonarqube-up)
      if [[ "$SONAR_CASE" == compose_start_fails ]]; then
        echo "fixture: Compose startup failed" >&2
        return 17
      fi
      return 0
      ;;
    /usr/local/sbin/getlink-sonarqube-status)
      if [[ "$SONAR_CASE" == tunnel_never_ready ]] ||
         { [[ "$SONAR_CASE" == tunnel_reset_then_ready ]] && (( SECONDS < 5 )); }; then
        echo "curl: (56) Recv failure: Connection reset by peer" >&2
        return 56
      fi
      echo 'SonarQube status: UP; Cloudflare Tunnel ready'
      return 0
      ;;
    docker)
      echo "fixture: container status"
      return 0
      ;;
    *) echo "Unexpected sudo command: $1" >&2; return 99 ;;
  esac
}
curl() {
  if [[ "$SONAR_CASE" == sonar_never_ready ]]; then
    return 22
  fi
  echo '{"status":"UP"}'
}
timeout() {
  [[ "$1" == --kill-after=5s ]] || return 99
  shift
  [[ "$1" == *s ]] || return 99
  shift
  "$@"
}
sleep() {
  SECONDS=$((SECONDS + $1))
}
SECONDS=0
'@

$BashCases = @(
    @{ Name = "immediately_ready"; Exit = 0; Text = "Cloudflare Tunnel ready" },
    @{ Name = "tunnel_reset_then_ready"; Exit = 0; Text = "Cloudflare Tunnel ready" },
    @{ Name = "tunnel_never_ready"; Exit = 1; Text = "within 120 seconds" },
    @{ Name = "sonar_never_ready"; Exit = 1; Text = "did not report UP" },
    @{ Name = "compose_start_fails"; Exit = 17; Text = "Compose startup failed" }
)
foreach ($Case in $BashCases) {
    $BashTestScript = ($BashFixture.Replace("__CASE__", $Case.Name) + "`n" + $RemoteCheck).Replace("`r`n", "`n")
    $BashOutput = @($BashTestScript | & $BashPath --noprofile --norc -s)
    $BashExitCode = $LASTEXITCODE
    $BashText = $BashOutput -join "`n"
    Assert-True ($BashExitCode -eq $Case.Exit) "$($Case.Name): unexpected exit code $BashExitCode. $BashText"
    Assert-True ($BashText.Contains($Case.Text)) "$($Case.Name): expected diagnostic output was missing."
    $HasMarker = $BashText -match '(?m)^GETLINK_SONARQUBE_INTERNAL_HEALTH_OK\r?$'
    Assert-True ($HasMarker -eq ($Case.Exit -eq 0)) "$($Case.Name): incorrect guest success marker."
    if ($Case.Name -eq "tunnel_never_ready") {
        Assert-True ($BashText.Contains("Connection reset by peer")) "The final tunnel error was not retained."
    }
    $Passed++
    Write-Host "PASS guest: $($Case.Name)"
}

# These script-scoped functions shadow the native programs only for this test
# and the child start helper. They never invoke Azure or the public endpoint.
function az {
    $State = $global:SonarStartTestState
    $Operation = @($args[0], $args[1]) -join " "
    [void]$State.AzureCalls.Add($Operation)
    Assert-True (($args -join " ").Contains("vm-getlink-dtd-example-sonarqube")) "A command targeted a VM other than the dedicated SonarQube VM."
    switch ($Operation) {
        "vm start" {
            $global:LASTEXITCODE = $State.CurrentCase.StartExit
        }
        "vm run-command" {
            Assert-True ($args -contains "value[].message") "All Run Command messages must be requested."
            $global:LASTEXITCODE = $State.CurrentCase.RunExit
            $State.CurrentCase.RunMessages
        }
        "vm deallocate" {
            $State.OutputBeforeCleanup = $State.CapturedOutput -join "`n"
            $global:LASTEXITCODE = $State.CurrentCase.DeallocateExit
        }
        default { throw "Unexpected Azure operation: $Operation" }
    }
}

function curl.exe {
    $State = $global:SonarStartTestState
    $State.PublicCalls++
    if (
        $State.CurrentCase.PublicReady -or
        ($State.CurrentCase.ContainsKey("PublicReadyAfter") -and
            $State.PublicCalls -gt $State.CurrentCase.PublicReadyAfter)
    ) {
        $global:LASTEXITCODE = 0
        '{"status":"UP"}'
    }
    else {
        $global:LASTEXITCODE = 22
        "fixture: public endpoint unavailable"
    }
}

# Inject the delay into the child script instead of replacing Start-Sleep.
$MockPublicRetryDelay = {
    param([int]$Seconds)
    $global:SonarStartTestState.SleepCalls++
    [void]$global:SonarStartTestState.SleepSeconds.Add($Seconds)
}

$HostCases = @(
    @{ Name = "healthy"; StartExit = 0; RunExit = 0; RunMessages = @("fixture: guest stdout", "GETLINK_SONARQUBE_INTERNAL_HEALTH_OK"); PublicReady = $true; DeallocateExit = 0; Cleanup = 0; PublicCalls = 1; SleepCalls = 0; Error = "" },
    @{ Name = "public_retry_then_ready"; StartExit = 0; RunExit = 0; RunMessages = @("GETLINK_SONARQUBE_INTERNAL_HEALTH_OK"); PublicReady = $false; PublicReadyAfter = 2; DeallocateExit = 0; Cleanup = 0; PublicCalls = 3; SleepCalls = 2; Error = "" },
    @{ Name = "missing_marker"; StartExit = 0; RunExit = 0; RunMessages = @("fixture: guest stdout", "fixture: guest stderr"); PublicReady = $true; DeallocateExit = 0; Cleanup = 1; PublicCalls = 0; SleepCalls = 0; Error = "stack/tunnel health verification failed" },
    @{ Name = "cli_failure_despite_marker"; StartExit = 0; RunExit = 9; RunMessages = @("fixture: guest stdout", "GETLINK_SONARQUBE_INTERNAL_HEALTH_OK"); PublicReady = $true; DeallocateExit = 0; Cleanup = 1; PublicCalls = 0; SleepCalls = 0; Error = "stack/tunnel health verification failed" },
    @{ Name = "public_failure"; StartExit = 0; RunExit = 0; RunMessages = @("GETLINK_SONARQUBE_INTERNAL_HEALTH_OK"); PublicReady = $false; DeallocateExit = 0; Cleanup = 1; PublicCalls = 12; SleepCalls = 12; Error = "public SonarQube API check failed" },
    @{ Name = "cleanup_failure"; StartExit = 0; RunExit = 0; RunMessages = @("fixture: guest stderr"); PublicReady = $true; DeallocateExit = 7; Cleanup = 1; PublicCalls = 0; SleepCalls = 0; Error = "automatic deallocation also failed" },
    @{ Name = "vm_start_failure"; StartExit = 3; RunExit = 0; RunMessages = @("GETLINK_SONARQUBE_INTERNAL_HEALTH_OK"); PublicReady = $true; DeallocateExit = 0; Cleanup = 0; PublicCalls = 0; SleepCalls = 0; Error = "Azure could not start" }
)
try {
foreach ($Case in $HostCases) {
    # A uniquely named shared state avoids PowerShell's dynamic script-scope
    # resolution when mocks are called by a different .ps1 file.
    $State = @{
        CurrentCase = $Case
        AzureCalls = New-Object 'System.Collections.Generic.List[string]'
        CapturedOutput = New-Object 'System.Collections.Generic.List[string]'
        OutputBeforeCleanup = ""
        PublicCalls = 0
        SleepCalls = 0
        SleepSeconds = New-Object 'System.Collections.Generic.List[int]'
    }
    $global:SonarStartTestState = $State
    $CaughtError = ""
    try {
        & $StartScript -PublicRetryDelay $MockPublicRetryDelay *>&1 | ForEach-Object { [void]$global:SonarStartTestState.CapturedOutput.Add($_.ToString()) }
    }
    catch {
        $CaughtError = $_.Exception.Message + "`n" + $_.ScriptStackTrace
    }
    $CleanupCalls = @($State.AzureCalls | Where-Object { $_ -eq "vm deallocate" }).Count
    Assert-True ($CleanupCalls -eq $Case.Cleanup) "$($Case.Name): incorrect deallocation count. $CaughtError"
    Assert-True ($State.PublicCalls -eq $Case.PublicCalls) "$($Case.Name): incorrect public check count. $CaughtError"
    Assert-True ($State.SleepCalls -eq $Case.SleepCalls) "$($Case.Name): incorrect retry delay count. $CaughtError"
    foreach ($DelaySeconds in $State.SleepSeconds) {
        Assert-True ($DelaySeconds -eq 5) "$($Case.Name): the public retry delay must remain five seconds."
    }
    if ($Case.Error) {
        Assert-True ($CaughtError.Contains($Case.Error)) "$($Case.Name): unexpected error: $CaughtError"
    }
    else {
        Assert-True ([string]::IsNullOrWhiteSpace($CaughtError)) "$($Case.Name): unexpected error: $CaughtError"
        Assert-True (($State.CapturedOutput -join "`n").Contains("Public SonarQube API is UP")) "The healthy case did not confirm the public API."
    }
    if ($Case.Name -eq "missing_marker") {
        Assert-True ($State.OutputBeforeCleanup.Contains("fixture: guest stdout")) "Guest stdout was not printed before cleanup."
        Assert-True ($State.OutputBeforeCleanup.Contains("fixture: guest stderr")) "Guest stderr was not printed before cleanup."
    }
    if ($Case.Name -eq "vm_start_failure") {
        Assert-True ($State.AzureCalls.Count -eq 1) "Health checks ran after a failed VM start."
    }
    $Passed++
    Write-Host "PASS host: $($Case.Name)"
}
}
finally {
    Remove-Variable -Name SonarStartTestState -Scope Global -ErrorAction SilentlyContinue
}

$global:LASTEXITCODE = 0
Write-Host "$Passed offline tests passed. No Azure resources were contacted."
