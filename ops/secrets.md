# Secrets

Forge uses SOPS with age identities as the intended secret boundary for NixOS
hosts. Service modules receive paths to runtime files; they do not embed
passwords, tokens, or private keys in Nix expressions.

## Service boundaries

Keep the secret systems deliberately small and separate:

- Vaultwarden stores human-managed passwords and credentials.
- SOPS with age stores declarative infrastructure and deployment secrets in
  Git, encrypted at rest.
- The dashboard may link to these services, but it is not a secret store.

The local VM enables Vaultwarden sign-ups only as a disposable fixture. A
production deployment must set an external domain, disable open sign-ups, and
provide its recovery and backup policy before accepting users.

Forge does not deploy OpenBao or a third-party SOPS web UI. SOPS is an
encrypted-file workflow, and adding a stateful secret server would introduce
another source of truth, authentication and recovery state, and a separate
backup/restore obligation. Reconsider that boundary only when the platform
needs centralized runtime secret access, dynamic credentials, or multi-user
audit logs.

Start with the local workflow:

```sh
just secrets-init
just secrets-check
just test-secrets
```

`just secrets-init` creates ignored files under `secrets/`: a local age
private key and an encrypted YAML fixture. The fixture is only a workflow
check; it is not a production credential. `sops-nix` mounts declared values
under `/run/secrets/<name>` during host activation. The age key path must be
provided by the deployment environment and must not point into `/nix/store`.

The local NixOS VM additionally imports `modules/local-secrets.nix`. This is a
disposable development fixture: it generates a guest-only age identity,
creates deterministic local administrator credentials and a random Discourse
secret key at boot, installs them before the services, and exposes
`forge-local-sops-rotate.service` for the smoke test. It is not a production
secret source. The VM test verifies service-account permissions,
encrypted-at-rest fixture data, successful startup, and rotation-triggered
restart.

The production host boundary and per-secret ownership are recorded in
[secrets-inventory.md](secrets-inventory.md). The `hetzner-vm` target imports
the generic SOPS wrapper but not the local fixture. It expects an externally
injected age identity and encrypted file, and intentionally fails secret
activation if either bootstrap input is absent.

Before Hetzner deployment, define separate production recipients, distribute
the corresponding private identity through the bootstrap channel, and verify
that a fresh host can decrypt its secrets before enabling public services.
Rotate recipients and service credentials independently. Backups may contain
encrypted service data, but never the age private identity needed to decrypt
it.
