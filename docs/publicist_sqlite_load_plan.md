# Publicist SQLite Load Plan

This document defines how draft-only publicist artifacts should later load
into SQLite. It is planning only. No loader code, runner changes, or database
writes are added here.

## Load Direction

Artifact files remain the source of truth. A future SQLite loader should read
the current YAML artifacts and derive normalized rows for indexed lookup.

## Artifact Mapping

### `audience_profiles.yaml` -> `audiences`

Each profile should map to one `audiences` row.

Suggested field mapping:

- `audience_key` -> `audiences.audience_key`
- `audience_label` -> `audiences.audience_label`
- `angle` -> `audiences.angle`
- `rationale` -> `audiences.rationale`
- `review_required` -> `audiences.review_required`
- artifact key/path metadata -> `audiences.source_artifact_key`

### `contact_ledger.yaml` -> `contacts`

Each ledger entry should map to one `contacts` row and join back to an
audience row.

Suggested field mapping:

- resolved audience id from `entries[].audience` -> `contacts.audience_id`
- `organization` -> `contacts.organization`
- `contact_name` -> `contacts.contact_name`
- `contact_role` -> `contacts.contact_role`
- `contact_channel` -> `contacts.contact_channel`
- `status` -> `contacts.status`
- `rationale` -> `contacts.rationale`
- `next_action` -> `contacts.next_action`
- `review_required` -> `contacts.review_required`
- artifact key/path metadata -> `contacts.source_artifact_key`

### `message_drafts.yaml` -> `drafts`

Each draft should map to one `drafts` row, joining to both audience and
contact when those records exist.

Suggested field mapping:

- `draft_id` -> `drafts.draft_id`
- resolved audience id from `audience_key` or `audience_label` -> `drafts.audience_id`
- resolved contact id from `contact_name` + `organization` -> `drafts.contact_id`
- `subject` -> `drafts.subject`
- `pitch_summary` -> `drafts.pitch_summary`
- artifact key -> `drafts.artifact_key`
- artifact path -> `drafts.artifact_path`
- `review_required` -> `drafts.review_required`
- draft-only workflow state -> `drafts.status`

Large draft text should remain in YAML or Markdown artifacts, not in SQLite.

### `review_decisions.yaml` -> `review_decisions`

Each decision row should map to one `review_decisions` record keyed by
`draft_id`.

Suggested field mapping:

- `draft_id` -> `review_decisions.draft_id`
- `decision` -> `review_decisions.decision`
- `reviewer_notes` -> `review_decisions.reviewer_notes`
- `approved_for_send` -> `review_decisions.approved_for_send`
- `reviewed_at` -> `review_decisions.reviewed_at`
- artifact key/path metadata -> `review_decisions.artifact_key`

## Future `outreach_events`

`outreach_events` should remain append-only future history. It should not be
loaded from the current draft-only artifacts yet because no send/log/follow-up
phase exists. When later phases are implemented, each reviewed outbound action
or follow-up should append a new event row rather than mutating prior history.

## First Implementation

The first SQLite loader should be a dry-run validator only.

It should:

- read the YAML artifacts
- resolve joins it would perform
- count rows it would insert per table
- report missing join keys or malformed rows
- print a deterministic summary of proposed inserts

It should not:

- create or modify the SQLite database
- update artifacts
- trigger any network, email, or send workflow

## Validation Priorities

- every audience profile resolves to one audience row
- every contact ledger row resolves to an audience
- every draft resolves to a stable `draft_id`
- every review decision resolves to an existing draft
- duplicate contact or draft identities are reported before any future write mode
