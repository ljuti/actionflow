---
type: ADR
id: "NNNN"
title: "Sentence-case decision title"
status: active
date: YYYY-MM-DD
supersedes:
superseded_by:
---

<!--
ADR TEMPLATE
============
Copy this file to docs/adr/NNNN-kebab-name.md and fill in the sections
below. The frontmatter shape above is mandatory; see AGENTS.md §10.5
for the full rules.

Filename and `id`:
- Use the next unused 4-digit number, zero-padded.
- The filename's numeric prefix MUST match the `id` field.
- The slug after the number is kebab-case and short.

Status transitions:
- `active`     — the decision is in force.
- `superseded` — a later ADR has replaced this one. Set this only when
                 amending the prior ADR's `status` and `superseded_by`
                 fields. Do not edit anything below the frontmatter.

Supersession:
- `supersedes:` lists the ADR id this one replaces (quoted string). Use
  `"NNNN (partial)"` if only part of the prior decision is replaced.
- `superseded_by:` is the inverse, filled in on the older ADR when a
  newer one replaces it.

Remove this comment block before committing.
-->

## Context

What is the situation that requires a decision? Constraints, prior art,
forces in tension. Keep this factual — the reasoning lives under
"Decision".

## Decision

What we are doing, stated as a present-tense directive. Be concrete:
include specific tools, paths, versions, and patterns where applicable.

## Consequences

### Positive

- What this unlocks or simplifies.

### Negative / trade-offs

- What this costs, forecloses, or makes harder.

### Follow-ups

- Concrete work this ADR implies but does not itself perform (e.g.,
  "update `docs/ARCHITECTURE.md` §X", "migrate existing call sites").

## Alternatives considered

Briefly: what else was on the table and why it was rejected. One short
paragraph per alternative is enough — agents and future readers need
the *why not*, not a full essay.
