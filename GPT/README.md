This directory is assistant-owned working memory for recipe and step contracts.

Purpose:
- keep step-local memory outside the transient conversation
- record proven contracts and costly failure modes
- help trace downstream failures back to upstream causes

Rules:
- keep files short and factual
- update a step memory when its contract changes
- prefer one file per important step
- record inputs, outputs, invariants, and pitfalls
- if a stale machine bug is diagnosed from logs, update the affected step memory so the failure mode is explicit
- do not use this directory for general notes or speculation

Suggested use:
- when a step fails, inspect its memory file first
- if the real cause is upstream, follow the listed dependency chain
- when code changes invalidate a memory file, update it in the same work

Current high-value recipe memory:
- `publicist_draft_agent/recipe_overview.md`
- `publicist_draft_agent/load_material.md`
- `publicist_draft_agent/init_review_decisions.md`
- `publicist_draft_agent/plan_research_requests.md`
- `publicist_draft_agent/workspace_and_ui.md`
