---
name: parallel-codex
description: Start, coordinate, monitor, and verify parallel Codex agents in isolated Herdr panes when the user explicitly requests delegation or concurrent agent work.
---

# Parallel Codex

Use this skill only when the user explicitly asks to delegate work to Codex or run coding agents concurrently. Use `skills/herdr-control` for terminal mechanics and preserve its safety boundaries.

Give each writing agent a separate repository or non-overlapping worktree. Do not run concurrent writers against the same files. Before starting an agent, define its target workspace, bounded outcome, relevant constraints, required validation, permitted side effects, and forbidden external actions.

Create a named Codex agent in a background pane with the current Codex CLI. Prefer auto-reviewed workspace permissions such as `--approve-for-me`; never use approval or sandbox bypass flags. Enable search only when current external research is needed. Wait until the TUI is ready, submit the brief through the Herdr agent interface, and confirm that the lifecycle reaches `working`.

Parallel work should continue independently while the primary agent handles non-overlapping tasks. Inspect `blocked` or `unknown` states before responding. Answer routine workspace trust prompts only when the target is known; escalate requests for new credentials, remote creation, publishing, deployment, destructive actions, or expanded filesystem access.

At completion, read the agent output and independently inspect its diff, repository status, and validation evidence. Do not rely on the agent's summary alone. Do not commit, push, create remotes, or merge work unless the user authorized that action. Report the agent name, workspace, outcome, checks, and any remaining publication step.
