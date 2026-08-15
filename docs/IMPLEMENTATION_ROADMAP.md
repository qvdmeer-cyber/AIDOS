# Initial implementation roadmap

This roadmap is implementation sequencing for the private AIDOS runtime.

## External project-preparation prerequisite

Project preparation is intentionally outside this repository:

- `qvdmeer-cyber/AIDOS-Contracts` owns deterministic Project Baseline, Discovery Authority and Discovery Closure/Current Product State contracts;
- `qvdmeer-cyber/AIDOS-Builder` owns distributable Project Baseline + Existing Project Discovery procedures;
- accepted baseline/evidence/discovery/current-product-state truth remains in each project repository.

AIDOS runtime onboarding requires:

```text
NEW_PROJECT
→ accepted compatible Project Baseline

EXISTING_PROJECT
→ accepted compatible Project Baseline
→ Evidence Inventory 0.2
→ accepted Discovery Closure / CPS 0.2
→ discovery state ACCEPTED
→ zero open discovery blockers
```

## Foundation — current

- [x] repository responsibility and architectural boundaries;
- [x] generic Definition/Worker/Execution agent contracts;
- [x] Definition, execution, review, interruption and learning protocols;
- [x] existing-project CPS gate before Definition;
- [x] **Discovery Closure** principle: primary repo is discovery root, not product boundary;
- [x] recursive material first-party component/dependency closure;
- [x] separate Discovery Authority vs Execution Authority;
- [x] public passive runtime observation required when reasonably reachable;
- [x] `NOT_OBSERVED` no longer closes observation-required runtime;
- [x] `DISCOVERY_REFRESH_REQUIRED` preserves old CPS/evidence and reopens missing branches;
- [x] delta-based Definition rule for existing products;
- [x] execution schema binds CPS/discovery contract versions;
- [x] launch/release governance and `RELEASE_READY` invariant;
- [x] project/state/execution schemas updated for discovery preparation bindings;
- [x] project bootstrap differentiates `NEW_PROJECT` / closure-compatible `EXISTING_PROJECT`;
- [x] review artefact lifecycle/security/session/concurrency/recovery principles.

## Bridge MVP

- [ ] validate accepted AIDOS-Contracts baseline/access before project registration;
- [ ] for `EXISTING_PROJECT`, validate Evidence Inventory 0.2 + CPS/discovery catalog 0.2 + discovery state ACCEPTED;
- [ ] reject open discovery blockers/material closure gaps at registration/dispatch;
- [ ] persist preparation snapshot identity and contract versions in runtime binding;
- [ ] detect a newly exposed material first-party/runtime branch and transition to `DISCOVERY_REFRESH_REQUIRED`;
- [ ] preserve execution evidence for Builder refresh without allowing Worker to rewrite CPS;
- [ ] robust atomic state writes + append-only event locking;
- [ ] execution lease acquire/renew/reconcile;
- [ ] project registry on dedicated runner;
- [ ] per-project credential/access isolation;
- [ ] keep discovery-read credentials/authority distinct from execution-write credentials/authority;
- [ ] Codex CLI start/resume wrapper and JSON event capture;
- [ ] session rotation;
- [ ] multi-project scheduler + heavy-job semaphore;
- [ ] review-ref publish/consume/cleanup;
- [ ] crash/restart recovery reconciler;
- [ ] telemetry + compact status view.

## Discovery Closure integration proof

External Builder/Contracts implement the closure procedure; AIDOS Core must prove the gates/interruption path.

- [ ] onboarding rejects an accepted CPS created under an older incompatible discovery contract;
- [ ] onboarding rejects `DISCOVERY_REFRESH_REQUIRED`;
- [ ] execution rejects a CPS binding whose id/commit/version does not match project state;
- [ ] Worker review detects omitted `FIRST_PARTY_MATERIAL` component and routes to discovery refresh;
- [ ] Worker review detects missing reasonably observable public runtime and routes to discovery refresh;
- [ ] expected product change caused by execution does **not** falsely trigger discovery refresh;
- [ ] after Builder accepts refreshed CPS, unchanged Definition can resume when its delta remains consistent;
- [ ] Definition reopens only when refreshed current state materially affects desired delta.

## GPT desktop integration proof

- [ ] register exact Worker/Conversation chat locator per project;
- [ ] trigger correct Worker chat from `REVIEW_READY` without periodic polling;
- [ ] identity mismatch fail-closed test;
- [ ] foreground/minimized/closed app tests;
- [ ] Windows locked → `WAITING_INTERACTIVE_SESSION` proof in supervised mode;
- [ ] unlock/resume behaviour;
- [ ] end-to-end Worker review → Git state → Codex continuation proof.

## Definition Agent integration

- [ ] consume accepted Project Baseline as bounded source context;
- [ ] consume closure-compatible accepted CPS for `EXISTING_PROJECT`;
- [ ] prove Definition asks only for desired delta;
- [ ] project-local Definition persistence;
- [ ] one-question interactive protocol proof desktop/mobile;
- [ ] explicit acceptance write path;
- [ ] contradiction → distinguish product Definition issue vs Discovery Closure issue;
- [ ] consistency/convergence checks.

## Launch / release governance runtime

- [ ] project-local Launch Definition persistence/version lineage;
- [ ] explicit `RELEASE_SCOPE_FROZEN` execution binding;
- [ ] durable `LAUNCH_BLOCKER` / `POST_LAUNCH` / `EVIDENCE_REQUIRED` events;
- [ ] post-launch backlog routing without release-scope mutation;
- [ ] Worker `RELEASE_READY` transition when frozen criteria PASS;
- [ ] explicit reopen event requiring reason/consequence and renewed acceptance;
- [ ] test that subjective improvement alone cannot block a satisfied release gate;
- [ ] post-launch evidence-loop integration where metrics exist.

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
