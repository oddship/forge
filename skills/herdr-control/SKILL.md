---
name: herdr-control
description: Inspect and control Herdr panes, tabs, workspaces, and agents when the user explicitly requests Herdr terminal orchestration.
---

# Herdr Control

Use this skill only when the user explicitly mentions Herdr or asks to inspect or control terminal layout, panes, tabs, workspaces, or agents through Herdr.

Before controlling anything, verify `HERDR_ENV=1`. If it is absent, report that the current agent is outside Herdr and stop. Read `herdr --skill` completely and inspect the relevant installed command group; the installed CLI is the syntax authority.

Inspect the current pane and layout before mutation. Target `--current`, an explicit opaque pane ID, or a unique agent name, and parse identifiers from Herdr JSON responses. Honor requested split direction and preserve the caller's focus with `--no-focus` for background work.

Do not close or move panes, tabs, workspaces, or sessions that this task did not create. Never stop the Herdr server from an active session. If socket access is denied by the execution sandbox, request narrowly scoped authorization for Herdr instead of bypassing the socket boundary.

Herdr authorization covers terminal control only. Repository creation, cloning private data, commits, pushes, deployments, destructive commands, and other external mutations still require their own task authority. Inspect a blocked agent before sending input, and report the resulting pane or agent identity and lifecycle state at handoff.
