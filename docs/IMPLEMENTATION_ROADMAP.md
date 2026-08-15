# Initial implementation roadmap

This roadmap is implementation sequencing, not product truth for an integrated project.

## Foundation — current

- [x] repository responsibility and architectural boundaries;
- [x] generic Definition/Worker/Execution agent contracts;
- [x] Definition, execution, review, interruption and learning protocols;
- [x] state/event/project/Definition/execution/learning schemas;
- [x] project bootstrap template/tool;
- [x] first PowerShell state/project-binding module;
- [x] review artefact lifecycle design;
- [x] security/session/concurrency/recovery principles.

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
