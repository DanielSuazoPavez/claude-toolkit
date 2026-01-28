---
name: design-diagram
description: Use when requests mention "diagram", "visualize", "flow", "architecture", "model", or "map out".
---

# Mermaid Diagramming

Create professional software diagrams using Mermaid's text-based syntax.

## Expert Guidance: Which Diagram Type?

| Audience | Time to Create | Maintenance | Recommended Type |
|----------|----------------|-------------|------------------|
| Developer (self) | 5 min | Update with code | Flowchart, Sequence |
| Team review | 15 min | Monthly | Class, ERD |
| External stakeholders | 30 min | Quarterly | C4 Context/Container |
| Documentation | 10 min | With releases | Sequence, State |

**Rule:** Match diagram complexity to how often it will be viewed and updated. Over-detailed diagrams become stale.

## When to Use Which

```
What are you showing?
├─ Data relationships → ERD
├─ Object structure → Class Diagram
├─ Time-based flow → Sequence Diagram
├─ Process/algorithm → Flowchart
├─ System boundaries → C4 Diagram
└─ State transitions → State Diagram
```

## Expert Decision Patterns

### Subgraphs vs. Separate Diagrams

| Situation | Use Subgraphs | Use Separate Diagrams |
|-----------|---------------|----------------------|
| Same process, different phases | Yes | - |
| Related but independent flows | - | Yes |
| Total nodes < 20 | Yes | - |
| Different audiences need different views | - | Yes |
| Cross-cutting concerns (auth, logging) | - | Yes (reference diagram) |

### When Multiple Diagram Types Apply

1. **Start with the question you're answering**: "How does data flow?" = Sequence. "What are the relationships?" = ERD/Class.
2. **Combine strategically**: C4 Context + Sequence for "what talks to what" + "how they talk"
3. **Default order for new systems**: C4 Context → ERD → Sequence → Class (broad to narrow)

### Evolving Requirements

- **Early design**: Keep diagrams informal (flowcharts, hand-drawn style notes)
- **Stabilizing**: Formalize with proper notation; add to version control
- **Production**: Diagrams live next to code they describe (`docs/architecture/` or inline)

### Versioning Strategy

```
docs/diagrams/
├── auth-flow.mmd           # Current version (no suffix)
├── auth-flow-v1.mmd        # Legacy preserved for reference
└── auth-flow-proposed.mmd  # Under review (delete after decision)
```

**Tip**: Include `%% Last updated: YYYY-MM-DD` comment for staleness detection.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **The Kitchen Sink** | 50+ nodes, unreadable | Split into multiple diagrams |
| **Wrong Abstraction** | ERD for process flow | Match diagram type to content |
| **Missing Legend** | Custom notation unexplained | Add `%% Legend:` comment |
| **Dead Diagram** | Code changed, diagram didn't | Store near code, update together |
| **Over-Detailed** | Implementation details in architecture | Match detail level to audience |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Diagram not rendering | Syntax error near special chars | Escape quotes: `["Label with ""quotes"""]` |
| GitHub shows raw text | Missing blank line before fence | Add empty line before ` ```mermaid ` |
| Node labels cut off | Label too long | Use `<br>` for line breaks or shorter alias |
| Arrows overlapping | Dense layout | Add `%%{init: {'flowchart': {'nodeSpacing': 50}}}%%` |
| Notion renders differently | Older Mermaid version | Test in Mermaid Live, simplify if needed |
| VS Code preview broken | Extension version mismatch | Update Mermaid extension |
| Special chars cause errors | Parentheses, brackets unescaped | Wrap in quotes: `id["My (label)"]` |

## Rendering

Native support: GitHub, GitLab, VS Code, Notion, Obsidian

Export: [Mermaid Live Editor](https://mermaid.live) or CLI `mmdc -i input.mmd -o output.png`
