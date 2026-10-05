# Tests

The flake imports each test expression from this directory into
`checks.x86_64-linux`:

- `local-smoke.nix` covers operator SSH, Forgejo HTTP and Git SSH, Forgejo
  Actions, Discourse, HAProxy, Mailpit, PostgreSQL, Redis, and service restore
  paths.
- `observability-smoke.nix` covers ClickHouse, Vector, Prometheus, Grafana
  datasource and dashboard provisioning, and authenticated Logchef queries.
- `netbird-policy.nix` and `zitadel-policy.nix` validate evaluated firewall,
  secret, service, and backup boundaries.
- `penpot-policy.nix` checks container credentials, local/production database
  authentication, loopback listeners, ingress, and the pinned nginx template.
  `just penpot-smoke` probes a running interactive VM; account, upload, export,
  and restore checks are documented in `ops/penpot.md`.
- `zitadel-smoke.nix` exercises ZITADEL bootstrap, backup, destructive restore,
  and post-restore health.
- `production-host-policy.nix` verifies that the Hetzner host uses external
  SOPS inputs, keeps the local fixture disabled, and enables service-owned
  backup units without requiring local secret files during evaluation.
- `local-smoke.nix` also exercises the local SOPS activation boundary: the
  Discourse secret is random while disposable administrator passwords are
  deterministic, all remain encrypted in the source fixture, and the fixture
  is rotated through the explicit systemd service.

Run an individual check with:

```sh
nix build .#checks.x86_64-linux.zitadel-smoke
```
