# Agent instructions

Forge is an open-source Nix and OpenTofu repository for operating a small, self-hosted platform on Hetzner. The intended services include Forgejo with Forgejo Actions and Discourse; Hetzner Object Storage is the production backend for OpenTofu state and encrypted backups.

## Working agreements

- Treat production access, credentials, state, and backups as sensitive. Never commit secrets, private keys, `.tfvars`, state files, or generated credentials.
- Prefer declarative, reviewable changes in Nix, OpenTofu, and shell scripts. Keep one concern per change.
- Keep service modules and the production profile independent of cloud providers. Local development and release rehearsals must use real services with explicit local inputs; put provider-specific provisioning and hardware in separate adapters.
- Preserve a clear bootstrap path: remote state and backup services may not exist during first deployment, so document any one-time bootstrap explicitly and keep it recoverable.
- Use `nix develop` for the flake-provided development environment and `just` for repository commands. Do not add host-specific dependencies when the flake can provide them.
- Treat `justfile` as the public command interface: add or update a recipe before using a recurring repository command, and put nontrivial shell logic in `scripts/` instead of composing it ad hoc in agent tool calls.
- Keep `.envrc` aligned with the flake so Direnv users enter the same development environment as `nix develop` users.
- Treat Forgejo Actions as an MVP requirement. A runner may share the disposable local VM, but production runners must use OCI isolation on a separate host from stateful and control-plane services.
- Use private Mailpit capture for local development and the pre-user MVP. Configure and test transactional SMTP, including account recovery, before accepting external users.
- Keep the local secret boundary small: use Vaultwarden for human-managed credentials and SOPS with age for declarative infrastructure secrets. Do not add a centralized secret server or a third-party SOPS UI without an explicit requirement for runtime secret APIs, dynamic credentials, or multi-user auditability; those services add independent authentication, recovery, backup, and restore state.
- Use Prometheus and Grafana for metrics, and Vector to send logs to ClickHouse for private exploration through Logchef. Consume Logchef as a pinned native Nix package/module rather than an OCI service; bound telemetry retention and do not treat logs as backup data.
- The local observability target uses Logchef local authentication only for private bootstrap; replace it with the planned ZITADEL integration before exposing observability to external users.
- Before changing infrastructure, inspect the relevant service documentation and existing state/configuration. Do not guess at destructive operations.
- Backups are incomplete until a restore has been exercised. Changes to backup jobs should include a restore check or a documented reason it cannot run locally.
- Changes that affect networking, firewall rules, authentication, storage, upgrades, or data retention require a rollback or recovery note.
- After substantial, evidence-backed learning that should change future work, invoke `skills/meta-self-improvement` before handoff and update the smallest relevant guidance file.

## Common commands

```sh
nix develop
just install-hooks
just check
just fmt
just validate
just test
just test-secrets
just ci
just hooks
just secrets-init
```

`just check` is the fast pre-commit check. It runs formatting and syntax checks. Use `just validate` for full flake and infrastructure validation, or `just ci` for both; the repository is intentionally allowed to begin without a live infrastructure configuration.

## Repository shape

- `flake.nix` — pinned-tool development shell and formatters.
- `justfile` — stable entry points for agents and contributors.
- `infra/` — Hetzner, networking, storage, and OpenTofu configuration as it is added.
- `services/` — service-specific configuration for Forgejo, Forgejo runners, Discourse, and their data services.
- `ops/` — backup, restore, upgrade, monitoring, and incident runbooks.
- `skills/` — repository-local agent skills for recurring infrastructure work.

## Git and commits

Use Conventional Commits for every commit:

```text
<type>(optional-scope): imperative summary
```

Examples: `feat(infra): add Hetzner network`, `fix(backup): retain failed snapshots`, `docs: describe state bootstrap`.

Use lower-case types such as `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, and `ci`. Keep the subject concise. Explain operational impact and migration/rollback details in the body when needed.

## Skill routing

- Use `skills/infrastructure-change` for Nix, OpenTofu, Hetzner, networking, storage, and service deployment changes.
- Use `skills/backup-restore` for backup policies, S3-compatible storage, restore drills, and recovery testing.
- Use `skills/maintenance` for upgrades, routine operations, incident response, and runbook changes.
- Use `skills/herdr-control` only for explicitly requested Herdr terminal control.
- Use `skills/parallel-codex` only for explicitly requested concurrent Codex delegation and verification.
- Use `skills/meta-self-improvement` after durable lessons from debugging, review, incidents, or confirmed design decisions.

When a task spans more than one area, use the smallest set of applicable skills and keep their safety boundaries intact.
