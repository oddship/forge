# Identity and private access

ZITADEL is the platform's authoritative operator identity provider. It should
issue OIDC identities for operator-facing applications, while NetBird provides
the private network path to those applications. Authentication and transport
are separate controls: being on the NetBird network does not replace
application login, and having a ZITADEL account does not make a private service
public.

## Deployment boundary

ZITADEL is a stateful control-plane service backed by PostgreSQL. Deploy it as
an independently managed service with its own database, backup, restore, and
upgrade procedures. The initial single-VM deployment may colocate it for cost
reasons, but the service boundary and data paths must remain split-ready.

Expose ZITADEL at a dedicated HTTPS hostname such as `id.example.com`. Put
HAProxy in front of it only after validating HTTP/2 and h2c forwarding; the
ZITADEL API and management console share its HTTP/2 endpoint. Do not expose
the ZITADEL database, admin API, or service port publicly.

The first deployment must retain a break-glass path that does not depend on
ZITADEL: SSH/NixOS administration, NetBird recovery, and one local emergency
administrator for each application. Rotate or disable emergency credentials
only after an OIDC login and recovery drill succeeds.

## OIDC client matrix

Create separate ZITADEL OIDC applications and secrets. Never reuse one client
secret across services.

| Client | Purpose | Access policy |
| --- | --- | --- |
| Forgejo | Developer login and operator administration | Map a ZITADEL admin/engineering group to Forgejo administrators; keep local admin recovery available. |
| Discourse | Community login | Enable the bundled OpenID Connect integration; keep account linking and auto-registration explicit. |
| Grafana | Operator observability login | Use Generic OAuth; allow sign-up only for the intended organization and map operator groups to Grafana roles. |
| Logchef | Log exploration login | Keep local authentication behind NetBird until the pinned Logchef release has a verified OIDC integration. |

Client IDs, client secrets, issuer URLs, and group-claim configuration belong in
the deployment secret workflow, not in Nix expressions or OpenTofu state. The
issuer should be the ZITADEL external URL so every client uses discovery rather
than hard-coded endpoint fragments.

## NixOS and recovery boundary

The reusable `forge.services.zitadel` module wraps the pinned nixpkgs ZITADEL
service. A production host must provide the master key and database settings as
external runtime files; a first bootstrap may also provide an external steps
file:

```nix
forge.services.zitadel = {
  enable = true;
  externalDomain = "id.example.com";
  masterKeyFile = "/run/keys/zitadel-master-key";
  databaseSettingsFile = "/run/keys/zitadel-database.yaml";
  bootstrapStepsFile = "/run/keys/zitadel-steps.yaml";
  backup.enable = true;
};
```

The runtime files must be readable by the `zitadel` service account and must
not be generated into the Nix store. The local backup archive contains the
PostgreSQL dump, master key, database settings, and optional bootstrap steps;
it is sensitive recovery material and must be encrypted before publication to
Object Storage. Use `systemctl start zitadel-backup` for a staged backup and
`FORGE_ALLOW_DESTRUCTIVE_RESTORE=1 forge-zitadel-restore ARCHIVE` only during a
reviewed restore window. Stop or isolate dependent OIDC clients while
restoring, then verify discovery and break-glass access before reopening them.

The module currently provisions and backs up a local PostgreSQL database. A
split-host deployment must replace this with a remote-PostgreSQL backup path
before setting `database.manageLocally = false`; the policy check intentionally
rejects enabling the current local backup implementation without local DB
ownership.

The disposable `checks.x86_64-linux.zitadel-smoke` target exercises the local
bootstrap, health probe, backup contents, destructive restore gate, and health
probe after restore. It uses fixture-only credentials and is not a production
secret or deployment procedure.

## Bootstrap order

1. Provision PostgreSQL storage and an encrypted backup destination.
2. Bootstrap ZITADEL's schema and first administrator through a one-time,
   reviewed procedure.
3. Put ZITADEL behind HTTPS and HAProxy, then verify discovery, login, logout,
   and recovery from an operator workstation.
4. Register the four OIDC clients and test group/role mappings one service at a
   time.
5. Restrict Grafana and Logchef ingress to NetBird; keep only the required
   public application routes on HAProxy.
6. Exercise a restore of the ZITADEL PostgreSQL database before removing any
   break-glass credentials.

The local application and observability VMs intentionally use local bootstrap
authentication for now. Adding ZITADEL to those VMs before a local HTTPS
issuer and disposable client-registration workflow exists would test wiring,
not a meaningful recovery path.

References:

- [ZITADEL requirements](https://zitadel.com/docs/self-hosting/manage/requirements)
- [ZITADEL reverse proxy requirements](https://zitadel.com/docs/self-hosting/manage/reverseproxy/reverse_proxy)
- [ZITADEL production and backup guidance](https://zitadel.com/docs/self-hosting/manage/production)
- [Forgejo OAuth configuration](https://forgejo.org/docs/latest/admin/command-line/)
- [Discourse OpenID Connect](https://meta.discourse.org/t/discourse-openid-connect-oidc/103632)
- [Grafana Generic OAuth](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/)
