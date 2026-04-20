#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODEL_NAME="${1:-}"
PIPE_NAME=""
PIPE_DIR=""

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "[start_pipe_ui] $*"
}

ensure_parent_dir() {
  local target="$1"
  mkdir -p "$(dirname "$target")"
}

write_override_yaml() {
  ensure_parent_dir "$PIPE_DIR/override.yaml"
  cat > "$PIPE_DIR/override.yaml" <<EOF
run:
  model: $MODEL_NAME
EOF
}

resolve_coffee_bin() {
  if [[ -x "$ROOT_DIR/node_modules/.bin/coffee" ]]; then
    printf '%s\n' "$ROOT_DIR/node_modules/.bin/coffee"
    return
  fi

  if command -v coffee >/dev/null 2>&1; then
    command -v coffee
    return
  fi

  die "Could not find a coffee executable"
}

[[ -n "$MODEL_NAME" ]] || die "Usage: $(basename "$0") <model-name>"
PIPE_NAME="${MODEL_NAME##*/}"
[[ -n "$PIPE_NAME" ]] || die "Could not derive pipe directory name from model name: $MODEL_NAME"
PIPE_DIR="$ROOT_DIR/pipes/$PIPE_NAME"
mkdir -p "$PIPE_DIR"
mkdir -p "$PIPE_DIR/logs" "$PIPE_DIR/state"

write_override_yaml

COFFEE_BIN="$(resolve_coffee_bin)"
UI_PORT_VALUE="${UI_PORT:-4311}"

info "Workspace: $PIPE_DIR"
info "Model: $MODEL_NAME"
info "Pipe name: $PIPE_NAME"
info "UI port: $UI_PORT_VALUE"
info "Starting UI server"

cd "$PIPE_DIR"
exec env EXEC="$ROOT_DIR" CWD="$PIPE_DIR" UI_PORT="$UI_PORT_VALUE" "$COFFEE_BIN" "$ROOT_DIR/ui_server.coffee"
