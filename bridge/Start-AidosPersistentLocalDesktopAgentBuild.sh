#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
assignment="$repo_root/START_PERSISTENT_LOCAL_DESKTOP_AGENT.md"
codex_path="${AIDOS_CODEX_PATH:-/home/aidos/.local/bin/codex}"

if [[ ! -x "$codex_path" ]]; then
  echo "Codex executable not found or not executable: $codex_path" >&2
  exit 2
fi
if [[ ! -f "$assignment" ]]; then
  echo "Build assignment is missing: $assignment" >&2
  exit 3
fi

cd "$repo_root"
printf 'Starting Codex implementation from %s in %s\n' "$(basename "$assignment")" "$repo_root"
printf '%s\n' 'Codex owns repository implementation work; it must stop at any explicit human/security bootstrap gate.'

prompt="$(cat "$assignment")"
exec "$codex_path" exec "$prompt"
