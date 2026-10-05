# Services

Service-specific configuration will live here as the platform is implemented:

- Forgejo — source control and collaboration.
- Forgejo Runner — OCI-isolated Actions execution; local runners may share the disposable VM, while production runners use a separate host.
- Discourse — community forum and its supporting dependencies.
- Penpot — collaborative design and prototyping in the disposable local VM;
  see [operation and recovery notes](../ops/penpot.md).
- PostgreSQL and Redis — independently managed data services with service-owned backup and restore procedures.
- Mailpit — private, non-delivering email capture for local development and the pre-user MVP.
- ZITADEL and NetBird — operator identity and private networking.
- HAProxy and the observability stack — ingress, health, metrics, logs, and alerts. The current observability target uses loopback-only Prometheus, Grafana, ClickHouse, Vector, and Logchef services with bounded log retention.

Keep service data paths, upgrade procedures, health checks, and rollback notes close to each service configuration. Credentials belong in the chosen secrets workflow, never in Git.
