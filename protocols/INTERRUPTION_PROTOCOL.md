# Human interruption protocol

## Purpose

AIDOS should allow development to run independently while making genuine human decisions manageable from a normal ChatGPT conversation, including mobile use.

## Interruption payload

When human input is required, persist a compact interruption record in project state containing:

- project/goal/execution/Definition binding;
- interruption type;
- exact evidence that caused it;
- decision required;
- current safe paused state;
- Definition question reference when applicable.

The human-facing Conversation Agent should not require reading a long Worker/Codex transcript.

## Product contradiction

For a Definition contradiction, the Conversation Agent presents the contradiction and asks one decision question at a time. On acceptance of a revised Definition, Worker may create a new/revised execution.

## Mobile continuity

Canonical project state, not device-local chat history, is the basis for resuming. A mobile Conversation chat must be able to reason from the same accepted/open Definition state as desktop.

## Supervised runner

If the runner is locked under `SUPERVISED` policy, it may finish an already-running bounded Codex execution but must not automatically start the next interactive GPT cycle. The pending interruption/review remains durable until the session is resumed/unlocked according to runner policy.
