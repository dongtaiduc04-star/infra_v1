# Maintenance policy

This is a public portfolio/reference publication. Only the owner is intended
to have push and merge permissions; readers do not need collaborator access to
view, download or fork it.

A fork or pull request is a separate copy or proposed change, not permission to
update this repository. External suggestions are not automatically accepted.
Do not submit third-party code unless you can identify its source and confirm
the rights needed to publish it. Existing copyright/license notices must be
preserved. No new open-source license has been selected for original code.

Never include credentials, Terraform state, kubeconfigs or private logs in
public contributions. Follow SECURITY.md for sensitive reports.

Owner changes should use a branch and pull request, run the documented checks,
and be reviewed before merge. Do not add auto-merge, automatic deployment, image
publishing, cloud login or cross-repository write access without a new security
review. CI is verification only and should not receive deployment secrets.
