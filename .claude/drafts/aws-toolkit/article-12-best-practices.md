# Article: 12 AWS Best Practices (Asim Nasir, Feb 2026)

Source: aws.plainenglish.io (archived 2026-02-09)
Theme: Treat AWS as an automation engine, not hosting.

## Usefulness tiers for agent/skill guidance

### Tier 1 — High value (concrete, checkable, models get wrong)

- **IAM least-privilege (#10)** — Models default to `*` permissions. Auditable.
- **Security groups as code (#7)** — Models generate permissive SGs. Reviewable.
- **IaC over console (#1)** — Agent should always output IaC, never console steps.
- **Multi-account isolation (#2)** — Architect agent should factor into recommendations.

### Tier 2 — Useful embedded knowledge (remind, not teach)

- **Immutable infra / no SSH (#3)** — Good default stance for architect agent.
- **Autoscale for failure (#8)** — min-size >= 2 is checkable. May be out of scope for smaller projects.
- **Test restores (#9)** — Agent could flag backup configs lacking restore testing.
- **Cost tagging (#6)** — Enforceable: "all resources must have cost-allocation tags."

### Tier 3 — True but generic / hard to operationalize

- **Structured logging (#4)** — Application-level concern, overlaps with `skill-logging` (P100).
- **Actionable alarms (#5)** — Good philosophy, hard to enforce in agent.
- **Boring deployments (#11)** — Outcome of doing other things right.
- **AWS as automation (#12)** — Overarching philosophy, not actionable.

## Key signal

Most valuable agent behaviors = **concrete and checkable**: IAM `*` usage, SG `0.0.0.0/0`, missing tags, min-size < 2.
Reinforces `aws-security-auditor` as highest-leverage starting point.
