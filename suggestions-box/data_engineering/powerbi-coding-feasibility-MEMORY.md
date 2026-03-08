# Power BI via Code: Feasibility Summary

## Context

Evaluated how much of "creating Power BI dashboards" can be done without Power BI Desktop — ie, programmatically from Claude Code or similar tools.

## The Short Answer

The **data model layer is fully programmable**. The **report visual layer still needs a GUI for initial creation**, but can be templated and tweaked via code after that.

## What's Fully Doable via Code

### Semantic Model (the heavy lifting, ~70-80% of the work)

- Tables, columns, relationships, hierarchies
- DAX measures (create, validate, troubleshoot)
- Power Query / M expressions
- Row-level security (RLS)
- Calculation groups, perspectives
- Best practice validation
- Deploy to Fabric workspaces
- TMDL import/export (human-readable, Git-friendly model definitions)

### Operations & CI/CD

- Publish/deploy via REST APIs
- Refresh scheduling and triggering
- Workspace management
- Git integration (Azure DevOps, GitHub) with bidirectional sync
- CI/CD pipelines with quality gates
- Deployment pipelines (dev/test/prod promotion)

### Querying & Analysis

- Execute DAX queries against models
- Python access via `sempy` / `semantic-link-labs` in Fabric notebooks
- Paginated reports (RDL is XML, fully generatable)

### Embedding

- Embed reports in custom apps via JS client API (`powerbi-client`)
- Programmatic filtering, slicers, events, bookmarks

## What Still Needs a GUI

- **Visual report design from scratch** — chart types, layout, positioning, interactions
- **Custom visual configuration** — marketplace visual property panes
- **Visual Power Query editor** — the step-by-step builder (raw M works in code)
- **Report theme live preview**

**However**: once a report exists, its PBIR format (JSON files, one per visual/page) is diffable and editable. You can template a base report and programmatically stamp out variations (swap measures, duplicate pages, adjust filters).

## Key Tool: Power BI Modeling MCP Server

Microsoft's official MCP server: [github.com/microsoft/powerbi-modeling-mcp](https://github.com/microsoft/powerbi-modeling-mcp)

- Runs locally, exposes 20+ tool categories to AI agents
- Connects via TOM / ADOMD.NET to:
  - Power BI Desktop (local AS instance)
  - Fabric Workspaces (cloud)
  - PBIP folders (file-based TMDL)
- People are already using it with Claude Code (see [Reddit thread](https://www.reddit.com/r/PowerBI/comments/1rj7kv8/ive_been_using_claude_code_power_bi_mcp_server/))

Microsoft also has a **Remote MCP server** for querying existing models with Copilot-powered DAX generation.

## The Spectrum

1. Everything by hand in Desktop — old world
2. Model via code, visuals by hand — what the MCP enables now
3. Model via code, visuals templated/tweaked via code, initial layout by hand — what PBIR enables
4. Everything via code — not there yet

## Next Steps

- Set up the Power BI Modeling MCP server with Claude Code
- Evaluate workflow: model in code, create base report template in Desktop, iterate visuals via PBIR JSON
- Explore `semantic-link-labs` for Python-based model management in Fabric notebooks

## Key Sources

- [Power BI Modeling MCP - GitHub](https://github.com/microsoft/powerbi-modeling-mcp)
- [Power BI MCP Servers Overview - Microsoft Learn](https://learn.microsoft.com/en-us/power-bi/developer/mcp/mcp-servers-overview)
- [TMDL Overview - Microsoft Learn](https://learn.microsoft.com/en-us/analysis-services/tmdl/tmdl-overview)
- [PBIR Format Transition - Power BI Blog](https://powerbi.microsoft.com/en-us/blog/pbir-will-become-the-default-power-bi-report-format-get-ready-for-the-transition/)
- [Tabular Editor + MCP](https://tabulareditor.com/blog/ai-agents-that-work-with-power-bi-semantic-model-mcp-servers)
- [semantic-link-labs - GitHub](https://github.com/microsoft/semantic-link-labs)
