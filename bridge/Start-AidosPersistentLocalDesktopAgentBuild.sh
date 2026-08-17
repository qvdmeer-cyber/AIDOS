#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
assignment="$repo_root/START_PERSISTENT_LOCAL_DESKTOP_AGENT.md"
codex_path="${AIDOS_CODEX_PATH:-/home/aidos/.local/bin/codex}"
final_message="/tmp/aidos-persistent-agent-final-$$.txt"

cleanup() {
  rm -f "$final_message"
}
trap cleanup EXIT

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
printf '%s\n' 'Codex edits/tests inside its workspace sandbox; this wrapper owns git commit/push outside that sandbox.'

base_head="$(git rev-parse HEAD)"
git fetch origin main >/dev/null 2>&1 || true
remote_head="$(git rev-parse origin/main)"
if [[ "$base_head" != "$remote_head" ]]; then
  echo 'Local HEAD is not current origin/main before completion; refusing to publish against stale main.' >&2
  printf 'local=%s remote=%s\n' "$base_head" "$remote_head" >&2
  exit 4
fi

prompt="$(cat "$assignment")"
prompt+=$'\n\n## HEADLESS COMPLETION CONTRACT\n\nYou are running inside a Codex workspace sandbox. Do NOT attempt git commit or git push; repository metadata may be protected by the sandbox. The outer bootstrap owns publication.\n\nResume and finish the existing in-progress implementation in the current worktree. Preserve intentional existing changes. Complete all implementation and deterministic validation that can be done without bypassing authentication, UAC/elevation, login, unlock, or another real human-authority boundary. In particular:\n- finish the Persistent Local Desktop Agent implementation;\n- run the new agent tests and relevant existing bridge/session/review regression tests and fix failures;\n- formally consume/reconcile/cleanup smoke review b96eaae0-a267-4733-85ca-a31e8e6b0395 if still pending, without resend/fabrication;\n- review the final diff for accidental/generated/unrelated changes;\n- make the operator CLI and install/start/status/diagnostic usage explicit in documentation;\n- perform non-destructive machine smoke actions that are possible within the existing authenticated session.\n\nDo not claim completion if required deterministic tests are failing or implementation work remains.\n\nYour FINAL RESPONSE must end with exactly one of these machine-readable lines:\nAIDOS_AGENT_BUILD_COMPLETE\nAIDOS_AGENT_HUMAN_GATE: <single minimal human action>\n\nUse AIDOS_AGENT_BUILD_COMPLETE only when the code/worktree is ready for the outer wrapper to commit. A genuine machine/security gate may remain for installation/acceptance, but if that gate prevents code from being ready to commit, use AIDOS_AGENT_HUMAN_GATE instead.'

"$codex_path" -a never -s workspace-write exec --output-last-message "$final_message" "$prompt"

if [[ ! -f "$final_message" ]]; then
  echo 'Codex did not produce a final-message artifact; refusing publication.' >&2
  exit 5
fi

last_line="$(awk 'NF{line=$0} END{print line}' "$final_message")"
if [[ "$last_line" == AIDOS_AGENT_HUMAN_GATE:* ]]; then
  printf '%s\n' "$last_line"
  exit 10
fi
if [[ "$last_line" != 'AIDOS_AGENT_BUILD_COMPLETE' ]]; then
  echo 'Codex did not certify the worktree as build-complete; refusing publication.' >&2
  printf 'Final marker: %s\n' "$last_line" >&2
  exit 6
fi

if [[ -z "$(git status --porcelain)" ]]; then
  echo 'Codex reported build complete but produced no repository changes.' >&2
  exit 7
fi

if ! git diff --check; then
  echo 'git diff --check failed; refusing publication.' >&2
  exit 8
fi

# This assignment is intentionally scoped to host/bridge implementation, docs and tests.
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  case "$path" in
    bridge/*|docs/*|tests/*) ;;
    *)
      printf 'Unexpected changed path outside persistent-agent scope: %s\n' "$path" >&2
      exit 9
      ;;
  esac
done < <(git status --porcelain | sed -E 's/^.. //' | sed -E 's/ -> .*//')

git fetch origin main >/dev/null
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo 'origin/main advanced during Codex work; refusing automatic commit/push. Reconcile first.' >&2
  exit 11
fi

git add -A -- bridge docs tests
if ! git diff --cached --check; then
  echo 'Staged diff check failed; refusing commit.' >&2
  exit 12
fi

git commit -m 'Add persistent local desktop agent'
git push origin HEAD:main

printf 'Persistent agent implementation committed and pushed at %s\n' "$(git rev-parse HEAD)"
printf '%s\n' 'Code publication complete. Any remaining machine installation/acceptance gate must be reported by the agent tooling itself.'
