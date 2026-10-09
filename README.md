# infra_v1 — GetLink Azure infrastructure

Public Azure-only copy of the existing GetLink infrastructure and operational
helpers. It reuses the original Azure resources, data, secrets, SonarQube and
Cloudflare routes. The original private repositories remain unchanged.

Companion repositories: [app_v1](https://github.com/dongtaiduc04-star/app_v1)
and [helm_v1](https://github.com/dongtaiduc04-star/helm_v1).

## Everyday workflow

1. In Azure Portal, start the existing GetLink application and SonarQube VMs.
2. Check [SonarQube](https://sonar-azure.dongtaiduc.me) is available.
3. Push code to `app_v1/main`. Its Azure workflow tests/builds, runs Sonar and
   Quality Gate, publishes the four existing GHCR images and updates
   `helm_v1/helm/getlink-dtd/values-azure.yaml`.
4. The ONE existing Argo Application follows `helm_v1/main` and automatically
   deploys. Check [GetLink](https://getlink-azure.dongtaiduc.me) in the browser.
5. Stop/deallocate the two VMs in Azure Portal after the work session.

No Terraform apply, bootstrap, empty activation commit or repo-source switch
is needed for an ordinary application release. See [daily operations](azure/README.md).

The owner confirmed this flow on **2026-10-08** with app SHA
`d6a86653ec927e5049de476ee67d0d66e2a9c437` and Helm revision
`6f05266eb2e3034f28c8d5492c5c20a1fa1307dc`: Argo Synced/Healthy,
all four application Pods and MySQL Ready, and the website working.
This is a dated confirmation, not an uptime guarantee.

## Existing infrastructure, manual Terraform

The `azure` root retains the original Azure resource definitions and addresses.
It uses `rg-getlink-dtd-portfolio-mw`, `vm-getlink-dtd-portfolio` and
`vm-getlink-dtd-portfolio-sonarqube` in Malaysia West; there is no second v1
VM, namespace, database, state store, Sonar project or tunnel.

Terraform remains manual as in the original Azure project. No Terraform
control-source handover to `infra_v1` has occurred. An application release does
not verify state lineage or select a Terraform writer. For an actual
infrastructure change, review the SAME private Azure state and variables,
select exactly ONE source/operator for that session, then review the saved plan.
Never manage these resources concurrently from `infra` and `infra_v1`, migrate
state or initialize a fresh empty state. Read [shared control](azure/SHARED-CONTROL.md).

## Infrastructure operations and helpers

Like the original Azure infrastructure, this copy has no automated GitHub
Terraform apply workflow. Keep reviewed AzureRM 4.81.0 Windows/Linux hashes;
validate source without contacting the live backend when no infrastructure
change is intended.

Sonar helpers and their existing tests retain the original Azure source.
The helpers use the Azure CLI's current account/subscription: verify it is the
recorded Azure for Students subscription before invoking any helper. GUI-first
daily operation avoids depending on local CLI account selection. Offline tests
mock Azure/HTTP; no cloud is contacted:

```powershell
.\azure\tests\Test-SonarQubeStart.ps1
```

Bootstrap/credential/tunnel scripts are retained for separately reviewed
recovery/provisioning, not ordinary delivery. Do not recreate PVCs or reset
secrets to start a session. State, saved plans, actual private tfvars, passwords,
tokens, private keys and kubeconfigs stay out of Git.

## Source provenance, access and licensing

The original infrastructure/GitOps layout referenced a Vprofile learning
project. The maintainer reports that AI generated the source at their request;
this does not establish ownership or third-party licensing compliance.
Preserve applicable third-party licenses and notices.

Only the owner is intended to have write/merge access. See
[CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
No new MIT or other open-source license has been granted.
