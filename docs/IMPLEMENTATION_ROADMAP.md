# Initial implementation roadmap

This roadmap is implementation sequencing for the private AIDOS runtime.

## External project-preparation prerequisite

Project-baseline preparation is now intentionally outside this repository:

- `qvdmeer-cyber/AIDOS-Contracts` owns the deterministic baseline/access contracts;
- `qvdmeer-cyber/AIDOS-Builder` owns the distributable Project Documentation Builder;
- accepted baseline/project truth remains in each project repository.

AIDOS runtime onboarding requires an accepted compatible project baseline.

## Foundation — current

- [x] repository responsibility and architectural boundaries;
- [x] generic Definition/Worker/Execution agent contracts;
- [x] Definition, execution, review, interruption and learning protocols;
- [x] launch/release governance principle and frozen-scope protocol;
- [x] `RELEASE_READY` conceptual state and explicit Launch Definition reopen rule;
- [x] state/event/project/Definition/execution/learning schemas;
- [x] project bootstrap bound to an existing project baseline;
- [x] first PowerShell state/project-binding module;
- [x] review artefact lifecycle design;
- [x] security/session/concurrency/recovery principles.

## Bridge MVP

- [ ] validate accepted AIDOS-Contracts baseline/access before project registration;
- [ ] robust atomic state writes + append-only event locking;
- [ ] execution lease acquire/renew/reconcile;
- [ ] project registry on dedicated runner;
- [ ] per-project credential/access isolation;
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

- [ ] consume accepted project baseline as bounded source context;
- [ ] project-local Definition persistence workflow;
- [ ] one-question interactive protocol proof on desktop/mobile;
- [ ] explicit acceptance write path;
- [ ] contradiction → reopen → reaccept → execution continuation proof;
- [ ] consistency/convergence checks.

## Launch / release governance runtime

The governance invariant is already part of the foundation. Runtime persistence/enforcement comes when project state/execution plumbing is implemented.

- [ ] project-local Launch Definition persistence/version lineage;
- [ ] explicit `RELEASE_SCOPE_FROZEN` binding for release-scoped executions;
- [ ] durable `LAUNCH_BLOCKER` / `POST_LAUNCH` / `EVIDENCE_REQUIRED` classification events;
- [ ] project-local post-launch backlog routing without release-scope mutation;
- [ ] Worker `RELEASE_READY` transition when all frozen launch criteria PASS;
- [ ] explicit reopen event requiring reason/consequence and renewed acceptance;
- [ ] convergence test proving subjective improvement alone cannot block a satisfied release gate;
- [ ] post-launch evidence loop integration where project/product metrics exist.

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
