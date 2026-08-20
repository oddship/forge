# Private networking

Forge uses NetBird as the operator overlay. NetBird manages the WireGuard
interface, peer enrollment, and policy; application services remain ordinary
NixOS services and do not need NetBird-specific configuration.

The repository module is `forge.services.netbird`. Enabling it requires an
external setup-key file and never accepts a key from the Nix store. The module
also supports `privateTCPPorts`, which opens application ports only on the
NetBird interface instead of globally in the host firewall.

Example production boundary:

```nix
forge.services.netbird = {
  enable = true;
  setupKeyFile = "/run/keys/netbird-setup-key";
  privateTCPPorts = [ 3001 8125 9090 ];
};
```

The setup key must be delivered by the deployment secret mechanism before
`netbird-netbird-login.service` runs. The key is an enrollment credential, not
an application password; rotate it in the NetBird control plane after the host
has joined and remove the old peer when replacing a machine.

## Access policy

- Public HAProxy routes are limited to the application endpoints that need
  external users.
- Grafana, Prometheus, Logchef, ClickHouse, SSH administration, and service
  backends are private by default.
- NetBird access does not replace ZITADEL login; operators still authenticate
  to the application.
- The local browser VMs intentionally do not join a real NetBird network. They
  use loopback-only QEMU forwards so local testing does not consume production
  enrollment credentials.

## Recovery

If NetBird enrollment fails, recover through the host provider console or
direct SSH from the provider network. Do not make NetBird the only path needed
to repair NetBird. After recovery, inspect `netbird status`, revoke the stale
peer, issue a replacement setup key, and repeat a private-service probe.

For a later multi-host deployment, keep the overlay address plan and access
groups in OpenTofu/Nix review, but keep private keys and setup keys in the
external secret workflow.
