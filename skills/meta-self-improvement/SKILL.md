---
name: meta-self-improvement
description: Capture durable, evidence-backed lessons from substantial repository work and improve the smallest relevant agent guidance or skill for future Forge runs.
---

# Meta Self Improvement

Use this skill after substantial learning that should change how future agents work in this repository. Typical triggers include a user correction, a repeated or non-obvious failure, a discovered infrastructure invariant, a bootstrap constraint, or an operational lesson that belongs in reusable project guidance.

Do not invoke this for generic knowledge, one-off typos, transient tool failures, or lessons already captured accurately. The goal is durable guidance, not a diary of every debugging step.

## Workflow

1. State the lesson in one sentence and identify the evidence: command output, a test, a review correction, or a confirmed design decision.
2. Check `AGENTS.md` and the existing `skills/` guidance for duplication or contradictions.
3. Update the smallest appropriate location:
   - `AGENTS.md` for repository-wide working agreements.
   - An existing domain skill for a recurring workflow or safety rule.
   - A focused reference file only when the lesson needs substantial, maintained detail.
4. Write the rule as an actionable decision or constraint. Preserve user intent and do not broaden permissions, invent production facts, or encode secrets.
5. Run the narrowest useful validation, normally `just check` plus skill frontmatter/placeholder checks. Mention the learning and resulting guidance change in the handoff.

When a lesson affects infrastructure safety, state, backups, credentials, or recovery, include the operational boundary and rollback/recovery implication. Prefer correcting an existing rule over adding another overlapping rule.
