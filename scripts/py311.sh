#!/usr/bin/env bash
set -euo pipefail

log() { printf '[py311] %s\n' "$*" >&2; }

# Search upwards for a project-local .venv with Python 3.11
resolve_project_venv() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -x "$dir/.venv/bin/python" ]; then
      if "$dir/.venv/bin/python" -c 'import sys; exit(0) if sys.version_info[:2]==(3,11) else exit(1)'; then
        printf '%s\n' "$dir/.venv/bin/python"
        return 0
      fi
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

find_python311() {
  local candidate

  # 1) Prefer project .venv if available
  if candidate="$(resolve_project_venv)"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  # 2) Direct executable in PATH
  if command -v python3.11 >/dev/null 2>&1; then
    printf '%s\n' "$(command -v python3.11)"
    return 0
  fi

  # 3) Try original user's pyenv (when running under sudo)
  if [ "${SUDO_USER-}" ]; then
    candidate="$(sudo -u "$SUDO_USER" sh -lc 'command -v pyenv >/dev/null 2>&1 && pyenv which python3.11 2>/dev/null || true')"
    if [ -n "${candidate}" ] && [ -x "${candidate}" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  # 4) Common install locations
  for candidate in \
    /usr/bin/python3.11 \
    /usr/local/bin/python3.11 \
    /opt/homebrew/bin/python3.11 \
    /opt/conda/bin/python3.11; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  # 5) Debian/Ubuntu alternatives
  if command -v update-alternatives >/dev/null 2>&1; then
    candidate="$(update-alternatives --list python3 2>/dev/null | grep -E '3\.11' | head -n1 || true)"
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  # 6) Fallback: system python3 if it is 3.11
  if command -v python3 >/dev/null 2>&1; then
    if python3 -c 'import sys; exit(0) if sys.version_info[:2]==(3,11) else exit(1)' >/dev/null 2>&1; then
      printf '%s\n' "$(command -v python3)"
      return 0
    fi
  fi

  return 1
}

main() {
  local interpreter script

  if [ "${1-}" = "--which" ]; then
    if interpreter="$(find_python311)"; then
      printf '%s\n' "$interpreter"
      exit 0
    else
      log "Python 3.11 not found"
      exit 1
    fi
  fi

  if ! interpreter="$(find_python311)"; then
    log "Python 3.11 interpreter not found. Install it or activate a 3.11 venv."
    exit 1
  fi

  if [ $# -ge 1 ] && [ -f "$1" ]; then
    script="$1"; shift
    exec "$interpreter" "$script" "$@"
  else
    exec "$interpreter" "$@"
  fi
}

main "$@"

