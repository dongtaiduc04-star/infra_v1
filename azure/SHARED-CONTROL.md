# Selecting a source for the existing environment

This is a preparation runbook, NOT permission to deploy. No cloud mutation,
Terraform state operation, credential change, GitHub deployment activation, or
Argo synchronization has been performed by preparing these files.

## Two selections are independent

1. **Application source:** the one existing Argo Application selects either
   `helm` or `helm_v1`. Both application pipelines can test/build/publish into
   the SAME four existing GHCR packages and update only their own Helm repository.
   A pipeline's success does not select that repository in Argo.
2. **Infrastructure control source:** select either `infra` or `infra_v1`
   for the SAME existing Azure backend and resources. Never run them as
   independent/concurrent Terraform controllers.

Switching the application's Helm URL does not switch the Terraform controller.
Switching Terraform source does not create another application or move its data.

## Current preparation gate

`shared-control.preparation.json` has `activationEnabled: false` and
`selectedController: null`. Infrastructure CI performs only offline/source
checks and has no deployment identity. The preparation checker intentionally
fails if someone changes that record to claim activation.

This record and the source checker are review aids, NOT an access-control lock.
Toggling a JSON value cannot authorize a deployment or prevent someone from
running Terraform directly. No Terraform apply workflow has been enabled here.

The original tracked Azure resource/bootstrap source baseline is commit
`6352ee7a2a309425badb76b4c6bf99480a06d532`. The public copy keeps those semantics
and the existing backend identity. Intentional differences are the Windows/Linux
AzureRM lock correction, preparation documentation/checks, explicit two-source
AppProject, and an inactive manual-sync Application proposal.

## Gate A — owner-only control review

Before enabling infrastructure control, separately authorize and review:

- The intended subscription, existing resource IDs, Azure account permissions,
  cost exposure and existing operational credentials. Metadata checks have
  confirmed the recorded two VMs/storage account, not application readiness.
- Exactly one active source, operator and operational authorization. Retain a
  private owner-controlled selection record. If deployment automation for the
  non-selected source actually exists, separately authorize pausing its access
  before handover; do not assume it exists or edit the original repository as
  part of this preparation. For CLI-only control, use only the selected source
  for each session. Do not turn public checks into an apply pipeline by merely
  adding credentials.
- No pending apply, destroy, VM bootstrap or saved plan from the other source.
  Discard/review stale plans through the owner-approved workflow; do not reuse
  a saved plan from another commit, selection or workspace.
- The SAME existing private state account/container/key, existing state lineage
  and resource addresses, and actual private variable values. This preparation
  did not read/export state, private tfvars or backend override files. If the
  expected state cannot be verified, STOP; do not initialize a fresh empty state.
- Current backups of MySQL/avatar data and Sonar PostgreSQL, and tested recovery
  expectations before any upgrade with data/schema impact.

Terraform backend state locking protects a state operation while it runs. It is
not a permanent owner-selection mechanism and does not make stale plans safe.
GitHub Actions concurrency groups are repository-scoped; equal group names in
`infra` and `infra_v1` do NOT serialize the two repositories. Public checks
remain non-operational regardless of such concurrency settings.

No `init -migrate-state`, `init -force-copy`, state copy/import, second state,
new VM, namespace, database, tunnel or Sonar project belongs in this handover.

## Gate B — a separately approved Terraform review

This runbook does not execute or currently authorize backend initialization,
plan, apply, destroy, refresh/import or state inspection. After Gate A and
separate owner authorization, the selected source must use the verified existing
backend with its private identity/variables. Review any saved plan completely.

A source-selection handover alone should not propose resource creation,
replacement, deletion, namespace/PVC changes or a new state. If it does, STOP
and reconcile configuration/state/variables rather than applying it. Existing
cloud drift can also produce changes; do not hide it or assume a plan is no-op.

Provider/schema compatibility, state lineage, Azure quotas/policies and data
compatibility require explicit verification. CI `validate` cannot prove them.
Never use `-lock=false` to work around another controller's lock.

## Gate C — switch the existing application source

This needs separate authorization to inspect and modify live Kubernetes/Argo.
Both recorded VMs are deallocated, and no Azure kubecontext is available locally;
never use the unrelated AWS contexts. Do not start a VM or invoke Azure Run
Command merely to complete these source checks.

When an authorized owner can inspect the existing cluster:

1. Record the current `getlink-dtd` Application, selected URL/revision/value
   files, live sync policy, AppProject permissions, health, current image tags,
   secrets/PVC names and backup status. Local old YAML sets autosync true but
   that is not proof of live settings.
2. Pause automatic sync, prune and self-heal before preparing the source switch.
   Inspect whether another parent Application/controller manages this object;
   do not let it immediately overwrite the paused policy or selected URL.
3. Prepare the existing AppProject to permit only the two exact Helm URLs:
   `https://github.com/dongtaiduc04-star/helm.git` and
   `https://github.com/dongtaiduc04-star/helm_v1.git`.
   The old private repository credential remains separate; public `helm_v1`
   normally requires no Git credential. Never repoint its existing Secret.
4. Compare the selected reviewed Helm revision to live resources using the same
   chart path, value files, fullname/release and `getlink-dtd` namespace. Preserve
   existing MySQL/avatar PVCs, secrets, service selectors and routes. Review all
   rendered changes, not just images. Ensure chosen image tags exist and the
   existing pull credential can read those packages.
5. Update the ONE existing Application's source URL/revision after approval.
   Do not delete/recreate it or create a second Application targeting the same
   objects. Deletion/finalizers/prune can remove managed resources/data.
6. Perform an owner-approved manual Sync, inspect rollout/health and test
   registration, login, links, uploads, public profiles and existing data.
   Keep automatic sync off during cutover. After verification, separately
   authorize activation of the already chosen steady-state autosync mode.

An inactive Helm source can still receive pipeline commits without changing
the running app. The initial manual-sync pause makes the cutover wait for
owner Sync. Once the chosen autosync mode is separately activated, changes to
the selected source can deploy after its pipeline updates Helm.

## Failure and rollback boundaries

Record the previous Helm revision and immutable image tags before a switch.
If rollout fails, stop further synchronization and inspect the cause. A reviewed
source/image rollback can restore code but NEVER automatically reverses database
migrations or restores deleted data. Do not recreate PVCs, run bootstrap, reset
secrets or start a second Terraform controller as a recovery shortcut.

No live Argo inspection, source switch, VM start, DNS/tunnel operation, Sonar
configuration, backend/state initialization or deployment activation has yet
been performed as part of this preparation.
