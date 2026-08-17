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
printf '%s\n' 'Codex owns repository implementation work; it must stop only at an explicit human/security bootstrap gate.'

base_prompt="$(cat "$assignment")"

run_codex() {
  local prompt="$1"
  "$codex_path" --sandbox workspace-write --ask-for-approval never exec "$prompt"
}

prompt="$base_prompt"
if [[ -n "$(git status --porcelain)" ]]; then
  prompt+=$'\n\n## RESUME / COMPLETION DIRECTIVE\n\nThis repository already contains uncommitted work from a prior Codex run for this assignment. Treat those changes as your own in-progress implementation, not as unrelated user edits. Resume from the current worktree. Do not discard, reset, stash, or overwrite them blindly.\n\nBefore returning control to the operator, complete all work that can be completed without bypassing a real human/security boundary:\n\n1. Inspect the existing dirty worktree and current durable AIDOS/review state.\n2. Finish the Persistent Local Desktop Agent implementation against the original assignment.\n3. Run the relevant deterministic tests, including the new agent tests and existing bridge/session/review regression tests; fix failures.\n4. Formally consume/reconcile/cleanup smoke review b96eaae0-a267-4733-85ca-a31e8e6b0395 through existing bridge contracts if it is still pending. Never resend or fabricate the review.\n5. Review the final diff for accidental/generated/unrelated changes.\n6. Commit the completed implementation in intentional commit(s). Do not push; the bootstrap wrapper will push after Codex exits with a clean worktree.\n7. From the same run, invoke the new agent installer/start/status/diagnostic and machine smoke steps when they can be performed under the existing authenticated AIDOS\\qvdm session without credential injection or security bypass. Calling Windows PowerShell from WSL is allowed for this implementation/acceptance work.\n8. If installation or acceptance reaches a genuine UAC/elevation, login, unlock, or other human-authority gate, stop there. Report exactly what is already complete and the single minimal human action required next. Do not stop merely because a command is Windows-specific or because RDP is connected/disconnected.\n9. If no human gate is reached, leave the agent installed/running and report the final agent status plus acceptance evidence.\n\nDo not end merely with uncommitted implementation files when tests and commit are possible.'
fi

for round in 1 2 3; do
  printf 'Codex completion round %d/3\n' "$round"
  run_codex "$prompt"

  if [[ -z "$(git status --porcelain)" ]]; then
    break
  fi

  if [[ "$round" -eq 3 ]]; then
    echo 'Codex exited three times with a dirty worktree; refusing to push incomplete work.' >&2
    git status --short >&2
    exit 4
  fi

  prompt=$'Continue the same Persistent Local Desktop Agent assignment from the current worktree. Your previous turn exited while the worktree is still dirty. Inspect what remains, finish implementation and validation, fix any failures, and commit all intentional assignment changes. Do not reset/discard the existing work. Do not push; the bootstrap wrapper will push after the worktree is clean. Stop only at a genuine human/security authority gate, and if one exists leave a clear final report describing the single required human action.'
done

if [[ -n "$(git status --porcelain)" ]]; then
  echo 'Worktree is unexpectedly dirty after completion loop; refusing to push.' >&2
  git status --short >&2
  exit 5
fi

local_head="$(git rev-parse HEAD)"
remote_head="$(git rev-parse origin/main)"
if [[ "$local_head" != "$remote_head" ]]; then
  printf 'Pushing completed Codex commit(s) to origin/main: %s\n' "$local_head"
  git push origin HEAD:main
fi

printf 'Persistent agent build bootstrap complete at %s\n' "$(git rev-parse HEAD)"
