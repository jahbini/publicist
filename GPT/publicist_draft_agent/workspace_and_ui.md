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
