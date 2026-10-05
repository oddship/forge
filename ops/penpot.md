# Penpot

Forge's disposable local VM enables [Penpot](https://penpot.app/) at
<http://penpot.localhost:8080>. It appears on the landing page and dashboard.
Run `nix develop`, then `just vm-run`; in another development shell, run
`just penpot-smoke`. First boot needs registry access to download the images
and extra time for PostgreSQL migrations. The VM reserves 6 GiB RAM and a
16 GiB virtual disk. Existing VM disks are not automatically resized; use a
fresh disk via `NIX_DISK_IMAGE=/tmp/forge-penpot.qcow2 just vm-run` if needed.

The module pins the official frontend, backend, and exporter 2.18.1 images by
multi-architecture manifest digest. Their version must match the hash-pinned
upstream nginx template. MCP and the admin console remain disabled. Native
PostgreSQL owns database `penpot`; the existing native Redis instance uses
database 2 for ephemeral coordination. Penpot services use host networking
to reach these loopback services. Backend (6060), exporter (6061), frontend
(18083), and nginx metrics (18084) bind loopback and get no firewall opening.
HAProxy handles the browser origin and WebSocket upgrades, with a one-hour
tunnel timeout. This does not isolate containers from other host services;
do not treat them as untrusted runner workloads.

The pinned exporter's HTTP implementation ignores `PENPOT_HTTP_SERVER_HOST`.
A scoped Node preload forces its port 6061 listener to `127.0.0.1`; it leaves
other sockets alone. Verify the actual sockets after each upgrade and remove
the preload when upstream honors the host setting.

Create an account through the UI, read its verification email in
<http://mailpit.localhost:8080>, and follow the link. Registration verification
stays enabled. Exercise password recovery and a team invitation through the
same captured-mail path. Create a design, upload an image, and export it to
verify the exporter and shared asset mount. Mailpit sends no external mail.
HTTP session cookies are a disposable local exception; clipboard features
may require a browser secure context.

The local fixture generates a random master key once in the guest's root-only
`/var/lib/penpot/secrets.env` and preserves it across restarts. Assets live in
`/var/lib/penpot/assets` under the reserved `penpot` uid/gid 1001 used by the
images. Local PostgreSQL trust is restricted to role/database `penpot` over
IPv4 loopback. Neither the key nor database contents enter Git or the Nix store.

## Checks and diagnostics

`just test-penpot` checks evaluated credential paths, the local/production
authentication boundary, loopback listeners, closed backend ports, conditional
HAProxy routing, and the patched upstream nginx template. `just penpot-smoke`
checks the frontend, backend readiness, and browser origin in a running VM.
It does not verify account creation, uploads, export, or restore. The generic
NixOS local smoke test does not start Penpot: registry pulls require network
access that the isolated test driver lacks.

The 2026-10-05 integration check used a fresh interactive VM: all three
containers started, `/readyz` and the forwarded browser origin passed, actual
listeners stayed on loopback after applying the exporter preload, and a test
registration delivered its verification email to Mailpit. The VM was rebooted
with its original runtime key and database. Upload, export, authenticated
login, password recovery, and a complete restore remain unchecked.

Inside the VM, inspect `podman-penpot-backend.service`,
`podman-penpot-exporter.service`, and `podman-penpot-frontend.service` with
`systemctl status` and `journalctl`. Never print container environments or
the runtime secret file while diagnosing a failure.

## Backup and recovery boundary

The existing PostgreSQL backup schedule includes `penpot` in the interactive
VM, but that dump alone is **not a complete Penpot backup**. No new complete
Penpot backup job is scheduled. A consistent recovery set needs the database,
assets, runtime master key, and the matching image digests/configuration.
Redis coordination data is not a source of truth. Complete automated backup,
bounded retention, encrypted Object Storage publication, alerts, and an
isolated restore drill remain production gates.

For a manual capture on a private host, stop all three Penpot container units
before dumping `penpot` in custom format as the PostgreSQL account and copying
the assets and runtime secret file. Keep the services stopped until all three
components have been captured; restart and wait for `/readyz` afterward. Use
a root-only staging directory and encrypt the set before it leaves the host.
Record its checksum and the pinned image digests. Capture failure must retain
the previous set; delete an incomplete set only after recording the failure.
Choose and record retention and an alert destination before scheduling this
procedure. Local dumps and a same-host file copy are not disaster recovery.

Restore only on an isolated disposable VM: stop the containers, retain a
pre-restore recovery set, restore the database with `pg_restore` as PostgreSQL,
replace assets with ownership `1001:1001`, and install the original runtime
environment file root-owned with mode `0600`. Start the containers and wait
for `/readyz`, then verify the original account, design, uploaded image,
export, and captured password-recovery email. Record the checksum and results.
This drill has not yet been exercised; do not claim recoverability from the
policy or HTTP smoke checks. RPO is the age of the latest complete captured
set; RTO is unmeasured until a drill includes image downloads and migrations.

## Production and rollback

Penpot remains disabled on the Hetzner host. Before enabling it, configure
its own HTTPS hostname and certificate coverage, real transactional
SMTP and recovery tests, a separately provisioned PostgreSQL database/role
with password authentication, private Redis connectivity, and the complete
backup/restore workflow. Keep `localFixture = false`; provide a SOPS-managed
root-readable `environmentFile` with a stable `PENPOT_SECRET_KEY`,
`PENPOT_DATABASE_PASSWORD`, and any SMTP credentials. Configure `publicUri`,
`databaseUri`, `redisUri`, SMTP options, and HAProxy's `penpotDomain` and
`penpotBackend` together. Complete identity integration and private access
policy before external-user exposure; local password login is the current
bootstrap mechanism.

To roll back this addition, set `forge.services.penpot.enable = false` and
rebuild the VM. Its route and dashboard entry disappear; retain the database,
assets, and master key for recovery. Before an upgrade, capture a complete
consistent recovery set and update all three image digests plus the template
version/hash together. A Nix generation rollback alone cannot undo database
migrations: restore the matching database/assets/key set before starting old
images. Preserve the previous set until the restored application passes the
account, upload, export, and recovery checks.
