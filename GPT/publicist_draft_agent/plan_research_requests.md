Step: `plan_research_requests`
Recipe: `publicist_draft_agent`

Purpose:
- generate planning-only research requests for follow-up targets
- preserve human review of allowed domains and approval state across reruns

Inputs:
- artifact `contact_ledger`
- artifact `audience_profiles`
- artifact `next_actions`
- existing artifact target `out/research_requests.yaml` when present

Outputs:
- artifact `research_requests`

Preserved fields by `request_id`:
- `status`
- `allowed_domains`
- `reviewer_notes`
- `reviewed_at`
- `review_required`

Debug/report fields:
- `preserved_count`
- `new_count`
- `approved_count`

Fallback behavior:
- if `next_actions` is empty, create `planned_only` background requests from `audience_profiles`
- never auto-approve
- `allowed_domains` stays human-controlled

Known pitfalls:
- if approved requests vanish on rerun, verify the run and UI are using the same workspace file
- if fetch sees nothing, inspect `status` and `allowed_domains` preservation here first
