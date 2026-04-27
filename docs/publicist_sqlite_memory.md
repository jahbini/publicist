# Publicist SQLite Memory

This document defines a future SQLite memory layer for the draft-only
publicist agent. It is a design scaffold only. No database file is created by
this change, and no pipeline step writes to SQLite yet.

## Source Of Truth

Files remain the source-of-truth artifacts:

- `source_material.yaml`
- `audience_profiles.yaml`
- `contact_ledger.yaml`
- `message_drafts.yaml`
- `review_decisions.yaml`
- `review_packet.md`

Those files are the canonical record for generated drafts, review packets, and
human-facing content.

## SQLite Role

SQLite is intended to act as indexed memory and lookup state, not the primary
artifact store. It is useful for:

- joining contacts to audiences and drafts
- querying review state across many runs
- tracking outreach-event metadata in future reviewed send phases
- retrieving lightweight metadata without loading every YAML or Markdown file

## Content Boundary

Large draft text should stay in YAML and Markdown artifacts. SQLite should only
store joinable metadata, identifiers, artifact references, and workflow state.

Examples of good SQLite data:

- audience keys and labels
- contact names, roles, and channels
- draft ids and artifact paths
- review decisions and approval flags
- outreach event timestamps and statuses

Examples of data that should remain in files:

- full draft email bodies
- full review packets
- source material text
- long reviewer commentary blocks

## Table Roles

- `audiences`: normalized audience definitions used across contacts and drafts
- `contacts`: reviewed or placeholder outreach targets
- `drafts`: lightweight draft metadata and file references
- `review_decisions`: per-draft human review outcomes and notes
- `outreach_events`: future append-only send/log/follow-up history

## Current Non-Goals

- No live SQLite database creation
- No runner integration
- No Memo API changes
- No network, email, or send behavior
