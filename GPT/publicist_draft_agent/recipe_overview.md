Recipe: `publicist_draft_agent`

Purpose:
- run a draft-only publicist workflow inside a selected pipe workspace
- keep all durable state in Memo-backed artifacts under active `CWD/out`
- support human review, manual edits, controlled research, and offline tracking

Execution model:
- `EXEC` points at shared repo code and top-level `config/`
- `CWD` points at the active campaign workspace, usually `pipes/<campaign>`
- source text lives at `source/publicist_source.txt` in `CWD`
- optional campaign config lives at `source/publicist_campaign.yaml` in `CWD`
- all publicist artifacts materialize to plain `out/*` in `CWD`

Core flow:
- `load_material`
- `suggest_audiences`
- `identify_audiences`
- `build_contact_ledger`
- `draft_messages`
- `init_review_decisions`
- `init_outreach_log`
- validation / sqlite memory / next actions
- research planning and approved fetch
- target extraction and qualification
- contact discovery planning and approved contact-page fetch
- contact-page merge into ledger
- review packet

Key artifacts:
- `out/source_material.yaml`
- `out/audience_profiles.yaml`
- `out/contact_ledger.yaml`
- `out/message_drafts.yaml`
- `out/review_decisions.yaml`
- `out/outreach_log.yaml`
- `out/research_requests.yaml`
- `out/research_results.yaml`
- `out/target_candidates.yaml`
- `out/qualified_targets.yaml`
- `out/contact_discovery_requests.yaml`
- `out/contact_page_results.yaml`
- `out/review_packet.md`

Invariants:
- no step may bypass Memo
- no live send behavior
- no publicist artifact should point at repo-root `out/agents/publicist/`
- runner and UI must treat `EXEC` and `CWD` differently
- workspace-local human edits must survive reruns when ids and source hash still match

Known pitfalls:
- if UI shows stale prototype data, inspect active workspace resolution first
- if a pipe run uses repo-root artifacts, `CWD` handling regressed
- duplicate producers for one artifact key are rejected by the runner
- target-specific refinement in `draft_messages` is opportunistic; it reads later artifacts only if they already exist in Memo/materialized state
