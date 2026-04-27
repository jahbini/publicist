#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENV_PYTHON="$ROOT_DIR/.venv/bin/python"
REQUIREMENTS_TXT="$ROOT_DIR/requirements.txt"
PACKAGES=(mlx mlx-lm mlx-metal)

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "[upgrade_mlx_env] $*"
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || die "Missing required file: $path"
}

require_exec() {
  local path="$1"
  [[ -x "$path" ]] || die "Missing executable: $path"
}

get_installed_version() {
  local package_name="$1"
  "$VENV_PYTHON" - "$package_name" <<'PY'
import importlib.metadata as md
import sys

package_name = sys.argv[1]
print(md.version(package_name))
PY
}

verify_requirements_pin() {
  local package_name="$1"
  local expected_version="$2"
  local actual_line
  actual_line="$(grep -E "^${package_name}==" "$REQUIREMENTS_TXT" || true)"
  [[ "$actual_line" == "${package_name}==${expected_version}" ]] || \
    die "requirements.txt pin mismatch for ${package_name}: expected ${package_name}==${expected_version}, found '${actual_line:-missing}'"
}

sync_requirement_pin() {
  local package_name="$1"
  local package_version="$2"
  local tmp_file

  tmp_file="$(mktemp)"
  awk -v pkg="$package_name" -v ver="$package_version" '
    BEGIN { updated = 0 }
    $0 ~ ("^" pkg "==") {
      print pkg "==" ver
      updated = 1
      next
    }
    { print }
    END {
      if (updated == 0) {
        exit 17
      }
    }
  ' "$REQUIREMENTS_TXT" > "$tmp_file" || {
    rm -f "$tmp_file"
    die "Failed to update ${package_name} in requirements.txt"
  }

  mv "$tmp_file" "$REQUIREMENTS_TXT"
}

require_exec "$VENV_PYTHON"
require_file "$REQUIREMENTS_TXT"

info "Upgrading packaging tools in .venv"
"$VENV_PYTHON" -m pip install --upgrade pip setuptools wheel

info "Upgrading MLX packages in .venv"
"$VENV_PYTHON" -m pip install --upgrade "${PACKAGES[@]}"

declare -A INSTALLED_VERSIONS=()
for pkg in "${PACKAGES[@]}"; do
  version="$(get_installed_version "$pkg")"
  [[ -n "$version" ]] || die "Could not determine installed version for $pkg"
  INSTALLED_VERSIONS["$pkg"]="$version"
  info "Installed $pkg==$version"
done

info "Synchronizing requirements.txt with installed MLX versions"
for pkg in "${PACKAGES[@]}"; do
  sync_requirement_pin "$pkg" "${INSTALLED_VERSIONS[$pkg]}"
done

info "Verifying requirements.txt matches .venv"
for pkg in "${PACKAGES[@]}"; do
  verify_requirements_pin "$pkg" "${INSTALLED_VERSIONS[$pkg]}"
done

info "Final MLX package state"
"$VENV_PYTHON" -m pip show "${PACKAGES[@]}"

info "MLX environment upgrade complete"
info "The next pipeline_runner start will see matching .venv and requirements.txt pins."
