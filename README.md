# Publicist Pipeline

This repository is a Memo-driven pipeline workspace for building AI-assisted workflows without giving the agent direct operational power.

The current primary example is `publicist_draft_agent`, a draft-first publicist system that can:
- read campaign source text from a selected workspace
- generate audience suggestions, target candidates, and reviewed draft messages
- preserve human review decisions and manual edits across reruns
- run controlled, approved research steps
- track manual outreach status without sending anything automatically

## Intent

The important design boundary in this repo is the combination of the pipeline runner and `Memo`.

`pipeline_runner.coffee` is the execution layer. It loads a top-level recipe from `config/`, expands it into `experiment.yaml`, schedules steps, and materializes declared artifacts.

`Memo` is the control boundary. Steps do not talk directly to the OS, browser, or external systems as an agent shortcut. Instead they:
- read declared inputs through Memo-backed artifacts
- write declared outputs through Memo-backed artifacts
- rely on meta devices for durable file materialization

That keeps state explicit, replayable, and reviewable.

In practice:
- recipe code lives under shared repo `EXEC`
- run state and artifacts live under active workspace `CWD`
- steps are expected to use declared `needs` and `makes`
- human review can edit selected artifacts in place, and later steps preserve those edits when ids and source hashes still match

## Workspace Model

This repo distinguishes two locations:

- `EXEC`: the shared code root for recipes, agents, runner, UI server, and docs
- `CWD`: the active campaign workspace, usually under `pipes/<campaign>`

For the publicist workflow, source input and outputs are workspace-local:

- `source/publicist_source.txt`
- `source/publicist_campaign.yaml`
- `out/*.yaml`
- `out/review_packet.md`
- `runtime/publicist.sqlite`

This means one shared system can run many separate campaign workspaces without duplicating code.

## Setting Up A New Pipe

To create a new campaign workspace:

1. Create a new directory under `pipes/`.
2. Add `source/publicist_source.txt`.
3. Optionally add `source/publicist_campaign.yaml`.
4. Run the top-level recipe `publicist_draft_agent` from that workspace.

Minimal example:

```text
pipes/mycampaign/
  source/
    publicist_source.txt
    publicist_campaign.yaml
```

Suggested starter source file:

```text
Describe this campaign here.
```

Suggested starter campaign config:

```yaml
priority_audiences:
  - technical_press
  - industry_partners
  - research_labs
  - pilot_customers
```

Then run from the workspace:

```bash
cd pipes/mycampaign
printf 'pipeline: publicist_draft_agent\n' > override.yaml
coffee ../../pipeline_runner.coffee
```

Expected outputs will appear in:

```text
out/source_material.yaml
out/audience_profiles.yaml
out/contact_ledger.yaml
out/message_drafts.yaml
out/review_decisions.yaml
out/outreach_log.yaml
out/review_packet.md
```

If you use the local UI:
- the UI server code still runs from shared `EXEC`
- the active pipe determines `CWD`
- the UI should read and write source files and artifacts in the active workspace only

## Recipes

Recipes are top-level YAML files in `config/`.

The publicist recipe is:

- `config/publicist_draft_agent.yaml`

That recipe is intentionally additive and review-oriented. It is designed to:
- avoid changing other pipelines
- avoid direct send behavior
- keep human approval visible in artifacts and UI

## GPT Working Memory

The `GPT/` subdirectory is assistant-owned working memory for Codex and future pipeline work.

It is not meant to be product output. It exists so Codex can recover important local knowledge quickly, especially when a pipeline has:
- step contracts
- proven invariants
- workspace rules
- known failure modes

For the publicist workflow, the most useful files are under:

- `GPT/publicist_draft_agent/`

Those notes describe:
- recipe intent
- `EXEC` vs `CWD`
- step-specific preservation rules
- common regressions and how to diagnose them

If a future Codex session seems to be missing pipeline context, `GPT/` is the first place it should look.

## Related Files

- `pipeline_runner.coffee`: runner and Memo integration
- `ui_server.coffee`: local UI server
- `ui/`: browser UI
- `docs/publicist_workspaces.md`: workspace-specific publicist notes
- `docs/agents.md`: agent-layer boundary and intent

## Practical Rule

If you are extending this repo, prefer:
- new declared artifacts
- normal pipeline steps
- UI-only human controls
- preservation of human-edited files

Avoid:
- bypassing Memo
- hidden side effects
- shared root outputs for workspace-specific campaigns
- automatic send behavior
