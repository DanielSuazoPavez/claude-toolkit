# Mermaid Theme Presets

Copy-paste these at the top of your diagram. All use `base` theme (the only one that supports `themeVariables` customization).

Two syntax options shown — frontmatter (cleaner) and inline directive (works everywhere).

## Documentation

High contrast, neutral blues/grays. Works in both light and dark GitHub/VS Code themes.

**Frontmatter:**
```yaml
---
config:
  theme: base
  themeVariables:
    primaryColor: '#4a90d9'
    primaryTextColor: '#fff'
    primaryBorderColor: '#2a6ab0'
    lineColor: '#666'
    secondaryColor: '#e8f0fe'
    tertiaryColor: '#f5f5f5'
---
```

**Inline directive:**
```
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#4a90d9', 'primaryTextColor': '#fff', 'primaryBorderColor': '#2a6ab0', 'lineColor': '#666', 'secondaryColor': '#e8f0fe', 'tertiaryColor': '#f5f5f5'}}}%%
```

## Design Review

Softer palette, muted tones. Keeps focus on structure rather than color.

**Frontmatter:**
```yaml
---
config:
  theme: base
  themeVariables:
    primaryColor: '#7b8794'
    primaryTextColor: '#1a1a1a'
    primaryBorderColor: '#5a6672'
    lineColor: '#999'
    secondaryColor: '#e2e8f0'
    tertiaryColor: '#f8f9fa'
---
```

**Inline directive:**
```
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#7b8794', 'primaryTextColor': '#1a1a1a', 'primaryBorderColor': '#5a6672', 'lineColor': '#999', 'secondaryColor': '#e2e8f0', 'tertiaryColor': '#f8f9fa'}}}%%
```

## Presentation

Bold, high visibility. Strong contrast and larger font for slides or screen sharing.

**Frontmatter:**
```yaml
---
config:
  theme: base
  themeVariables:
    primaryColor: '#2563eb'
    primaryTextColor: '#fff'
    primaryBorderColor: '#1e40af'
    lineColor: '#1e40af'
    secondaryColor: '#dbeafe'
    tertiaryColor: '#eff6ff'
    fontFamily: 'sans-serif'
---
```

**Inline directive:**
```
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#2563eb', 'primaryTextColor': '#fff', 'primaryBorderColor': '#1e40af', 'lineColor': '#1e40af', 'secondaryColor': '#dbeafe', 'tertiaryColor': '#eff6ff', 'fontFamily': 'sans-serif'}}}%%
```
