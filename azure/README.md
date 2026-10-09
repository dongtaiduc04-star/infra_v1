# Azure — existing GetLink environment

This is the Azure-only copy of the original infrastructure source and helpers.
The running app already follows `app_v1` → `helm_v1`; no second deployment,
new resource or Terraform-state handover is needed for ordinary releases.

## Existing identities

| Item | Existing value |
| --- | --- |
| Subscription | `529b5eb6-35b8-4998-a690-d34b60f28ca7` (Azure for Students) |
| Resource group | `rg-getlink-dtd-portfolio-mw` |
| Application VM | `vm-getlink-dtd-portfolio` / `10.60.1.10` |
| SonarQube VM | `vm-getlink-dtd-portfolio-sonarqube` / `10.60.1.20` |
| Region / VM size | `malaysiawest` / `Standard_B2as_v2` |
| GetLink | `https://getlink-azure.dongtaiduc.me` |
| SonarQube | `https://sonar-azure.dongtaiduc.me` |
| Private backend | `rg-getlink-tfstate` / `stgetlinktf498374` / `tfstate` / `azure-k3s.tfstate` |

Names and backend identifiers are non-secret configuration. Actual private
tfvars, state, plans, passwords, tokens, keys and kubeconfigs do not belong in Git.

## Start and check through the interfaces

1. In [Azure Portal](https://portal.azure.com), select the recorded subscription
   and open **Resource groups → rg-getlink-dtd-portfolio-mw**.
2. Open each of the two existing VMs and choose **Start**. Do not choose
   **Create**, redeploy extensions, reinstall services or reset credentials.
3. Wait for **Running**, then open [SonarQube](https://sonar-azure.dongtaiduc.me)
   and [GetLink](https://getlink-azure.dongtaiduc.me). Allow services and tunnels
   time to start; VM power state alone does not prove application readiness.
4. After pushing code to `app_v1/main`, use **app_v1 → Actions** to follow the
   Azure workflow, then check GetLink/login/content in the browser.

The workflow publishes the same four existing GHCR packages and changes image
tags in `helm_v1/helm/getlink-dtd/values-azure.yaml`. Existing Argo
`getlink-dtd` follows `helm_v1/main`, using chart `helm/getlink-dtd` and
`values.yaml` plus `values-azure.yaml`, with autosync/prune/self-heal enabled.
If its interface is available, check **Synced / Healthy** at the new Helm commit.

Keep these Repository settings in `app_v1`:

| Kind | Name | Value/purpose |
| --- | --- | --- |
| Secret | `AZURE_SONAR_TOKEN` | Existing Azure Sonar project analysis access |
| Secret | `GITOPS_PAT` | Only `helm_v1`, Contents read/write plus Metadata read |
| Variable | `AZURE_SONAR_HOST_URL` | `https://sonar-azure.dongtaiduc.me` |
| Variable | `ENABLE_AZURE_DELIVERY` | `true` |
| Variable | `HELM_REPO_NAME` | `helm_v1` |

Main pushes run delivery; pull requests run checks only. There is no manual
`Run workflow` trigger. The built-in `GITHUB_TOKEN` publishes packages; do not
add a separate token secret for that purpose. The four existing packages retain
`app_v1` Actions Write access and original `app` access; package visibility stays
unchanged. Never paste token values into screenshots, ordinary Run Command
scripts or Git.

The owner confirmed release `d6a86653ec927e5049de476ee67d0d66e2a9c437`,
Helm `6f05266eb2e3034f28c8d5492c5c20a1fa1307dc`, Synced/Healthy Argo,
Ready app/MySQL Pods and a working website on **2026-10-08**. This is dated
evidence, not a guarantee of later VM power state.

## End a work session

In each existing VM Overview, choose **Stop** and verify **Stopped (deallocated)**.
Both public sites are unavailable while their VMs are stopped. Compute billing
stops after deallocation, but disks/storage still cost. In-guest shutdown or
merely **Stopped** is not the same billing state.

The original three-hour/01:00 Vietnam self-deallocation cost guard remains.
Do not remove it for a normal release; this environment is not always-on/highly
available production infrastructure.

## Existing helpers, no new bootstrap

Sonar helpers retain the original behavior. They use Azure CLI's current account;
verify it selects the recorded subscription before use. From this directory:

```powershell
.\scripts\sonarqube-status.ps1
.\scripts\sonarqube-start.ps1
.\scripts\sonarqube-stop.ps1
```

Start checks the guest Sonar/tunnel and public API and may deallocate the Sonar
VM if health checks fail. Stop deallocates the same VM. Status uses Run Command
when running. These are operational commands, not offline tests.

Other bootstrap/Secret/tunnel scripts are retained as original recovery references,
not normal release steps. Public `helm_v1` needs no Argo Git token.
`configure-argocd-repo.sh` remains the original helper for private `helm.git`
and its existing `getlink-dtd-helm-repo` Secret; do not repoint that credential.

## Terraform remains manual

The original tracked `backend.tf` and Azure resource/bootstrap definitions are
retained. Use the SAME private Azure AD/CLI backend, actual private variables
and resource addresses. Application deployment did not transfer or verify
Terraform state/control. Keep original private infrastructure control until
a separately reviewed change selects ONE source/operator; never run old/v1
Terraform concurrently, migrate/copy state or initialize a fresh empty state.

No automated Terraform deployment workflow is added: the original Azure project
also used manual Terraform. Normal app delivery requires no plan/apply.
For a real infrastructure change, review its current state, private inputs and
saved plan before any apply; never apply a stale plan or bypass a state lock.

No Argo manifest apply is needed for the already-running deployment. Do not
blindly apply bootstrap directories or create a second Application. Preserve
existing `getlink-dtd` namespace, app/registry Secrets, MySQL/avatar PVCs, the
Sonar project and both Cloudflare tunnels. VM/disk/PVC deletion is not a repo
switch. Back up data before schema/storage changes; code rollback is not data
restore. See [shared operation and rollback notes](SHARED-CONTROL.md).
