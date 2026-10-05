---
name: infrastructure-change
description: Plan, implement, and validate Nix or OpenTofu infrastructure changes for the Forge Hetzner platform; use for networking, storage, service deployment, and state backend work.
---

# Infrastructure Change

Use this skill for changes to the Nix development or host configuration, OpenTofu resources, Hetzner networking or storage, or Forgejo/Discourse deployment.

## Workflow

1. Inspect the current configuration, state assumptions, and relevant service boundaries before editing.
2. Identify bootstrap dependencies and whether the change affects a Hetzner host, firewall, DNS, persistent data, runner isolation, or the Object Storage-backed OpenTofu state backend.
3. Make the smallest declarative change. Keep secrets and generated state out of the repository.
4. Validate NixOS module options against the locked nixpkgs version when APIs are version-sensitive, then run `just fmt` and `just validate` or the narrowest relevant validation. Use `tofu plan` for real configuration changes and review the plan before any apply.
5. Record migration, rollback, and recovery notes for changes that can interrupt service or affect data.

When a generated systemd service needs a one-time bootstrap before normal startup, do not defer it with `enable = false` if it must later be started manually: NixOS can render that unit masked. Keep the unit startable and remove its boot `wantedBy` link instead, then make the bootstrap action explicit.

Forgejo reserves the literal `admin` username in the pinned release, so use a configurable non-reserved administrator name such as `forge-admin`. A one-time Forgejo administrator bootstrap should use `Type=oneshot`, `RemainAfterExit`, and a persistent marker: this makes success observable to NixOS tests and prevents repeated password changes while still allowing a recovery operator to remove the marker deliberately when restoring a database without the account.

Keep deterministic administrator passwords confined to disposable local fixtures. Production bootstrap passwords must arrive through the external SOPS runtime boundary and be rotated or replaced after break-glass verification.

For Forgejo's built-in SSH server, configure `BUILTIN_SSH_SERVER_USER` separately from `SSH_USER`: the latter controls the username shown in clone URLs, while the former controls the account accepted by the built-in listener. Validate both configuration and an end-to-end key-authenticated clone or push.

NixOS reads `users.users.<name>.openssh.authorizedKeys.keyFiles` at build time. Do not point it at a runtime bootstrap path under `/etc` or `/run`; use a root-owned `services.openssh.authorizedKeysCommand` for runtime operator keys, install the public-key file before disabling password/root SSH, and preserve provider-console recovery. OpenSSH also rejects an authorized-keys command executable directly under `/nix/store` when its parent directory modes fail `StrictModes`, so copy the wrapper to a root-owned runtime path such as `/run/forge/ssh` before `sshd` starts. The command runs with a minimal environment; use absolute paths for helper binaries.

External secret paths interpolated into a service pre-start must be readable by that service account while remaining outside Git and the Nix store; validate the effective file permissions under the same user that runs the service.

Prefer systemd `LoadCredential` when a service supports it, especially for secrets under NixOS's restricted `/run/keys` directory. If a daemon must read a secret path directly, validate both its parent-directory traversal permissions and the service sandbox in a VM test.

When enabling native Vector, build the affected NixOS host closure so NixOS runs Vector's configuration validator; Nix evaluation and formatting do not validate VRL syntax or sink configuration.

For interactive local VM smoke tests, treat QEMU boot as separate from application readiness: allow service-specific startup time and poll the reverse-proxy endpoints before diagnosing a failure. Nginx `return` locations should set an explicit `default_type` when serving a browser landing page; otherwise the default `application/octet-stream` can make a valid response download instead of render.

Validate the actual interactive QEMU closure in addition to cached NixOS tests. The QEMU shared Nix store can appear as guest UID 65534, so runtime tools that require root-owned configuration paths may fail even when their build-time validation passes; keep any workaround scoped to disposable VM hosts and retain the production runtime check. Keep manual VM provisioning aligned with the smoke-test contract: if an audit expects a provisioned account, team, source, or dashboard, configure and query that same object in both targets.

When placing HAProxy in front of a NixOS module that manages its own Nginx virtual host, inspect the rendered listen ports and explicitly move or disable the module-managed listener before binding HAProxy to the edge port. A QEMU host forward also still traverses the guest firewall, so every intentionally forwarded browser port needs an explicit guest firewall rule and an end-to-end host-side probe. When the browser origin uses a non-default port, configure that full origin in the application, preserve its canonical host and port in the upstream Host header, and verify an authenticated request with the browser Origin header; if the NixOS module exposes database-backed site settings as defaults, explicitly reconcile any already-persisted value rather than assuming a new default replaces it.

For OCI services using host networking, inspect every upstream listener, including metrics and diagnostic ports, and verify the actual guest sockets after boot. A declared environment option does not prove the implementation uses it: Penpot 2.18.1's exporter ignores its HTTP host setting, while its frontend adds a metrics listener on 8082 that collides with Forge's browser forward. Keep any binding workaround scoped to the pinned component, test the real socket behavior, and reassess it when upgrading; closed firewall ports do not establish loopback binding.

For Forgejo Actions container jobs, keep the Forgejo label type as `docker` for workflow compatibility, but select the backend explicitly through the wrapper and locked `services.forgejo-runner.instances.<name>.runtimes` options. Podman is socket-activated on this NixOS target, so readiness checks should wait for `podman.socket`; the runner's access to the system Podman socket is a privileged host boundary and remains an MVP-only exception until runners move to a separate VM.

For the observability stack, a green health endpoint is not an ingestion test. The local VM test must emit a unique journald marker, wait for a positive Vector-to-ClickHouse result, query that marker through Logchef's authenticated team/source API, and execute a real Grafana datasource query. Keep the responsibility split explicit: Logchef queries logs from ClickHouse, while Grafana currently verifies Prometheus metrics.

Provision Grafana dashboards declaratively beside their datasources with stable datasource UIDs, and verify both the datasource query and dashboard API response in the local VM test. Do not invent Logchef saved-query provisioning in the Nix module until the pinned Logchef release exposes a declarative contract; exercise its authenticated query API instead.

Treat an identity provider as stateful infrastructure, not a login toggle: ZITADEL requires PostgreSQL persistence and its reverse-proxy path must preserve HTTP/2/h2c behavior. Keep deployment, SSH, and application recovery usable without OIDC until discovery, login, logout, group mapping, backup restore, and a break-glass drill have all passed.

For the locked nixpkgs ZITADEL module, keep the database overlay, bootstrap steps, and 32-byte master key outside the Nix store; write the master-key file as exactly 32 bytes with no trailing newline. A ZITADEL recovery archive is incomplete unless it contains the PostgreSQL dump plus the master key and runtime settings needed to start the restored instance. When backup and restore cross service accounts, explicitly grant temporary dump ownership/traversal and use a drop-and-recreate database restore for partitioned schemas; gate destructive restore explicitly and only claim local backup support when the database is locally reachable.

For local SOPS workflows, preserve the input format explicitly: use a `.yaml`/`.json` temporary filename or pass `--input-type` when encrypting generated fixtures, otherwise SOPS may serialize the plaintext as a binary `data` field. Keep the age identity ignored and outside the Nix store, and test both successful decryption and absence of a plaintext marker in the ciphertext.

The Forge `modules/secrets.nix` wrapper depends on the `sops-nix` module being imported by the host; keep the wrapper optional rather than importing it into a host that has no SOPS provider. When adding new Nix source files to a flake, stage them before evaluating or building because Git-backed flakes do not expose untracked paths.

In a fresh NixOS VM, `sops.age.generateKey` is an activation-time mechanism and may not have run before a boot-time fixture service; a disposable local fixture must explicitly create and persist its guest-only key before invoking SOPS. Production hosts must inject their age identity instead. Secret ownership must match the process that reads the path during pre-start: the Discourse pre-start runs as `discourse`, so its local test secrets use `discourse:discourse` with mode `0400`.

A secret-rotation helper should order after the installer but avoid a reverse `Requires=` edge to it when the installer restarts consumer units; use an explicit installer restart so rotation cannot create a systemd restart loop. If a runtime SOPS file cannot be a pure Nix path, keep only a store symlink to the runtime path in the declarative manifest; never place generated plaintext or private keys in the store.

Standalone NixOS host outputs do not inherit local VM hardware. Declare and
document the root filesystem and boot-loader contract for each bootable host,
then add a policy check that evaluates the host without requiring its runtime
secret files or a local QEMU module.

Do not apply production infrastructure, rotate credentials, destroy resources, or modify remote state without explicit authorization in the task. If remote state is unavailable, preserve the bootstrap boundary instead of silently switching the steady-state workflow to local state.

For HTTP-01 issuance behind HAProxy, inspect the locked NixOS ACME unit split:
`acme-<cert>.service` supplies initial certificate material, while
`acme-order-renew-<cert>.service` performs network issuance. Order the latter
after both the edge and challenge responder; requiring successful issuance
before starting its HTTP listener would prevent bootstrap. Build the optional
ACME host configuration locally, and keep trusted issuance/renewal as live
DNS checks before admitting users.

After a Discourse restore, wait for the real HTTP endpoint as well as its
systemd unit. Restored workers can take over a minute to become ready on the
local VM; use a bounded per-request curl timeout and a separate readiness
window so proxy startup errors remain retryable without an unbounded request.
