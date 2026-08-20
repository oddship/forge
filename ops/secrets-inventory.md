# Production secret inventory

The production host consumes an age identity at
`/run/forge/secrets/age-key.txt` and an encrypted SOPS YAML file at
`/etc/forge/secrets/production.yaml`. Both files are bootstrap inputs. They
must exist before `sops-install-secrets.service` starts; the host does not
generate or recover either file automatically.

The age identity and encrypted data must have separate custody. Keep the age
identity in an offline/password-manager recovery record and keep the encrypted
SOPS file with the deployment configuration or backup publication. Never put
the identity, plaintext values, or a rendered `/run/secrets` file in Git, the
Nix store, OpenTofu state, or a service-data backup.

## Inventory

| Secret | Consumer | Runtime owner/mode | Rotation and recovery boundary |
| --- | --- | --- | --- |
| `discourse-secret-key-base` | Discourse | `discourse:discourse`, `0400` | Rotate only as a reviewed Discourse maintenance operation; restore the matching application data and restart Discourse. |
| `discourse-admin-password` | One-time Discourse administrator bootstrap | `discourse:discourse`, `0400` | Generate and inject through production SOPS; the local deterministic fixture is disposable only. Rotate or replace after break-glass verification. |
| `forgejo-admin-password` | One-time Forgejo administrator bootstrap | `forgejo:forgejo`, `0400` | Generate and inject through production SOPS; the local deterministic fixture is disposable only. Rotate or replace after break-glass verification. |
| `forgejo-mailer-password` | Forgejo SMTP | `forgejo:forgejo`, `0400` | Rotate at the SMTP provider and in SOPS together, then restart Forgejo and verify a delivery test. |
| `discourse-mailer-password` | Discourse SMTP | `discourse:discourse`, `0400` | The current service wrapper does not yet wire SMTP authentication; keep this as a pending production integration rather than placing an unused value in the host. |
| `netbird-setup-key` | NetBird enrollment | `root:root`, `0400` | Use once to enroll a host, revoke it in the NetBird control plane, and issue a replacement when rebuilding the peer. |
| `zitadel-master-key` | ZITADEL encryption | `zitadel:zitadel`, `0400` | Treat as recovery material; rotate only with a ZITADEL-specific migration plan and a tested restore. |
| `zitadel-database-settings` | ZITADEL database connection | `zitadel:zitadel`, `0400` | Rotate database credentials independently, update the encrypted overlay, restart ZITADEL, and verify discovery. |
| `zitadel-bootstrap-steps` | One-time ZITADEL bootstrap | `zitadel:zitadel`, `0400` | Use only during initial bootstrap or a reviewed recovery; remove access after the first administrator is verified. |
| `object-storage-access-key` / `object-storage-secret-key` | Backup publisher and OpenTofu bootstrap | publisher-specific, `0400` | Use separate least-privilege credentials for state and backup buckets; rotate without placing them on application services. |
| `hetzner-api-token` | OpenTofu provisioning | CI/operator environment only | Inject through the OpenTofu execution environment; never make it a NixOS secret or host file. |
| `forgejo-runner-token` | Disposable Actions runner | runner host only, `0400` | Keep runners separate from the production host; revoke and replace the token when rebuilding a runner. |

The initial `hetzner-vm` target declares only the secrets required by its
currently enabled Forgejo and Discourse services. NetBird and ZITADEL remain
disabled until their control-plane bootstrap, HTTPS routes, and recovery
checks are complete. Their ownership and paths are recorded here so enabling
them does not change the custody model.

## Bootstrap and break-glass recovery

1. Provision the host and create `/etc/forge/secrets` and
   `/run/forge/secrets` with root-only permissions.
2. Inject the production age identity and encrypted SOPS file through the
   approved bootstrap channel. Confirm the identity can decrypt the file
   before starting public services.
3. Start `sops-install-secrets.service`, then start services in dependency
   order. A missing key or encrypted file must stop activation rather than
   produce a partial public deployment.
4. Keep SSH/provider-console access and one local emergency administrator per
   application until OIDC login and a restore drill have both succeeded.
5. During recovery, rebuild the host, inject the identity and encrypted
   configuration, restore PostgreSQL and service data using the runbook, and
   verify health before reopening ingress.

The age identity is deliberately not stored with encrypted backups. If the
identity is lost, the encrypted backup is not recoverable; use the offline
recovery record and rotate recipients after access is restored.
