Step: `load_material`
Recipe: `publicist_draft_agent`

Purpose:
- load campaign source text from the active workspace
- establish campaign identity and source hash for downstream preservation rules

Inputs:
- meta read `experiment.yaml`
- workspace file `source/publicist_source.txt`

Outputs:
- artifact `source_material`

Invariants:
- read source from active `CWD`, not from repo root
- fallback sample text is no longer the normal path
- output must include `source_hash`
- downstream human-edit preservation should key against this hash

Known pitfalls:
- do not reintroduce `data/agents/publicist/sample_source.txt` as the default source
- if a run from `pipes/<campaign>` still emits prototype copy, inspect this step first
- if source changes but stale drafts/research survive, inspect source-hash gating downstream
