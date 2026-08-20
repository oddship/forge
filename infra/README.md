# Infrastructure

This directory will contain the OpenTofu configuration for Hetzner hosts, networking, firewall, storage, DNS integrations, and the Object Storage backend used by OpenTofu.

The first executable target is intentionally local: `just vm-build` builds `nixosConfigurations.local-vm`, and `just vm-test` runs the NixOS smoke test. Keep cloud provisioning separate until the host and service modules have a working local target.

Development state is local and Git-ignored. At the first real deployment, an isolated bootstrap configuration with local state creates and protects the Hetzner Object Storage bucket after an operator generates S3 credentials. The main infrastructure configuration must use that remote backend from its first apply. Keep the bootstrap recoverable, but never silently fall back production state to a local backend.

The production topology separates the stateful application host from the replaceable Forgejo Actions runner host. OpenTofu owns both hosts and their network, firewall, IP, volume, and DNS resources; NixOS owns the software and runtime configuration on each host.

Do not commit `.tfstate`, `.tfvars`, credentials, or generated provider files. Use `tofu plan` for review and require explicit authorization before applying changes.
