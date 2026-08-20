# Operations

Runbooks for daily backups, restore drills, upgrades, monitoring, incident response, and routine maintenance belong here.

Every backup runbook should identify what is backed up, where it is stored, retention, encryption, failure reporting, and how to restore it. Prefer documented, repeatable commands over undocumented shell history.

Each stateful service owns its consistency, backup, and restore commands. Backups are written and verified in local staging before encrypted publication to Hetzner Object Storage. Development may exercise the same workflow against local fixtures, but local storage is not disaster recovery. OpenTofu state backup and service-data backup remain separate recovery paths.

Mailpit is private and non-delivering during the pre-user MVP. Before external users are accepted, configure transactional SMTP and verify signup, notification, and account-recovery delivery.

The ZITADEL and NetBird boundary is documented in [identity.md](identity.md).

The NetBird enrollment and firewall boundary is documented in [networking.md](networking.md).

The operator and Forgejo Git SSH boundaries are documented in [ssh.md](ssh.md).

The production secret ownership and break-glass procedure is documented in
[secrets-inventory.md](secrets-inventory.md). The service backup matrix,
recovery order, and current restore coverage are documented in
[backup-restore.md](backup-restore.md).

The standalone Hetzner host expects its bootstrap image to provide an ext4
root filesystem labelled `nixos` and installs GRUB to `/dev/sda`; the image
provisioning step must establish that disk contract before activation.

The local observability target keeps Prometheus, Grafana, ClickHouse, Vector, and Logchef on private loopback listeners. Grafana's encryption key is loaded by systemd from an external runtime file, and Logchef's API-token and local-admin secrets are also provisioned outside Git and the Nix store. Local Logchef authentication is a private bootstrap measure; replace it with ZITADEL before external exposure. ClickHouse log data has a bounded TTL and is not part of service or OpenTofu backup recovery; validate the observability stack separately after deployment.
