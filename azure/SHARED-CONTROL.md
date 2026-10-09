# Shared Azure operation

The public v1 repos operate the existing GetLink environment. They do not own
a second VM, namespace, database, Sonar project, tunnel or Terraform state.
Original private repos remain unchanged; shared running resources/data are reused.

## Application delivery

Push to `app_v1/main` to run the Azure CI/CD workflow and update only
`helm_v1`. One existing Argo Application `getlink-dtd` follows
`helm_v1/main` with autosync/prune/self-heal enabled. Check GitHub Actions
and the website; no Terraform or bootstrap step is required for normal code changes.

Both old/new pipelines share the four GHCR packages (including `latest`) and
Sonar project. The selected Helm source controls deployment; a successful
pipeline for an inactive Helm source does not select it in Argo.
Keep original access/credentials unchanged and give v1 only its required access.

## Infrastructure remains manual

The original Azure infrastructure had no GitHub Terraform apply workflow;
none is added here. The same original resource definitions/backend are retained.
No Terraform state/control handover to `infra_v1` has occurred.

For an actual infrastructure change, verify the SAME private state and actual
private variables, select ONE source/operator for the session and review a
new saved plan before applying. Never run old/v1 Terraform concurrently,
migrate/copy state, import into a second state, create a new backend or bypass
a state lock. A source handover should not require creation/replacement/deletion
of existing resources. Stop and reconcile any unexpected plan instead.

## Image rollback on helm_v1

Use a reviewed, known-compatible full SHA whose four images still exist.
Check schema/data compatibility first; code rollback cannot reverse migrations
or recover deleted data.

1. Stop further app releases while reviewing rollback; record the current tags.
2. In `helm_v1/helm/getlink-dtd/values-azure.yaml`, change ONLY
   `images.frontend.tag`, `images.apiGateway.tag`, `images.authService.tag`
   and `images.linkService.tag` to the same reviewed SHA.
3. Make a normal commit to main (or the required owner PR). Do not force-push,
   reset history, change repositories/routes/Secrets/PVCs or use `latest`.
4. Argo autosync deploys that Helm commit. Check Synced/Healthy and the website
   before resuming releases.

Rebuilding/rerunning an old app pipeline is not a rollback procedure: it can
overwrite shared tags/Sonar and update an inactive Helm repo. SHA tags identify
a release but are not registry-enforced immutable objects.

## Exceptional source switch/recovery

Do not repeat the completed v1 cutover for daily use. A future switch to/from
private `helm` changes the shared running app: inspect the actual Application,
pause autosync/prune/self-heal, check no operation is pending and review the full
rendered diff/images before switching the ONE existing Application. Refresh
comparison to the chosen URL, verify rollout/data and only then resume autosync.

Keep the AppProject limited to the old/new exact Helm URLs. Public `helm_v1`
needs no Argo Git Secret; the original private `helm.git` credential remains
on its original URL. Do not blindly apply a bootstrap directory, delete/recreate
the Application, recreate PVCs/VMs, reset secrets or start another Terraform
controller as a recovery shortcut. Back up data before schema/storage changes.
