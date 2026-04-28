# Publicist Workspaces

Each pipe directory is a separate campaign workspace.

- The pipeline code and recipe stay shared at the repo level.
- The active workspace is the current `CWD`.
- Publicist source text lives in `source/publicist_source.txt` inside that workspace.
- Generated artifacts still materialize under `out/` inside that workspace.

## Source Definition

`source/publicist_source.txt` defines the campaign for that workspace. The
publicist pipeline reads that file through `Memo` during `load_material`.

If the file is missing, the pipeline creates a placeholder:

```text
Describe this campaign here.
```

## UI Behavior

The UI edits the source text in the active `CWD` workspace, not in `EXEC`.

- Switching pipes changes the active workspace.
- Saving the Campaign Source Text panel writes `source/publicist_source.txt`
  in that workspace.
- Rerunning the pipeline then uses that saved source text for the current
  campaign only.
