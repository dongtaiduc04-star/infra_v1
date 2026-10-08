# Azure — shared existing GetLink environment

This is the only Terraform root in `infra_v1`. It preserves the existing Azure
resources rather than creating a v1 environment. It is a prepared alternative
source; no new controller has been activated.

## Recorded non-secret identity

| Item | Existing identity |
| --- | --- |
| Subscription | `529b5eb6-35b8-4998-a690-d34b60f28ca7` (Azure for Students) |
| Resource group | `rg-getlink-dtd-portfolio-mw` |
| k3s VM / private address | `vm-getlink-dtd-portfolio` / `10.60.1.10` |
| SonarQube VM / private address | `vm-getlink-dtd-portfolio-sonarqube` / `10.60.1.20` |
| Location / both VM sizes | `malaysiawest` / `Standard_B2as_v2` |
| Application / Sonar hostname | `getlink-azure.dongtaiduc.me` / `sonar-azure.dongtaiduc.me` |
| State storage resource group | `rg-getlink-tfstate` |
| Private state account / container | `stgetlinktf498374` / `tfstate` |
| Existing state key | `azure-k3s.tfstate` |

The hostnames and state identifiers are recorded configuration, not credentials.
Owner-authorized read-only Azure metadata checks during preparation found both
VMs deallocated and the state storage account provisioned with blob public access
disabled. That does NOT verify the state body/container, running k3s, Argo source,
live data, DNS routes, image pull access, or SonarQube readiness.

No Azure kubecontext was available locally; the unrelated AWS contexts must not
be used for this Azure environment.

## Backend and controller rules

The identifiers in `backend.tf` match the original tracked Azure configuration.
State remains private in the SAME store. Do not initialize an empty/new backend,
change the key, migrate/copy state, import into a second state or run both sources
as independent controllers. Authentication remains Azure AD plus Azure CLI;
no storage key or other credential is committed.

`backend.hcl.example` is a reference, not a request to create/configure a new
backend. Private override files, actual tfvars, state and plans stay excluded.

See [SHARED-CONTROL.md](SHARED-CONTROL.md) for the separate activation gates.
A local checker cannot prove exclusive ownership, Azure access or state lineage.

## Offline verification

```powershell
.\scripts\Test-SharedInfrastructurePreparation.ps1
.\tests\Test-SonarQubeStart.ps1
```

The preparation checker reads only named source files. It compares
17 normalized-text hashes against the original Azure Git baseline, validates
the exact backend identifiers and reviewed provider lock, checks both allowed
Helm URLs, and requires the prepared Application to use manual synchronization.
It does not read private tfvars/backend overrides/state or contact any service.

Terraform source checks remain `fmt -check`, provider-only
`init -backend=false -input=false -lockfile=readonly`, and `validate`.
Use an isolated copy and private validation cache; never initialize the live
backend merely to validate these files. Keep AzureRM 4.81.0 and both platform
hashes. No plan/apply/destroy or cloud commands are part of public infra CI.

## Existing runtime contract

Keep the single Argo Application, AppProject and destination namespace
`getlink-dtd`. `helm_v1` retains the original resource names, existing
`getlink-dtd-secrets`, `ghcr-pull-secret`, MySQL/avatar PVCs, four GHCR package
names, existing Sonar project and both existing Cloudflare tunnels.

The AppProject preparation allows `helm.git` and `helm_v1.git`. The Application
preparation selects `helm_v1` with the same chart path/value files and manual
sync for the cutover. These files have NOT changed the live Application. The
chosen steady-state mode is autosync from the selected source, activated only
after the separately approved cutover and checks. Pause auto sync/prune,
review the full live-to-desired diff, and require owner approval before a switch.
Do not re-run bootstrap or regenerate credentials/data when switching sources.

## Helpers are operational, not checks

The Sonar helpers preserve the original behavior and now use the existing
portfolio resource group, VM and public Sonar hostname by default:

- `sonarqube-start.ps1` starts SonarQube, runs guest health checks, checks the
  public endpoint, and may deallocate the VM on health failure.
- `sonarqube-stop.ps1` deallocates the existing VM.
- `sonarqube-status.ps1` queries Azure and uses guest Run Command when running.
  Although its guest commands inspect status, issuing Run Command is not an
  offline source check and needs separate authorization.

Do not execute these helpers during preparation. Their offline regression tests
mock Azure, HTTP and delays; they do not start/stop or contact either VM.

`install-argocd.sh`, `create-app-secrets.sh`, registry/tunnel/admin/bootstrap
scripts are recovery/provisioning references, not switch-source steps.
Existing secrets, tunnels and data must be reused, not recreated. The optional
Argo private-repository helper is limited to the existing private `helm` URL and
its existing repository Secret; public `helm_v1` normally needs no Git credential.

## Cost and persistence boundaries

Both VMs have no public IP, no inbound Internet NSG rule, and 64 GiB Standard SSD
OS disks. k3s uses single-node local-path persistence. SonarQube/PostgreSQL use
persistent Docker volumes on the existing Sonar VM. Never recreate either VM,
disk, namespace or PVC to switch repo source. Preserve backups before any
separately approved application/schema upgrade.

The existing timer requests self-deallocation after three hours or 01:00 Vietnam
time. Deallocation stops VM compute billing, not disk/storage billing. The
default-outbound-access subnet choice and single-host PostgreSQL are portfolio
cost tradeoffs, not a high-availability production design.

## Secrets and licensing

Do not publish Terraform state, plan files, tokens, passwords, private keys,
kubeconfig or actual private tfvars. Pass existing credentials only through
authorized protected mechanisms; never ordinary Git or command-history text.
Do not reset the existing Sonar administrator or tunnel credentials during this
source preparation. Retain the existing third-party notices.
