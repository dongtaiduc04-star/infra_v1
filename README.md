# infra_v1 — GetLink Azure infrastructure

This public Azure-only repository is being prepared as an alternative control
source for the SAME existing GetLink environment as the private `infra`
repository. It is not a new environment, and preparation has not activated it.
The original repository and deployed resources remain unchanged by these edits.

Companion repositories: [app_v1](https://github.com/dongtaiduc04-star/app_v1)
and [helm_v1](https://github.com/dongtaiduc04-star/helm_v1).

## Shared existing environment

The Azure root preserves the original Terraform resource addresses and defaults:
`rg-getlink-dtd-portfolio-mw`, `vm-getlink-dtd-portfolio`,
`vm-getlink-dtd-portfolio-sonarqube`, Malaysia West. The applications reuse
their existing namespace, data, secrets, images, SonarQube, and Cloudflare routes;
there is no separate v1 VM, database or state.

The public backend identifiers in `azure/backend.tf` describe the existing
PRIVATE Azure state store. They are not credentials or the state body. Never
create a new state, migrate/copy state, import the old resources into another
state, or manage the same resources concurrently from `infra` and `infra_v1`.

Exactly one repository may be selected for Terraform operations at a time.
`azure/shared-control.preparation.json` intentionally has activation disabled
and no selected controller. A successful preparation check does not enable a
deployment. See [the shared-control runbook](azure/SHARED-CONTROL.md).

## Checks-only infrastructure CI

CI remains read-only and has no Azure identity or deployment secrets. It uses
Terraform 1.16.4 with the reviewed AzureRM 4.81.0 Windows/Linux lock. It checks
formatting, initializes provider packages with `-backend=false -lockfile=readonly`,
and validates source. It never initializes the real backend, reads state, plans,
applies, destroys, starts VMs or synchronizes Argo CD.

Offline checks exercise the SonarQube startup helper with mock Azure and HTTP
calls, and check inactive preparation/source parity:

```powershell
.\azure\scripts\Test-SharedInfrastructurePreparation.ps1
.\azure\tests\Test-SonarQubeStart.ps1
```

For Terraform source validation, use an isolated copy and private
`TF_DATA_DIR`; never reuse a production `.terraform` directory. Formatting and
validation are not proof of cloud deployment, database compatibility or cost.

## One application, two selectable Helm sources

The prepared AppProject permits only the existing `helm` and `helm_v1` URLs.
The prepared Application selects `helm_v1`, but automatic sync, prune and
self-heal remain disabled. Do not apply it blindly: inspect the live existing
`getlink-dtd` Application and rendered diff first, then explicitly authorize
a source switch and initial manual Sync. The chosen steady-state mode is
automatic synchronization from the selected Helm source, activated only after
the separately approved cutover and checks. Do not create a second Application
or delete/recreate the existing one. Restoring an image tag does not restore data.

## Private material and operational helpers

No state, saved plans, private tfvars, storage keys, tokens, passwords, private
keys or kubeconfigs belong in Git. Existing helper defaults now point to the
shared original environment. Start/stop/bootstrap/secret/tunnel scripts can
mutate it and are NOT publication steps or offline checks. Do not run them just
because CI is green. Stopped VMs still incur disk/storage cost.

Read [azure/README.md](azure/README.md) and the shared-control runbook before any
separately approved operational action.

## Source provenance, access and licensing

The original infrastructure/GitOps layout referenced a Vprofile learning
project. The maintainer reports that AI generated the source at their request;
this does not establish ownership or third-party licensing compliance.
Preserve applicable third-party licenses and notices.

Only the owner is intended to have write/merge access. See
[CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
No new MIT or other open-source license has been granted.
