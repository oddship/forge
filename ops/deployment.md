# Development and production deployment

Forge has one set of real service modules. Environment profiles select the
runtime inputs and exposure rules; cloud adapters select disks and provisioning.

| Layer | Purpose |
| --- | --- |
| `modules/services/` and `modules/platform.nix` | Shared application and data-service implementations; no cloud provider dependency. |
| `modules/profiles/local.nix` | Disposable development stack, including Penpot, Actions, dashboard, Vaultwarden, and private Mailpit. |
| `modules/profiles/production.nix` | Provider-independent production core: Forgejo, Discourse, PostgreSQL, Redis, HTTPS, operator access, and externally supplied secrets. |
| `modules/profiles/local-https.nix` | Run the production core locally with disposable credentials, a local CA, and private Mailpit. |
| `hosts/` | QEMU or provider-specific boot, disk, and networking adapters. |
| `infra/hetzner/` | Hetzner resources only. Future providers get another infrastructure root and thin NixOS host adapter. |

The production profile currently enables the core services only. Penpot,
identity, observability, and the separately hosted Actions runner retain their
documented production gates. Sharing a service module does not establish that
every deployment profile enables every planned service.

## Local development and release rehearsal

Enter `nix develop`. Use `just vm-run` for the complete development stack and
`just test-local` for its real application, Actions, SSH, and restore checks.
Use `just test-https` to boot the production core in an isolated NixOS VM and
verify trusted HTTPS, HTTP redirects, private-route rejection, authenticated
Forgejo and Discourse administrator access, and persistent SOPS secrets and
certificate material after reboot.
These tests use actual applications, databases, SOPS, and HAProxy.

`just https-run` starts an interactive rehearsal VM with loopback-only host
forwards on HTTPS `8443` and HTTP `8084`. Resolve `forge.forge.test` and
`community.forge.test` to `127.0.0.1` on the host, and browse those names on
port `8443`. No public DNS, public certificate, cloud account, or ACME contact
is needed. The HTTP redirect is the production redirect to port `443`; use
the explicit local HTTPS port when browsing this forwarded VM.

The guest creates its own CA and a certificate valid for 30 days. Trust only
the public `/var/lib/forge-local-tls/ca.crt` in a dedicated development browser
profile or pass it to curl with `--cacert`; do not disable certificate checks.
The CA private key remains inside the disposable guest. The initial Forgejo
administrator is `forge-admin` with password `forge-local-forgejo-admin`;
Discourse uses `admin` and `forge-local-discourse-admin`. These are local
fixtures. To refresh an expired local certificate, remove only the disposable
TLS files in the guest, restart `forge-local-tls`, then restart HAProxy and
update the trusted public CA. Removing the ignored local HTTPS qcow2 disk
resets the entire rehearsal and destroys its local data.

## Production inputs

Import `modules/profiles/production.nix` into a host adapter for the target
provider. Configure `forge.platform.domain` with the real base domain before
deployment; the committed `example.com` default is a placeholder. The platform
uses `forge.<domain>` and `community.<domain>`.

Supply the persistent age identity and SOPS ciphertext using the secret
inventory runbook. The production key lives at
`/var/lib/forge/secrets/age-key.txt`, root-owned with mode `0600`. Boot fails
the secret precheck if either input is absent or the key permissions are wrong;
it never generates a replacement identity. Keep independent recovery custody.

Choose one certificate path:

- Supply a root-owned PEM containing the private key and certificate chain at
  `forge.productionIngress.certificateFile` (default `/etc/forge/tls/edge.pem`),
  readable by the `haproxy` group, with parent directory traversal restricted
  appropriately. The issuing system owns renewal and HAProxy reloads.
- Enable `forge.productionIngress.acme.enable`, set its contact `email`, and
  explicitly set `acceptTerms = true`. Configure both DNS names to reach the
  host and allow HTTP `80` and HTTPS `443`. NixOS ACME manages issuance and
  renewal, with HTTP-01 challenge traffic routed to a loopback Nginx responder.
  The edge initially uses NixOS's local bootstrap certificate; admit users only
  after trusted public issuance succeeds. Renewal starts after both challenge
  listeners and reloads HAProxy when certificate material changes.
  Live public issuance and renewal still require a real DNS/endpoint check.

HAProxy owns ports `80` and `443`. Discourse Nginx listens only on loopback
`18081`, receives a canonical Host and the trusted HTTPS scheme, and forces
HTTPS URLs. Local Mailpit, dashboard, and Vaultwarden routes are excluded from
the production edge. Unknown HTTPS Host headers receive `404`.

Before admitting external users, complete real transactional SMTP and account
recovery, the production runner configuration and OCI isolation on its own
host, encrypted backup publication, and an isolated restore from Object Storage.
The current local backup jobs alone do not provide disaster recovery.

## Migration and rollback

For an existing host using the former `/run/forge/secrets/age-key.txt` path,
install the same identity at the persistent path with root ownership and mode
`0600` before activating this generation. Preserve the original encrypted YAML
and offline recovery copy; do not regenerate keys or application secrets.
Check decryption and boot before opening ingress.

Before enabling HTTPS, install the certificate or establish ACME reachability,
and preserve provider-console/operator SSH access. If activation fails, select
the previous NixOS generation through that recovery channel. Retain both key
locations until rollback is no longer needed. Discourse's persisted site
settings may retain HTTPS; if intentionally rolling back to HTTP, reconcile
`SiteSetting.force_https` and the port through its Rails runner as part of a
reviewed maintenance operation. Avoid reopening HTTP service to external users
during recovery. No service data migration or cloud apply is part of local
rehearsal.
