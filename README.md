# infra_v1 — GetLink Azure infrastructure examples

A source-only portfolio publication, not the state or control repository for
the owner's running infrastructure. Its only Terraform root is `azure/`,
with private k3s and SonarQube VM examples and cost-control helpers.

Run Terraform from `azure/` or use `terraform -chdir=azure` from this repository.

Companion copies:
[app_v1](https://github.com/dongtaiduc04-star/app_v1) and
[helm_v1](https://github.com/dongtaiduc04-star/helm_v1).

## Safety boundary

Cloud resources, Terraform state, credentials, private keys and kubeconfigs
are not included. The backend definitions intentionally omit the real storage
locations. `azure/backend.hcl.example` shows the fields an operator must supply
in a private `azure/backend.hcl`, only after selecting a state store they own.

Do not connect this copy to the original environment's backend. Do not migrate
or copy state from it. Never run `terraform apply`, `terraform destroy`,
`kubectl apply`, or VM start/stop scripts just to view or validate the source.
Actual deployment requires separate authorization, credentials, review and
budget. Stopped VMs may still incur storage charges.

Argo CD examples refer to `helm_v1` and have automatic synchronization
disabled. Domains, registries and helper defaults are examples.
The public application workflow does not publish images or update Helm values.
Optional private-repository bootstrap requires an explicit `HELM_REPO_URL`;
a public Helm repository can normally be read without such a credential.

## Checks-only CI

CI has read-only repository permissions, no cloud identity and no deployment
secrets. Terraform 1.16.4 is used to run formatting checks, then
`init -backend=false` and `validate` in the Azure root only.
Initialization may download provider packages; it does not initialize the
configured remote state backend. No plan/apply/destroy is run.

A separate offline regression job exercises the SonarQube startup helper using
mock Azure calls, HTTP responses and delays. It does not start a VM.

```sh
terraform fmt -check -recursive
terraform -chdir=azure init -backend=false -input=false -lockfile=readonly
terraform -chdir=azure validate -no-color
pwsh -NoProfile -File azure/tests/Test-SonarQubeStart.ps1
```

Formatting and validation do not prove cloud policy compliance, affordability,
or deployment success. Review provider versions and security recommendations
before adapting these portfolio examples to any real environment.

## Source provenance, access and licensing

The original infrastructure/GitOps layout referenced a Vprofile learning
project. The maintainer reports that AI generated the source at their request;
this is not a guarantee of originality or third-party licensing compliance.
Neither AI generation nor a clean Git history establishes ownership of all
source. Preserve any applicable third-party licenses and notices.

Only the owner is intended to have write/merge access. See
[CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
No new MIT or other open-source license has been granted; existing third-party
licenses and notices remain applicable.
