#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIPES_DIR="$ROOT_DIR/pipes"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "[migrate_pipe_names] $*"
}

extract_model_from_provenance() {
  local provenance_path="$1"
  sed -n 's/^[[:space:]]*"model_id"[[:space:]]*:[[:space:]]*"\(.*\)",[[:space:]]*$/\1/p' "$provenance_path" | head -n 1
}

extract_model_from_override() {
  local override_path="$1"
  sed -n 's/^[[:space:]]*model:[[:space:]]*\(.*\)[[:space:]]*$/\1/p' "$override_path" | head -n 1
}

normalized_pipe_name() {
  local model_name="$1"
  local normalized
  normalized="${model_name//\//_}"
  normalized="${normalized// /_}"
  printf '%s\n' "$normalized"
}

resolve_model_id_for_pipe() {
  local pipe_dir="$1"
  local provenance_path="$pipe_dir/build/model/.model_provenance.json"
  local override_path="$pipe_dir/override.yaml"
  local model_name=""

  if [[ -f "$provenance_path" ]]; then
    model_name="$(extract_model_from_provenance "$provenance_path")"
  fi

  if [[ -z "$model_name" && -f "$override_path" ]]; then
    model_name="$(extract_model_from_override "$override_path")"
  fi

  printf '%s\n' "$model_name"
}

[[ -d "$PIPES_DIR" ]] || die "pipes directory not found: $PIPES_DIR"

shopt -s nullglob
pipe_dirs=("$PIPES_DIR"/*)
shopt -u nullglob

for pipe_dir in "${pipe_dirs[@]}"; do
  [[ -d "$pipe_dir" ]] || continue
  current_name="$(basename "$pipe_dir")"
  model_id="$(resolve_model_id_for_pipe "$pipe_dir")"

  if [[ -z "$model_id" ]]; then
    info "Skipping $current_name: could not resolve model id from provenance or override"
    continue
  fi

  if [[ "$model_id" != */* ]]; then
    info "Skipping $current_name: model id is not organization-qualified: $model_id"
    continue
  fi

  target_name="$(normalized_pipe_name "$model_id")"
  target_dir="$PIPES_DIR/$target_name"

  if [[ "$current_name" == "$target_name" ]]; then
    info "Already normalized: $current_name"
    continue
  fi

  if [[ -e "$target_dir" ]]; then
    die "Cannot rename $current_name -> $target_name because target already exists: $target_dir"
  fi

  info "Renaming $current_name -> $target_name"
  mv "$pipe_dir" "$target_dir"
done
