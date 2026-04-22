#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODEL_NAME=""
PIPE_NAME=""
PIPE_DIR=""
UI_BIND_MODE="${UI_BIND_MODE:-local}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "[start_pipe_ui] $*"
}

pipe_name_for_model() {
  local model_name="$1"
  local normalized

  normalized="${model_name//\//_}"
  normalized="${normalized// /_}"
  printf '%s\n' "$normalized"
}

legacy_pipe_name_for_model() {
  local model_name="$1"
  printf '%s\n' "${model_name##*/}"
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    net|--net)
      UI_BIND_MODE="net"
      shift
      ;;
    local|--local)
      UI_BIND_MODE="local"
      shift
      ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [net|--net] [local|--local] <model-name>
EOF
      exit 0
      ;;
    *)
      if [[ -n "$MODEL_NAME" ]]; then
        die "Unexpected extra argument: $1"
      fi
      MODEL_NAME="$1"
      shift
      ;;
  esac
done

[[ -n "$MODEL_NAME" ]] || die "Usage: $(basename "$0") [net|--net] [local|--local] <model-name>"
PIPE_NAME="$(pipe_name_for_model "$MODEL_NAME")"
[[ -n "$PIPE_NAME" ]] || die "Could not derive pipe directory name from model name: $MODEL_NAME"
PIPE_DIR="$ROOT_DIR/pipes/$PIPE_NAME"
LEGACY_PIPE_NAME="$(legacy_pipe_name_for_model "$MODEL_NAME")"
LEGACY_PIPE_DIR="$ROOT_DIR/pipes/$LEGACY_PIPE_NAME"
mkdir -p "$PIPE_DIR"
mkdir -p "$PIPE_DIR/logs" "$PIPE_DIR/state"

write_override_yaml

COFFEE_BIN="$(resolve_coffee_bin)"
UI_PORT_VALUE="${UI_PORT:-4311}"

info "Workspace: $PIPE_DIR"
info "Model: $MODEL_NAME"
info "Pipe name: $PIPE_NAME"
info "UI bind mode: $UI_BIND_MODE"
if [[ "$LEGACY_PIPE_NAME" != "$PIPE_NAME" && -d "$LEGACY_PIPE_DIR" && ! -d "$PIPE_DIR/build" ]]; then
  info "Legacy tail-only pipe also exists: $LEGACY_PIPE_DIR"
  info "New launches now use organization-qualified pipe names."
fi
info "UI port: $UI_PORT_VALUE"
info "Starting UI server"

cd "$PIPE_DIR"
exec env EXEC="$ROOT_DIR" CWD="$PIPE_DIR" UI_PORT="$UI_PORT_VALUE" UI_BIND_MODE="$UI_BIND_MODE" "$COFFEE_BIN" "$ROOT_DIR/ui_server.coffee"
