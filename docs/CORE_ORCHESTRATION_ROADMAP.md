# Core orchestration expansion roadmap

This roadmap covers additive AIDOS-core capabilities for multi-project/multi-workstream orchestration, Auto Define, remote control, Human Input Requests, progress/ETA and portfolio insights. Proven Bridge semantics remain authoritative while newer orchestration layers are integrated.

## Architecture/contracts now present

- [x] one AIDOS managing multiple isolated project instances;
- [x] durable Workstream schema with scope ownership, shared contracts, dependency graph, blockers, resource claims and integration gates;
- [x] actor-role abstraction (`THINKER`, technical `WORKER`, `HUMAN`) while preserving current concrete Agent identities;
- [x] AIDOS-owned control-flow invariant;
- [x] Human Input Request schema independent of chat/session;
- [x] control-intent schema for run/pause/resume/safe-stop/status/input/recovery;
- [x] progress/ETA schema with confidence and actual-vs-estimated outcome;
- [x] system-insight schema separating Observation/Hypothesis/Adopted Improvement;
- [x] future external Interface boundary documented as replaceable client layer;
- [x] shared Decision Governance authority taxonomy through AIDOS-Contracts;
- [x] confidence/reversibility/impact/authority fail-closed Auto Define policy;
- [x] first-class durable Definition `AUTO_DECISION` writepath and supersession lineage;
- [x] deterministic single-decision and Definition decision-lineage validation;
- [x] unified Definition readiness validator combining progress/applicability/decision integrity;
- [x] Human Input escalation semantics for failed Auto Define assessments;
- [x] Auto Define telemetry/learning model and durable aggregate schema;
- [x] Builder-owned authority-aware Project Baseline Auto Define under the same shared policy.

## Runtime implementation required

### Auto Define orchestration

Contracts/tools exist; the runtime still needs to make them an automatic actor loop rather than a manually invoked capability.

- [ ] Definition Thinker emits/records Decision Assessments for unresolved concerns;
- [ ] runtime evaluates assessment against shared Contracts policy and rejects policy drift/failure;
- [ ] fixed-point Auto Define loop automatically resolves system/repository/eligible auto decisions until convergence;
- [ ] automatic durable Human Input Request publication when the next concern is human-required;
- [ ] exact Human Input response → Definition Thinker reactivation → fresh fixed-point pass;
- [ ] automatic surface/applicability updates bound to system/repo/auto/human resolutions;
- [ ] automatic current Auto Decision lineage validation before `USER_REVIEW`;
- [ ] supersession/reopen path triggered by new evidence, Definition changes and human override;
- [ ] durable Auto Define event/metric aggregation and `auto-define-evaluation` production;
- [ ] status/control boundary exposes explainability fields without giving an Interface decision authority;
- [ ] regression proof that final Definition acceptance remains human and cannot be auto-applied.

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
- durable event/state recovery and disposable GPT/Codex sessions;
- explicit human acceptance for Baseline/Definition/release gates;
- contracts/governance are not project-overridable.

## Explicit non-scope

This does **not** implement the external AIDOS Interface UI and does not start a separate Interface project. A future Interface consumes Core status/control/Human Input/decision-explainability/event contracts only.
