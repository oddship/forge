# Forge

Forge is an open-source, Nix- and OpenTofu-based infrastructure repository for hosting a small self-managed platform on Hetzner.

The planned platform includes:

- [Forgejo](https://forgejo.org/) with Forgejo Actions for source control, collaboration, and CI.
- [Discourse](https://www.discourse.org/) for community discussion.
- PostgreSQL and Redis as independently managed data services.
- ZITADEL and NetBird for identity-aware private access.
- HAProxy, Prometheus, Grafana, and logging for ingress and operations.
- Mailpit for captured email during local development and the pre-user MVP.
- Hetzner Object Storage for production OpenTofu state and encrypted backups.
- Automated daily backups, restore checks, upgrades, and day-to-day maintenance described as code and runbooks.

This repository is being built to make operations reproducible and reviewable. It does not yet contain a production-ready VM configuration. Do not apply infrastructure until the bootstrap, secrets, DNS, firewall, backup, and restore paths have been reviewed.

## Development

Install Nix with flakes enabled, then enter the project shell:

```sh
nix develop
just check
just install-hooks
```

If you use [Direnv](https://direnv.net/), allow the repository once with `direnv allow`; the committed `.envrc` will then load the flake automatically.

Useful commands:

```sh
just fmt       # format Nix and OpenTofu files when present
just check     # fast formatting and syntax checks
just validate  # full flake and infrastructure validation
just test      # build all application, observability, network, and identity checks
just test-secrets # run the local SOPS/age secret checks
just ci        # run fast checks plus full validation
just vm-build  # build the local NixOS VM target
just host-build # evaluate/build the Hetzner host target without deploying
just vm-test   # run the local NixOS smoke test
just test-identity # run the ZITADEL policy and restore smoke tests
just test-host  # run the production host policy check
just secrets-init # create an ignored local age identity and encrypted fixture
just hooks     # run the pre-commit hook against every tracked file
```

The development environment is defined in [`devshell.nix`](./devshell.nix) and composed by [`flake.nix`](./flake.nix). The command interface is in [`justfile`](./justfile), reusable shell lives in [`scripts/`](./scripts/), and the Git hook is configured in [`.pre-commit-config.yaml`](./.pre-commit-config.yaml). Keeping these interfaces current makes the repository usable by both people and coding agents.

## Planned layout

```text
infra/       Hetzner hosts, firewall, DNS, volumes, Object Storage, and OpenTofu state
services/    Forgejo, Actions runners, Discourse, and supporting service configuration
ops/         Backup, restore, upgrade, monitoring, and incident runbooks
skills/      Repository-local agent guidance for recurring workflows
hosts/       NixOS host targets, starting with the local VM
modules/     Reusable NixOS modules
tests/       NixOS smoke and integration tests
```

Development uses Git-ignored local OpenTofu state. The first Hetzner deployment bootstraps a protected Object Storage bucket before the main infrastructure is applied; production state must use that remote S3 backend. Forgejo Actions may share the disposable local VM, but its production OCI runner belongs on a separate, replaceable host.

The local secret workflow is documented in [`ops/secrets.md`](./ops/secrets.md),
and the production inventory is in
[`ops/secrets-inventory.md`](./ops/secrets-inventory.md). It uses SOPS and age,
with private identities kept outside Git and the Nix store. Backup and restore
coverage is tracked in [`ops/backup-restore.md`](./ops/backup-restore.md).

## Roadmap

1. Keep the validated Nix development shell, pre-commit workflow, and local
   QEMU target reviewable under Conventional Commits.
2. Maintain the local service stack: PostgreSQL, Redis, Mailpit, Forgejo,
   Discourse, service-owned backups, restore checks, and deterministic
   disposable administrator fixtures.
3. Keep the local integration boundary tested: HAProxy, Forgejo Actions with
   Podman, operator SSH, Forgejo Git SSH, observability, and policy checks.
4. Complete ZITADEL OIDC and NetBird production enrollment, HTTPS/h2c ingress,
   alerting, and the remaining operational runbooks.
5. Add the recoverable OpenTofu bootstrap for Hetzner networking, Object
   Storage state/backups, DNS, and the application/runner hosts; deploy NixOS
   only after the remote-state and disaster-recovery paths are exercised.

Mailpit is intentionally non-delivering. Transactional SMTP and account-recovery testing are release gates before accepting external users.

## Contributions

Read [`AGENTS.md`](./AGENTS.md) and [`CONTRIBUTING.md`](./CONTRIBUTING.md) before making changes. Commits use [Conventional Commits](https://www.conventionalcommits.org/).

Infrastructure changes should include validation, operational impact, and rollback or recovery notes. Never commit credentials or state files.

## License

Forge is licensed under the MIT License. See [`LICENSE`](./LICENSE).
