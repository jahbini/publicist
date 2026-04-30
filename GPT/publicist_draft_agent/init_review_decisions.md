Step: `init_review_decisions`
Recipe: `publicist_draft_agent`

Purpose:
- create durable human review state for outreach drafts

Inputs:
- artifact `message_drafts`
- existing artifact target `out/review_decisions.yaml` when present

Outputs:
- artifact `review_decisions`

Merge rules:
- key by `draft_id`
- preserve human fields:
  - `decision`
  - `reviewer_notes`
  - `approved_for_send`
  - `reviewed_at`
  - `updated_at`
- add new rows for new drafts
- remove nothing

Invariants:
- this artifact is working memory, not a fresh generation every run
- `updated_at` is only set on new rows

Known pitfalls:
- if human review disappears on rerun, inspect workspace mismatch before step logic
- if a different campaign reuses the same `draft_id`, source-hash checks upstream must prevent blind reuse
