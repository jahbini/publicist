Topic: publicist workspace and UI contract
Recipe: `publicist_draft_agent`

Intent:
- keep shared code at repo level
- keep campaign data and artifacts inside the selected pipe workspace

Rules:
- `EXEC` is shared code root
- `CWD` is active workspace
- top-level recipe discovery still comes from `EXEC/config`
- UI artifact reads must come from active `CWD/out`

UI-facing publicist files:
- `source/publicist_source.txt`
- `source/publicist_campaign.yaml`
- `out/review_decisions.yaml`
- `out/outreach_log.yaml`
- `out/research_requests.yaml`
- `out/research_results.yaml`
- `out/target_candidates.yaml`
- `out/contact_discovery_requests.yaml`
- `out/contact_page_results.yaml`
- `out/review_packet.md`

Invariants:
- switching pipe should switch workspace-visible publicist state
- panel path labels should point into the active workspace
- UI save endpoints must update active-workspace artifacts, not repo-root files

Known pitfalls:
- stale prototype output in UI usually means workspace resolution drifted
- reopening UI alone does not create artifacts; the pipeline step must run
- if a panel is empty while Outputs shows files, inspect the panel’s workspace path first

Human-facing UI guidance:
- do not try to correct the human in a scolding way
- when a fetched or generated item is wrong, show the human exactly where to update it
- prefer direct UI backlinks, anchors, or panel links over abstract instructions
- if a generated result came from an approved request, expose the governing `request_id` and a jump path to that request
- do not silently rewrite, normalize away, or reinterpret human-entered values unless the UI clearly shows that transformation and the human explicitly chose it
- pipeline behavior should preserve human intent; if a value is unsafe or unsupported, surface that clearly instead of quietly changing it
