# Backup and restore

Every stateful service owns its consistency boundary and its restore command.
Backups currently land in local staging directories on the host. They are not
disaster recovery until an encrypted copy has been published to independent
Hetzner Object Storage and a restore has been exercised from that copy.

## Current coverage

| Service/data | Backup unit or command | Staging path | Restore check |
| --- | --- | --- | --- |
| Forgejo application data | Native `forgejo-dump.service` | `/var/lib/forgejo/dump` | Local smoke verifies a native dump is produced; a production drill must restore repositories and application data on an isolated host before cutover. |
| Forgejo PostgreSQL | `postgresqlBackup-forgejo.service` | `/var/backup/postgresql/forgejo.sql.gz` | Local smoke drops and restores the database with `pg_restore`, then starts Forgejo. |
| Forge Redis | `redisBackup-forge.service` | `/var/backup/redis/forge.rdb` | Local smoke writes a marker, restores the RDB, restarts Redis, and reads the marker. |
| Discourse PostgreSQL, Redis, and uploads | `discourse-backup.service` | `/var/backup/discourse/discourse-*.tar.zst` | Local smoke invokes `forge-discourse-restore` behind `FORGE_ALLOW_DESTRUCTIVE_RESTORE=1` and probes Discourse afterward. |
| ZITADEL PostgreSQL and recovery material | `zitadel-backup.service` | `/var/backup/zitadel/zitadel-*.tar.zst` | `zitadel-smoke` checks archive members, the destructive restore gate, and health after restore. |
| Penpot PostgreSQL only (partial coverage) | `postgresqlBackup-penpot.service` in the interactive VM | `/var/backup/postgresql/penpot.sql.gz` | Assets and the runtime master key also require a consistent capture; no complete backup or restore drill yet. See [Penpot recovery](penpot.md). |
| OpenTofu state | Remote S3 backend; bootstrap configuration added, live provisioning and locking checks pending | Independent versioned state bucket | Restore the state object into a disposable workspace and run a read-only plan before production use. |

The local test target also exercises Forgejo Actions, because runner state and
registration are operational dependencies even though the runner should be
disposable in production.

Forgejo recovery deliberately uses the separate PostgreSQL dump plus the
native file archive. The upstream CLI documents `forgejo dump` as a capture
archive, while its upgrade guidance warns that the embedded SQL dump has
long-standing reinjection issues. Do not treat the embedded SQL as the only
database recovery source; a full file-archive restore remains an isolated
production-drill task until the target storage layout is fixed and exercised.
See the [Forgejo CLI](https://forgejo.org/docs/latest/admin/command-line/) and
[backup guidance](https://forgejo.org/docs/latest/admin/upgrade/#backup).

## Recovery order

1. Rebuild the NixOS host, firewall, ingress, and private-access path.
2. Inject the age identity and encrypted SOPS configuration; verify secret
   installation and break-glass access.
3. Restore PostgreSQL, including all service databases and roles.
4. Restore Redis data where the service requires it; Redis is not a source of
   truth for Forgejo or Discourse, so application data takes precedence.
5. Restore Forgejo and Discourse application archives, then verify public
   health, login, uploads, mail, and background jobs.
6. Restore ZITADEL and verify discovery, administrator recovery, and OIDC
   clients before reopening private operator applications.
7. Re-enroll disposable runners and validate monitoring separately. Logs and
   metrics are operational evidence, not a replacement for service backups.

## Validation commands

Run the complete local recovery coverage with:

```sh
just test-local
just test-identity
just test
```

All destructive restore helpers require an explicit
`FORGE_ALLOW_DESTRUCTIVE_RESTORE=1` environment variable. Restore drills must
run on an isolated host or disposable VM, record the archive checksum, and
confirm service health before any production cutover.

## Retention and publication boundary

The service modules use bounded local retention so a failed publication cannot
silently remove the last local copy. The production policy still needs an
explicit Object Storage publication job with encryption, independent
credentials, retention, checksum verification, failure alerts, and a tested
prune policy. That publication and the OpenTofu state bucket bootstrap are
follow-up deployment work; local backup success must not be reported as
remote durability.
