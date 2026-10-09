# Security reporting

Do not post passwords, tokens, private keys, Terraform state, kubeconfigs,
database exports, or sensitive logs in public issues, pull requests or comments.

If GitHub private vulnerability reporting is enabled, use the repository's
Security tab to report privately. Otherwise ask the maintainer, without
including sensitive details, for a private reporting channel. Do not assume
that an ordinary issue or pull request is confidential.

This Azure copy has no GitHub Terraform apply workflow, just like the original.
Terraform and operational helpers use an authorized owner's private session;
they are not publication checks. No deployment credential belongs in Git.
Examples that name a Secret contain references only; real values must be
supplied outside Git. An operator must change any factory/demo credential
before exposing a real service.

If a real credential is exposed, revoke or rotate it at its issuer and update
dependent services before cleaning source/history. Making a file private or
deleting it from the latest commit does not invalidate a leaked credential.

Only owner-approved changes belong in this repository. Do not grant write
permissions to a bot, deploy key or integration just to run checks. Build
success and a secret scan do not constitute a full security assessment.
