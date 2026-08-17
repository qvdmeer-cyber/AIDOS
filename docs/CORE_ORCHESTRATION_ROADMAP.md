# Core orchestration expansion roadmap

This roadmap covers the new AIDOS-core concepts for multi-project/multi-workstream orchestration, remote control, Human Input Requests, progress/ETA and portfolio insights. It is additive to the existing Bridge roadmap and must preserve proven runtime semantics.

## Architecture/contracts now present

- [x] one AIDOS managing multiple isolated project instances;
- [x] durable Workstream schema with scope ownership, shared contracts, dependency graph, blockers, resource claims and integration gates;
- [x] actor-role abstraction (`THINKER`, technical `WORKER`, `HUMAN`) while preserving current concrete Agent names/identities;
- [x] AIDOS-owned control-flow invariant;
- [x] Human Input Request schema independent of chat/session;
- [x] control-intent schema for run/pause/resume/safe-stop/status/input/recovery;
- [x] progress/ETA schema with confidence and actual-vs-estimated outcome;
- [x] system-insight schema separating Observation/Hypothesis/Adopted Improvement;
- [x] future external Interface boundary documented as replaceable client layer.

## Runtime implementation required

### Workstreams

- [ ] project-level workstream decomposition/planning;
- [ ] project-local workstream persistence;
- [ ] dependency-aware scheduler;
- [ ] workstream-specific Thinker/Worker activation;
- [ ] cross-workstream change/replan events;
- [ ] shared-contract invalidation/revalidation;
- [ ] shared-resource lease manager;
- [ ] integration-gate lifecycle;
- [ ] concurrent-workstream crash/recovery reconciliation.

### Control plane

- [ ] durable control-intent processor;
- [ ] safe-boundary `RUN`, `PAUSE`, `RESUME`, `SAFE_STOP` semantics;
- [ ] status/blocker/recovery query projection;
- [ ] audit/reject invalid control intent;
- [ ] external client authentication/authorization;
- [ ] no direct process/project-file manipulation by clients.

### Human Input Requests

- [ ] publish durable request from genuine human boundary;
- [ ] channel-independent presentation;
- [ ] exact binding validation on response;
- [ ] response/resolution event;
- [ ] deterministic next-actor selection;
- [ ] map current `WAITING_USER` to exact waiting request(s);
- [ ] prove continuity across session rotation and device/channel changes.

### Progress / ETA / insights

- [ ] weighted progress from Definition/workstream/dependency/validation/integration evidence;
- [ ] probabilistic ETA with confidence/range;
- [ ] persist estimated versus actual remaining time;
- [ ] project/portfolio telemetry aggregation;
- [ ] human-attention reason/maturity trend;
- [ ] Observation → Hypothesis → explicit adoption workflow.

## Proven semantics that must not regress

- exact project/root/preparation/execution/revision binding;
- execution leases and crash reconciliation;
- deterministic execution validation before review;
- canonical review assignment/response/consume/cleanup;
- fail-closed tamper/identity handling;
- supervised interactive-session gating;
- durable event/state recovery and disposable GPT/Codex sessions.

## Explicit non-scope

This does **not** implement the external AIDOS Interface UI and does not start a separate Interface project. The future Interface consumes Core status/control/Human Input/event contracts only.
