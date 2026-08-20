# Forge manual local audit

This is a disposable local-QEMU audit of the Forge application and
observability targets. It does not deploy to Hetzner, contact Cloudflare, or
use production credentials.

Run the application and observability VMs in separate terminals:

```sh
just vm-run
just observability-run
```

Wait for each serial console to reach `multi-user.target`. Keep both terminals
open; they are also the VM consoles used for the credential and log checks.
Stop either VM with `Ctrl-a x` in its console, or run `just vm-stop` from a
separate terminal to stop only the Forge-named local VMs. The browser ports are forwarded
to `127.0.0.1` by QEMU. Hostnames ending in `.localhost` resolve to loopback in
modern browsers; if needed, add them to `/etc/hosts`:

```text
127.0.0.1 forge.localhost discourse.localhost mailpit.localhost
```

## Application VM

### Boot and service health

- [ ] The console reaches `multi-user.target` without a failed systemd unit.

```sh
systemctl is-system-running
systemctl --failed
systemctl is-active haproxy.service nginx.service forgejo.service forgejo-admin-bootstrap.service discourse.service
systemctl is-active postgresql.service redis-forge.service redis-discourse.service
systemctl is-active mailpit-forge.service
```

### HAProxy ingress

Use these URLs through the HAProxy edge on host port `8080`:

- [x] Landing page: <http://127.0.0.1:8080/>
- [x] Forgejo: <http://forge.localhost:8080/>
- [x] Discourse: <http://discourse.localhost:8080/>
- [x] Mailpit: <http://mailpit.localhost:8080/>

The direct backend forwards are useful for separating ingress failures from
application failures:

- [x] Forgejo direct backend: <http://127.0.0.1:8082/>
- [x] Discourse direct backend: <http://127.0.0.1:8081/>
- [x] Mailpit direct backend: <http://127.0.0.1:8083/>

Equivalent console probes:

```sh
curl --fail -H 'Host: forge.localhost' http://127.0.0.1:80/
curl --fail -H 'Host: discourse.localhost' http://127.0.0.1:80/
curl --fail -H 'Host: mailpit.localhost' http://127.0.0.1:80/
```

### Forgejo login

The local SOPS fixture supplies a deterministic disposable password to the
one-time Forgejo bootstrap unit:

| Username | Email | Password |
| --- | --- | --- |
| `forge-admin` | `admin@forge.localhost` | `forge-local-forgejo-admin` |

- [ ] Log in at <http://forge.localhost:8080/> with the credentials above.
- [ ] Confirm the Forgejo Actions page is available under the repository or
      site administration UI.

### Local operator SSH

The local VM exposes guest OpenSSH on host port `2200` for inspection. This is
password-only and disposable; production operator access remains key-only.

```sh
ssh -p 2200 operator@127.0.0.1
```

- [ ] Log in with password `forge-local-operator`.
- [ ] Run `systemctl --failed` and inspect `journalctl -u forgejo-admin-bootstrap.service`.

### Forgejo Git SSH

Forgejo Git SSH is separate from operator OpenSSH. The local VM forwards host
port `2222` to Forgejo's built-in Git SSH listener and host port `2200` to the
guest's operator OpenSSH listener.

```sh
ssh-keygen -t ed25519 -f ~/.ssh/forge-local-git -C forge-local-git
```

- [ ] In Forgejo, open the administrator account settings and add the contents
      of `~/.ssh/forge-local-git.pub` under **SSH/GPG keys**.
- [ ] Create or identify a test repository owned by `forge-admin`.
- [ ] Verify Git SSH access without an HTTP password:

```sh
GIT_SSH_COMMAND='ssh -F /dev/null -i ~/.ssh/forge-local-git -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10' \
  git ls-remote ssh://git@127.0.0.1:2222/OWNER/REPOSITORY.git
```

- [ ] Clone, commit, and push a test change using the same SSH command.

### Discourse login

The local SOPS fixture supplies this deterministic disposable credential:

| Email | Password |
| --- | --- |
| `admin@discourse.local` | `forge-local-discourse-admin` |

- [ ] Log in at <http://discourse.localhost:8080/>.
- [ ] Use the email and password above.
- [ ] Confirm the administrator UI loads.

### Mailpit

Mailpit has no login in the local target and does not deliver mail externally.

- [ ] Open <http://mailpit.localhost:8080/>.
- [ ] Confirm the Mailpit UI loads and the inbox is reachable.

### Local backup evidence

Run these from the application VM console:

```sh
systemctl start forgejo-dump.service
systemctl start postgresqlBackup-forgejo.service
systemctl start redisBackup-forge.service
systemctl start discourse-backup.service
find /var/lib/forgejo/dump -type f -print -quit
find /var/backup/postgresql -type f -maxdepth 1 -print
find /var/backup/redis -type f -maxdepth 1 -print
find /var/backup/discourse -type f -maxdepth 1 -print
```

- [ ] Forgejo application archive exists.
- [ ] Forgejo PostgreSQL dump exists.
- [ ] Forge Redis RDB exists.
- [ ] Discourse archive exists.

The destructive restore paths are exercised in disposable test VMs, not the
interactive VM. Stop the interactive VMs first, then run:

```sh
just test-local
just test-identity
```

- [ ] `just test-local` passes its PostgreSQL, Redis, Discourse, and Forgejo
      restore checks.
- [ ] `just test-identity` passes its ZITADEL restore check.

## Observability VM

### Credentials and health

The local observability target uses disposable credentials:

| Service | URL | Username/email | Password |
| --- | --- | --- | --- |
| Grafana | <http://127.0.0.1:3001/> | `admin` | `admin` |
| Logchef | <http://127.0.0.1:8125/> | `admin@forge.local` | `forge-local-admin-password` |
| Prometheus | <http://127.0.0.1:9090/> | none | none |

- [ ] Grafana login succeeds.
- [ ] Logchef login succeeds.
- [ ] Prometheus shows its healthy status page.
- [ ] Grafana contains the **Forge platform overview** dashboard.
- [ ] The dashboard's **Prometheus targets** panel returns data.

### Log ingestion through Logchef

From the observability VM console, emit a unique audit marker:

```sh
systemd-cat --identifier=forge-manual-audit echo forge-manual-audit-marker
```

In Logchef, select the provisioned **Forge platform logs** source and run:

```sql
SELECT timestamp, event
FROM logs.events
WHERE position(event, 'forge-manual-audit-marker') > 0
ORDER BY timestamp DESC
LIMIT 20
```

- [ ] The query returns the marker event.
- [ ] The event contains the journald identifier `forge-manual-audit`.

This verifies the intended boundary: Vector ingests journald into ClickHouse,
and Logchef queries the resulting log rows. Grafana currently verifies
Prometheus metrics; it is not the log viewer.

## Exit criteria

- [ ] Application services boot without failed units.
- [ ] HAProxy routes all three application hostnames.
- [ ] Forgejo and Discourse administrator logins work.
- [ ] Mailpit is reachable and remains non-delivering.
- [ ] Local backup archives are produced.
- [ ] Automated restore checks pass in disposable VMs.
- [ ] Grafana dashboard and Prometheus query work.
- [ ] Logchef returns a newly ingested journald marker.
- [ ] No production credentials, state files, or generated secrets were copied
      into the repository.

After the audit, stop both QEMU processes with `just vm-stop` or `Ctrl-a x`. The next deployment
milestone is provider-specific Hetzner, Cloudflare, Object Storage, and DNS
bootstrap; none of those are exercised by this document.
