# Infrastructure

Software lives in provider-independent Nix service modules and environment
profiles. This directory owns cloud resources. See [the deployment
runbook](../ops/deployment.md) for the local/production boundaries.

`bootstrap/` creates separate private, versioned S3 buckets for state and
service backups, with deletion protection. `hetzner/` provisions a private
network, restricted operator SSH, a public application edge, and a separate
runner host. It uses a partial S3 backend from its first apply. Future clouds
get another provisioning root and a thin host adapter, reusing the production
software profile.

## Validation and bootstrap

Run these commands inside `nix develop`. `just infra-validate` installs locked
providers and validates their real schemas with backend initialization disabled.
This is static validation, not a simulated or live cloud plan.

1. Create Object Storage credentials in the provider console. Supply
   `MINIO_USER` and `MINIO_PASSWORD` through the operator environment. Keep
   credentials out of OpenTofu variables, backend files, Git, and VM images.
2. Set non-secret `TF_VAR_s3_endpoint`, `TF_VAR_s3_region`, and `TF_VAR_buckets`
   (JSON object with `state` and `backups` names). For Hetzner, use the selected
   location's endpoint hostname without `https://` and its signing region.
3. Run `just infra-bootstrap-init`, then `just infra-bootstrap-plan`. Review
   and authorize the saved plan before `just infra-apply bootstrap`. This
   isolated root deliberately uses ignored local state to avoid the bucket/state
   cycle. Keep an encrypted offline copy of bootstrap state, with independent
   key custody; neither newly created bucket should be its sole recovery copy.
4. Verify that the actual buckets are private and versioning is enabled.
   Establish separate state and backup credentials and test their access
   boundaries. Hetzner keys initially cover every bucket in their project:
   separate bucket names alone do not isolate access. Use separate projects
   or explicit bucket policies, retaining independent recovery access.
5. Copy `hetzner/backend.hcl.example` to an ignored `*.backend.hcl`, replace
   bucket/endpoint/region inputs, and supply `AWS_ACCESS_KEY_ID` and
   `AWS_SECRET_ACCESS_KEY` in the environment. Never put credentials in backend
   arguments; initialization persists backend configuration locally.
6. Verify S3 conditional-write locking against the real endpoint with two
   isolated OpenTofu sessions and a separate disposable state key. Confirm
   that a second writer fails while the first holds the lock, then release it.
   Keep `use_lockfile = true`; do not bypass a failed probe with `-lock=false`.
   This check cannot run without a real endpoint and credentials.
7. Run `just infra-init /absolute/path/to/production.backend.hcl`. Supply
   `HCLOUD_TOKEN` and non-secret `TF_VAR_location`, `TF_VAR_operator_cidrs`
   (JSON CIDR list), and `TF_VAR_hosts` (JSON `app` and `runner` objects, each
   containing `image` and `server_type`). Use reviewed NixOS snapshot IDs;
   never bake private keys or application secrets into images.
8. Run `just infra-plan`. Review its saved, ignored `review.tfplan` and obtain
   authorization before `just infra-apply hetzner`. Saved plans are sensitive;
   remove them after use. No remote plan or apply is part of local validation.

The Hetzner root creates compute and network resources. It does not install
NixOS, bake images, inject secrets, configure DNS, or enroll an Actions runner.
The app image must satisfy `hosts/hetzner-vm.nix` (ext4 label `nixos`, GRUB
`/dev/sda`) and the operator access contract. Retain provider-console recovery
while injecting the persistent age identity, encrypted YAML, certificate, and
operator public-key file. Set the production domain, point DNS at the app
addresses, and verify activation/reboot before exposing users. The separate
runner image needs its own OCI configuration and registration credentials;
separate compute alone does not establish working Actions execution.

## Recovery and rollback

If buckets already exist, import them and their versioning resources rather
than creating replacements; bucket names are import IDs. Preserve bootstrap
state independently after deployment. Recover an encrypted state copy or use
reviewed imports if it is lost; never destroy buckets to repair missing state.

For a state recovery drill, download an older object version to a separate
protected workspace, verify lineage and serial, and run a read-only plan against
the actual cloud. Do not overwrite active state during the drill. Versioning
alone does not establish independent recovery custody or access control.

The app has provider delete/rebuild protection. Both hosts and the network have
OpenTofu `prevent_destroy`. Replacement-sensitive image changes must fail until
an operator explicitly reviews the replacement migration. Keep old app/data
available until restore and cutover succeed. Firewall changes require console
recovery and access verification from an allowed operator network. Infrastructure
rollback is a reviewed plan restoring prior inputs; NixOS rollback uses the
previous generation as described in the deployment runbook.

Backup upload, encryption, Object Storage retention, failure alerts, and an
isolated restore from the remote copy remain release gates. Creating versioned
buckets does not complete the backup workflow.

References: [Hetzner bucket bootstrap](https://docs.hetzner.com/storage/object-storage/getting-started/creating-a-bucket-minio-terraform/),
[Hetzner credential scope](https://docs.hetzner.com/storage/object-storage/faq/s3-credentials/),
[OpenTofu S3 backend and locking](https://opentofu.org/docs/language/settings/backends/s3/),
[Hetzner server provider](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/server).
