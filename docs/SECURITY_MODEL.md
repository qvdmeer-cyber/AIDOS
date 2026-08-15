# Security and authority model

## Principle

Prefer **high autonomy inside a small technical boundary** over unrestricted autonomy across the entire runner.

A dedicated machine reduces accidental exposure but is not itself a sufficient authorization boundary.

## V1 execution posture

Default:

- dedicated Windows runner;
- non-admin development user where practical;
- exact project root binding;
- Codex workspace/project-scoped write access;
- automatic review/approval only inside that boundary;
- explicit network/deployment capability per project;
- bridge configuration/credentials not writable by project Codex processes;
- secrets excluded from repositories, event logs and review artefacts.

`danger-full-access` over the entire host is not the normal V1 profile.

## Evolution path

Preferred later architecture:

```text
host runner
├─ isolated Project A runtime
│   └─ Codex may receive broad/full access inside that runtime
└─ isolated Project B runtime
    └─ Codex may receive broad/full access inside that runtime
```

## Hard stop boundaries

Unless already and explicitly authorized by the active execution, stop before:

- destructive/non-reversible remote actions;
- new production write authority;
- credentials/secrets handling outside the approved route;
- filesystem access outside bound roots;
- sibling-project modifications;
- unapproved schema/data destruction;
- new external infrastructure/service authority;
- material security/privacy behaviour changes.

## Windows lock policy

Two policies are supported conceptually:

- `SUPERVISED`: a locked Windows session prevents the next interactive GPT step; running Codex may finish its current bounded execution and publish state/evidence.
- `UNATTENDED_ALLOWED`: intended for a dedicated proven runner; the bridge may continue interactive orchestration according to its configured trigger mechanism.

Lock/unlock never changes scope or execution state by itself. It only controls whether the next interactive orchestration step may start.
