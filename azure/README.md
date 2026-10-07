# Azure k3s infrastructure

This directory is the only Terraform root in this Azure-only publication.
It is a source-only example, not the control repository for the owner's
running environment. No state or deployment identity is included.

## Safety rules

- Run Terraform with `terraform -chdir=azure ...` from the `infra_v1`
  directory, or run it while the current directory is `infra_v1/azure`.
- Never use `terraform init -migrate-state` or `terraform init -force-copy`.
- The parent repository directory is not a Terraform root.
- Authentication uses the signed-in Azure CLI identity and Azure AD access to
  the private `tfstate` container; no storage key is stored in this repository.

## Cost and access model

- The VM has no public IP and the NSG has no inbound Internet rules.
- Initial administration uses Azure VM Run Command. Web ingress will be added
  with Cloudflare Tunnel, which only needs outbound HTTPS.
- The subnet explicitly opts in to Azure default outbound access as a
  student/demo cost tradeoff. This is not the recommended production pattern.
- The 64 GiB Standard SSD continues to incur storage cost while the VM is
  deallocated. Always deallocate the VM after a demo to stop compute billing.
- Azure DevTest auto-shutdown cannot be attached here: the schedule must match
  the VM region, while that resource type is unavailable in Malaysia West.
- A systemd cost-control timer instead asks Azure to deallocate the VM after
  three hours of uptime or at 01:00 Vietnam time, whichever comes first. The
  VM uses a system-assigned identity with a custom role scoped to this VM and
  limited to VM read plus deallocate actions. Manual deallocation remains the
  safest action whenever a work session ends early.

## Local checks

From this directory:

```powershell
terraform fmt -check
terraform init -backend=false -input=false
terraform validate
# A real plan requires your own backend, identity, review and authorization.
```

Review the saved plan before any separately authorized apply. Never apply
`tfplan-destroy` or a plan made for a different backend or environment.

## Example GitOps path

The public app_v1 workflow only runs checks: it does not publish images or
update Helm values. For a separately authorized deployment, an operator must
build/publish their own images, configure the helm_v1 example values, create
secrets outside Git, and explicitly synchronize Argo CD. The Azure Application
example has automatic synchronization disabled.

Azure uses k3s local-path storage and Traefik behind an outbound Cloudflare
Tunnel. The tunnel container requests 64 MiB of ephemeral storage with a
256 MiB limit and a 128 MiB /tmp volume. These are initial demo budgets,
not an Azure disk resize; monitor storage and eviction before tuning them.

Public helm_v1 can be read without a Git credential. Private image pulls may
require a separate read-only registry token. If choosing a private Helm mirror,
configure HELM_REPO_URL explicitly and supply its read-only Git credential as
a protected parameter; never reuse a deployment/write token for readers.

## Bootstrap order

These are manual deployment references, not publication or CI steps. First
configure your own backend, image tags, domains and isolated target resources.
Only an authorized operator should then perform the following operations:

1. Start the VM and confirm the k3s node is `Ready`.
2. Run `scripts/install-argocd.sh` through Azure VM Run Command.
3. Run `scripts/create-app-secrets.sh`; it generates the MySQL and JWT values
   inside the VM and never prints them.
4. Run `scripts/configure-ghcr-pull-secret.sh` as a Managed Run Command with
   `GHCR_USERNAME` and `GHCR_TOKEN` supplied as protected parameters.
5. For a public Helm repository, no Git token is needed. For a private mirror,
   use `scripts/configure-argocd-repo.sh` with explicit `HELM_REPO_URL`,
   `GITHUB_USERNAME` and protected `GITHUB_TOKEN` parameters.
6. Apply `kubernetes/argocd-project.yaml`, followed by
   `kubernetes/argocd-application.yaml`.
7. Create a remotely managed Cloudflare Tunnel. Pass its token to
   `scripts/configure-cloudflare-token.sh` as a protected parameter, then apply
   `kubernetes/cloudflared.yaml`.
8. In Cloudflare, publish `getlink-azure.example.com` to
   `http://traefik.kube-system.svc.cluster.local:80`.
9. Verify the Argo CD application, all application pods, the ingress, and the
   public HTTPS endpoint. Deallocate the VM when the work session ends.

The committed Kubernetes manifests contain no credentials. Never paste a
GitHub or Cloudflare token into a normal `az vm run-command invoke --scripts`
call because ordinary script text can be retained in command history or Azure
operation metadata.

## Dedicated Azure SonarQube host

SonarQube is deliberately isolated from the single-node k3s workload VM. The
same resource group, VNet, and `snet-k3s` subnet are reused, but Terraform
creates a second `Standard_B2as_v2` VM with these properties:

- VM name: `vm-getlink-dtd-example-sonarqube`
- Private IP: `10.60.1.20`; no public IP and no inbound NSG rule
- 2 vCPU and 8 GiB RAM, the cost-controlled small-installation footprint
- 64 GiB Standard SSD OS disk; Docker named volumes persist across restarts and
  deallocation, but the disk continues to incur storage cost while stopped
- SonarQube Community Build `26.9.0.129388-community`
- PostgreSQL `18.6-bookworm`
- A dedicated `cloudflare/cloudflared:2026.9.3` connector
- The same three-hour/01:00 Vietnam self-deallocation guard used by k3s

The VM bootstraps Docker from Docker's official Ubuntu repository. A VM
extension creates the Compose stack, generates the PostgreSQL and SonarQube JWT
secrets inside the VM, and starts SonarQube. Those secret values never enter
Terraform configuration or state. The Compose services use persistent volumes,
health checks, a read-only SonarQube root filesystem, a writable `/tmp`, and the
Elasticsearch host limits required by current SonarQube Community Build.

Running PostgreSQL on this same VM is an explicit portfolio/cost exception.
Sonar recommends a separate database host for production. Do not treat this
single-VM topology as a highly available production design.

The current pinned image versions and host limits were selected from the
official SonarQube, PostgreSQL, Docker, Azure VM size, and Cloudflare Tunnel
documentation. Upgrade them deliberately: read the SonarQube update notes,
back up PostgreSQL, change the pinned Terraform variables, review the plan, and
only then apply.

### Deployment review (not performed by CI)

From `infra_v1/azure`:

```powershell
terraform fmt -check
terraform init -backend=false -input=false
terraform validate
# A real plan requires your own backend, identity, review and authorization.
```

A fresh deployment can create both k3s and SonarQube VMs. Review every resource,
its names, backend ownership and cost before any deployment. Never apply a plan
from this publication to the original running environment. No deployment is
performed by the public CI.

After creation, the internal health command is:

```powershell
az vm run-command invoke `
  --resource-group rg-getlink-dtd-example-mw `
  --name vm-getlink-dtd-example-sonarqube `
  --command-id RunShellScript `
  --scripts "sudo /usr/local/sbin/getlink-sonarqube-status" `
  --query "value[0].message" `
  --output tsv
```

### Replace the factory administrator password before publishing

The SonarQube container listens only on the VM loopback address at this point,
so replace the factory `admin` / `admin` credential **before** creating the
public Cloudflare route. The password is sent only as a Managed Run Command
protected parameter, is not printed, and is not stored by the script. Save it
in your password manager.

```powershell
$AdminSecure = Read-Host "Nhập mật khẩu quản trị SonarQube mới (ít nhất 16 ký tự, không có khoảng trắng)" -AsSecureString

try {
  $AdminPassword = [System.Net.NetworkCredential]::new(
    "",
    $AdminSecure
  ).Password

  if ($AdminPassword.Length -lt 16 -or $AdminPassword -match '\s') {
    throw "Mật khẩu phải có ít nhất 16 ký tự và không chứa khoảng trắng."
  }

  $null = az vm run-command create `
    --resource-group rg-getlink-dtd-example-mw `
    --vm-name vm-getlink-dtd-example-sonarqube `
    --run-command-name configure-sonarqube-admin-password `
    --location malaysiawest `
    --script "@.\scripts\configure-sonarqube-admin-password.sh" `
    --protected-parameters "SONAR_ADMIN_PASSWORD=$AdminPassword" `
    --async-execution false `
    --timeout-in-seconds 600 `
    --only-show-errors

  if ($LASTEXITCODE -ne 0) {
    throw "Không thể đổi mật khẩu quản trị SonarQube."
  }

  $AdminResultJson = az vm run-command show `
    --resource-group rg-getlink-dtd-example-mw `
    --vm-name vm-getlink-dtd-example-sonarqube `
    --run-command-name configure-sonarqube-admin-password `
    --instance-view `
    --query "instanceView.{executionState:executionState,exitCode:exitCode,output:output,error:error}" `
    --output json

  if ($LASTEXITCODE -ne 0) {
    throw "Không thể đọc kết quả đổi mật khẩu từ Azure."
  }

  $AdminResult = $AdminResultJson | ConvertFrom-Json
  if ($AdminResult.executionState -ne "Succeeded" -or $AdminResult.exitCode -ne 0) {
    throw "Script đổi mật khẩu trong VM thất bại: $($AdminResult.error)"
  }

  $AdminResult.output
}
finally {
  $AdminSecure.Dispose()
  Remove-Variable AdminPassword, AdminSecure, AdminResultJson, AdminResult `
    -ErrorAction SilentlyContinue
  [System.GC]::Collect()
}
```

Confirm `executionState: Succeeded`, `exitCode: 0`, then delete this Managed
Run Command exactly as for the tunnel command below. The script is idempotent
when rerun with the same password. If another password has already replaced
the factory credential, it stops without overwriting it.

### Configure the dedicated Cloudflare Tunnel safely

Create a new remotely managed tunnel for SonarQube. Do not reuse the k3s
tunnel. In Cloudflare, publish `sonar.example.com` to the Docker-network
service URL `http://sonarqube:9000`.

Run the following from `infra_v1/azure`. It prompts securely and does not read the
clipboard. The token is supplied to Azure only as a Managed Run Command
protected parameter:

```powershell
$TunnelSecure = Read-Host "Nhập token của Cloudflare Tunnel dành riêng cho SonarQube" -AsSecureString

try {
  $TunnelToken = [System.Net.NetworkCredential]::new(
    "",
    $TunnelSecure
  ).Password

  if (
    [string]::IsNullOrWhiteSpace($TunnelToken) -or
    $TunnelToken.Length -lt 50 -or
    $TunnelToken -match '\s'
  ) {
    throw "Tunnel token không hợp lệ hoặc bạn đã nhập cả lệnh Docker."
  }

  $null = az vm run-command create `
    --resource-group rg-getlink-dtd-example-mw `
    --vm-name vm-getlink-dtd-example-sonarqube `
    --run-command-name configure-sonarqube-cloudflare-token `
    --location malaysiawest `
    --script "@.\scripts\configure-sonarqube-cloudflare-token.sh" `
    --protected-parameters "TUNNEL_TOKEN=$TunnelToken" `
    --async-execution false `
    --timeout-in-seconds 600 `
    --only-show-errors

  if ($LASTEXITCODE -ne 0) {
    throw "Không thể cấu hình Cloudflare Tunnel cho SonarQube."
  }

  $TunnelResultJson = az vm run-command show `
    --resource-group rg-getlink-dtd-example-mw `
    --vm-name vm-getlink-dtd-example-sonarqube `
    --run-command-name configure-sonarqube-cloudflare-token `
    --instance-view `
    --query "instanceView.{executionState:executionState,exitCode:exitCode,output:output,error:error}" `
    --output json

  if ($LASTEXITCODE -ne 0) {
    throw "Không thể đọc kết quả cấu hình tunnel từ Azure."
  }

  $TunnelResult = $TunnelResultJson | ConvertFrom-Json
  if ($TunnelResult.executionState -ne "Succeeded" -or $TunnelResult.exitCode -ne 0) {
    throw "Script cấu hình tunnel trong VM thất bại: $($TunnelResult.error)"
  }

  $TunnelResult.output
}
finally {
  $TunnelSecure.Dispose()
  Remove-Variable TunnelToken, TunnelSecure, TunnelResultJson, TunnelResult `
    -ErrorAction SilentlyContinue
  [System.GC]::Collect()
}
```

If the SonarQube password API rejects the initial password change and the
password must instead be changed in the web UI, create and activate this
Cloudflare custom WAF rule **before** starting the connector:

```text
(http.host eq "sonar.example.com" and ip.src ne YOUR_PUBLIC_IP)
```

Use the `Block` action. After confirming that the rule is active, the first
tunnel bootstrap may add this second protected parameter:

```powershell
--protected-parameters `
  "TUNNEL_TOKEN=$TunnelToken" `
  "ALLOW_FACTORY_ADMIN_WITH_IP_ALLOWLIST=true"
```

This is an explicit one-time exception. Change the `admin` password
immediately through the IP-restricted hostname. Then rerun the tunnel command
with only `TUNNEL_TOKEN`; a successful run proves the factory `admin/admin`
credential is no longer valid. After that successful verification, remove or
review the temporary IP-only WAF rule for any separately authorized scanner
that needs access. These public repositories' checks-only CI does not contact
SonarQube.
Never use the override without the active, hostname-specific IP allowlist, and
update that rule first if the public IP changes during this recovery procedure.

Verify the result, then remove the Managed Run Command resource. Removing it
does not delete the token file inside the VM:

```powershell
az vm run-command show `
  --resource-group rg-getlink-dtd-example-mw `
  --vm-name vm-getlink-dtd-example-sonarqube `
  --run-command-name configure-sonarqube-cloudflare-token `
  --instance-view `
  --query "instanceView.{executionState:executionState,exitCode:exitCode,output:output,error:error}" `
  --output json

az vm run-command delete `
  --resource-group rg-getlink-dtd-example-mw `
  --vm-name vm-getlink-dtd-example-sonarqube `
  --run-command-name configure-sonarqube-cloudflare-token `
  --yes `
  --only-show-errors `
  --output none
```

The connector uses Cloudflare's token-file mechanism. Rotating the token and
rerunning the protected command force-recreates only the `cloudflared`
container so that the new token is actually loaded. By default, the command
refuses to start a public connector while the factory `admin` / `admin`
credential is active; only the explicit, IP-allowlisted recovery procedure
above bypasses that guard. If a rotated token cannot establish a healthy
connector, it restores the previous token and restarts the previous connector;
a failed first-time token leaves the connector stopped.

### Start, stop, and check quickly

From `infra_v1/azure`, helper defaults are example resource names and domains.
Pass your own ResourceGroup, VmName and (where applicable) PublicUrl explicitly
for any separately authorized operation. The commands below mutate resources:

```powershell
.\scripts\sonarqube-start.ps1
.\scripts\sonarqube-status.ps1
.\scripts\sonarqube-stop.ps1
```

`sonarqube-start.ps1` starts the VM, waits for `/api/system/status` to report
`UP`, then retries the full internal stack/tunnel status check for up to 120
seconds. This allows `cloudflared` to finish initializing its readiness endpoint
after Compose reports the container as started. A stuck check is bounded by GNU
`timeout`, with a five-second kill grace period. The helper also requires the public
`https://sonar.example.com/api/system/status` API to report the same
state. If a health check fails, it prints the returned Run Command stdout/stderr
before automatically deallocating the VM to avoid unattended compute cost.
The helpers require an explicit success marker from
the guest script rather than trusting only Azure CLI's own exit code. They
encode the multiline guest check locally and explicitly launch it with Bash,
avoiding Azure CLI newline-argument and `/bin/sh` differences.

Run the offline regression tests from `infra_v1/azure` (Git for Windows Bash is
used on Windows; Azure calls, HTTP requests, and sleeps are mocked):

```powershell
.\tests\Test-SonarQubeStart.ps1
```

The tests inject `PublicRetryDelay` for the public API retry loop rather than
defining a function named `Start-Sleep`. Normal startup still uses the native
PowerShell cmdlet with a five-second delay. The suite covers both transient public
endpoint failures followed by recovery and exhausted retries with deallocation.

`sonarqube-status.ps1` reports the Azure power state, Compose health,
Elasticsearch sysctls, SonarQube API status, and tunnel readiness.
`sonarqube-stop.ps1` uses Azure **deallocate**, not an in-guest shutdown, so
compute billing stops. Run the stop helper whenever a work session finishes;
the timer is only a safety net.

After the tunnel is healthy, log in as `admin` with the password configured by
the protected command above, then generate a dedicated analysis token. Store
it only in a separately authorized scanner/deployment system. Do not add
Sonar, Azure, GitOps or registry credentials to app_v1, helm_v1 or infra_v1:
their public CI is checks-only and does not contact a running SonarQube server.
