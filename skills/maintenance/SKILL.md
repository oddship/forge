---
name: maintenance
description: Prepare safe routine maintenance, upgrades, incident response, and operational runbook changes for the Forge platform.
---

# Maintenance

Use this skill for operating-system and service upgrades, recurring maintenance, health checks, incident runbooks, monitoring, and operational documentation.

Start with current service health, recent changes, dependency order, and available backups. Prefer a reversible, staged procedure with a maintenance window, verification checks, and a rollback path. For upgrades, pin or record versions and explain compatibility or migration requirements.

Keep day-to-day operations reproducible through Nix, OpenTofu, `just`, or a checked-in runbook. Do not turn an emergency manual action into an assumed permanent configuration without documenting and reconciling it afterward. Do not run disruptive commands against production without explicit authorization.
