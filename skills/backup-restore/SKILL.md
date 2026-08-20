---
name: backup-restore
description: Design, implement, or verify daily backups and restore workflows for Forgejo, Discourse, data services, and OpenTofu state.
---

# Backup Restore

Use this skill when changing backup schedules, retention, encryption, local staging, S3-compatible storage, restore procedures, or recovery testing.

For every backup workflow, make the following explicit: source data, consistency method, destination, encryption, retention, failure reporting, and restore steps. Separate service backups from infrastructure state backups and document the dependency order for recovery.

Prefer immutable or access-controlled backup destinations and least-privilege S3 credentials. Never print or commit credentials, state, or backup contents. A successful upload is not proof of recoverability: test a restore in an isolated location, verify application health and data integrity, and record what was checked.

Before dropping or replacing a database during a restore drill, stop the services that hold connections to it; restart them only after the restore and run a health check. A dump can complete successfully while an active application still makes the destructive step unsafe.

Give backup and restore temporary workspaces to the account that reads or writes their contents, and wait for an application endpoint or socket after restarting a service; `systemd` becoming active is not sufficient proof that the application is ready.

When a live restore or destructive test is requested, stop at the plan/runbook unless the task explicitly authorizes the affected environment. Include RPO/RTO assumptions and a rollback or containment step for operational changes.
