# Agents Design Notes

This document sketches an experimental agent layer that sits above the
existing pipeline and `Memo` system without changing how current pipelines
execute.

## Core Position

The agent is a planner, not an operator. It can propose intents, sequence
work, and prepare drafts, but it does not directly execute shell commands,
HTTP calls, filesystem writes, or outbound messaging.

## Control Boundary

`Memo` remains the control boundary for all durable state, step coordination,
artifact handoff, and approval flow. The agent does not bypass `Memo`, and it
does not introduce a shortcut path around the existing pipeline ledger model.

## Execution Hands

Execution should happen through sandboxed devices only. Those devices act as
the agent's hands after intent is translated into explicit, reviewable,
approved steps. Future actions should route through `Memo`, `meta`, and
approved step devices rather than direct OS, network, or filesystem access by
the agent itself.

## Review Gates

Human review is required before any public outreach, network posting, or
contact action. The experimental agent layer may prepare drafts and recommended
next steps, but release to the outside world must stay behind an explicit
review gate.

## Non-Goal

This scaffold does not implement a live CLI, HTTP lookup path, or email
sending. It is documentation and draft configuration only.

## Workspaces

Publicist campaign content should live in the active workspace rather than in
shared repo fixtures. Each pipe directory acts as its own campaign workspace,
with `source/publicist_source.txt` defining the local campaign text and
`out/` holding that workspace's generated artifacts.
