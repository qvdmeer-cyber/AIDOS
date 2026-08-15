# Initial implementation roadmap

This roadmap is implementation sequencing, not product truth for an integrated project.

## Foundation — current

- [x] repository responsibility and architectural boundaries;
- [x] generic Project Documentation/Definition/Worker/Execution agent contracts;
- [x] project documentation, Definition, execution, review, interruption and learning protocols;
- [x] state/event/project/documentation/Definition/execution/learning schemas;
- [x] project bootstrap template/tool;
- [x] first PowerShell state/project-binding module;
- [x] review artefact lifecycle design;
- [x] security/session/concurrency/recovery principles.

## Project Documentation Builder — usable before bridge

- [x] dedicated generic Project Documentation Agent;
- [x] strict software-project scope; organisation-documentation excluded;
- [x] existing-source-first / single-source-of-truth protocol;
- [x] one-question-at-a-time gap interview;
- [x] concern coverage + provenance model;
- [x] persistent project-local documentation manifest/session schemas;
- [x] documentation bootstrap tool;
- [x] accepted-baseline validator;
- [x] normal ChatGPT start entrypoint;
- [ ] run first real existing-project pilot;
- [ ] run first new-project pilot;
- [ ] refine concern taxonomy/questions from pilot evidence;
- [ ] add repository inventory/coverage assistance tooling where automation proves useful;

## Bridge MVP

- [ ] schema validation tooling;
- [ ] robust atomic state writes + append-only event locking;
- [ ] execution lease acquire/renew/reconcile;
- [ ] project registry on dedicated runner;
- [ ] Codex CLI start/resume wrapper and JSON event capture;
- [ ] session-rotation implementation;
- [ ] multi-project scheduler;
- [ ] heavy-job resource semaphore;
- [ ] review-ref publisher/consumer cleanup implementation;
- [ ] crash/restart recovery reconciler;
- [ ] telemetry store and compact status view.

## GPT desktop integration proof

- [ ] register exact Worker/Conversation chat locator per project;
- [ ] trigger correct Worker chat from `REVIEW_READY` without periodic polling;
- [ ] identity mismatch fail-closed test;
- [ ] foreground/minimized/closed app tests;
- [ ] Windows locked → `WAITING_INTERACTIVE_SESSION` proof in supervised mode;
- [ ] unlock/resume behaviour;
- [ ] end-to-end Worker review → Git state → Codex continuation proof.

## Definition Agent integration

- [ ] project-local Definition persistence workflow;
- [ ] one-question interactive protocol proof on desktop/mobile;
- [ ] explicit acceptance write path;
- [ ] contradiction → reopen → reaccept → execution continuation proof;
- [ ] consistency/convergence checks.

## Learning loop

- [ ] learning-candidate capture from project executions;
- [ ] provenance validation;
- [ ] capability/goal taxonomy and retrieval selection;
- [ ] promotion workflow (`CANDIDATE → PROVEN → TOOLIZED`);
- [ ] first generic validators/skills generated from proven learnings.

## Runner hardening

- [ ] dedicated Surface/Windows clean-room install guide;
- [ ] credential boundaries;
- [ ] disk/resource telemetry and safe thresholds;
- [ ] parallel-run tuning from observed data;
- [ ] optional per-project isolated runtime prototype;
- [ ] evaluate full Codex access only inside the isolated boundary.
