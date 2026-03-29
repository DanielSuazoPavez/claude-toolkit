# Mermaid Rendering Gotchas

## Common Issues

| Issue | Fix |
|-------|-----|
| Arrows overlapping in dense diagrams | `%%{init: {'flowchart': {'nodeSpacing': 50}}}%%` |
| GitHub shows raw text instead of diagram | Add blank line before ` ```mermaid ` fence |
| Special chars break rendering | Wrap labels in quotes: `id["My (label)"]` |

## Non-Obvious Syntax Patterns

C4 diagrams use Mermaid's less documented syntax — easy to get wrong:

```mermaid
C4Context
  title System Context
  Person(user, "User", "End user of the system")
  System(app, "Application", "Core application")
  System_Ext(email, "Email Service", "Sends notifications")
  Rel(user, app, "Uses", "HTTPS")
  Rel(app, email, "Sends emails", "SMTP")
```

Subgraph scoping — nodes defined inside a subgraph are scoped; edges must reference the node ID, not the subgraph:

```mermaid
flowchart LR
  subgraph auth["Auth Service"]
    a1[Login] --> a2[Validate Token]
  end
  subgraph api["API Gateway"]
    b1[Route Request]
  end
  a2 --> b1
```

## architecture-beta Gotchas

| Issue | Fix |
|-------|-----|
| Edges render without direction | Always specify positions: `A:R -- L:B`, not `A -- B` |
| Custom icons show as blue "?" on GitHub | Use only built-in: `cloud`, `database`, `disk`, `internet`, `server` |
| Service declared before its group | Declare `group` first, then `service ... in group` |
| Edge from group boundary fails | Use `{group}` modifier on a service: `svc{group}:R --> L:other`, not on group ID |
| Groups can have icons too | `group vpc(cloud)[VPC]` — use to visually distinguish group types |
