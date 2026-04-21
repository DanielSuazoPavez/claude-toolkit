---
name: build-communication-style
metadata: { type: command }
description: Build or refine a communication style doc through guided discovery. Use when setting up Claude's voice, tuning tone, or customizing how Claude communicates. Keywords: communication, style, tone, voice, preferences.
argument-hint: "[refine]"
allowed-tools: Read, Write, Edit, Glob, AskUserQuestion
---

Build or refine a `.claude/docs/essential-preferences-communication_style.md` file through guided discovery.

**See also:** `/snap-back` (reset tone mid-session), `/brainstorm-feature` (discovery process reference)

## When to Use

- New user wants Claude to stop sounding like customer service
- User has a style doc but wants to tune specific dimensions
- Setting up a project for the first time and wants to define how Claude communicates

## Process

### 1. Detect Mode

Check if `.claude/docs/essential-preferences-communication_style.md` (or similar) exists.

- **Exists** → Read it, enter refinement mode (step 4)
- **Doesn't exist** → Enter creation mode (step 2)
- **`$ARGUMENTS` contains "refine"** → Force refinement mode even if no doc exists yet

### 2. Example-Driven Calibration (creation mode)

Show **one pair at a time**. Each pair shows two Claude responses to the same scenario — contrasting styles. Ask the user which they prefer (A, B, somewhere between, neither).

Use 3-4 pairs covering different dimensions. Examples:

**Pair 1 — Ceremony vs Directness:**
> Scenario: User asks to fix a bug in a function
>
> **A:** "I'd be happy to help you fix that bug! Let me take a look at the function. I can see the issue — here's what's happening and how we can fix it: [explanation + code]"
>
> **B:** [reads file, fixes bug, shows diff] "Off-by-one in the loop bound."

**Pair 2 — Verbosity:**
> Scenario: User asks why a test is failing
>
> **A:** "The test fails because `parse_config` returns `None` when the file is empty, but the test expects an empty dict. Three options: [detailed breakdown of each with tradeoffs]"
>
> **B:** "`parse_config` returns `None` on empty file, test expects `{}`. Fix the function or the test?"

**Pair 3 — Disagreement:**
> Scenario: User suggests an approach that has a known issue
>
> **A:** "That'll work! Here's the implementation..." [builds what was asked]
>
> **B:** "That approach has a race condition when concurrent requests hit the cache. Want me to show why, or would you prefer I just build it with a lock?"

**Pair 4 — After a mistake:**
> Scenario: Claude gave wrong advice and user corrected it
>
> **A:** "I apologize for the confusion in my previous response. You're absolutely right that the API uses POST, not GET. Let me correct my approach and provide the right solution..."
>
> **B:** "You're right, it's POST. Updated."

### 3. Adaptive Dimension Walk

Based on calibration responses, identify which dimensions the user has strong opinions about. Dig deeper on those, quick pass on the rest.

**Core dimensions:**

| Dimension | What to ask |
|-----------|-------------|
| **Tone** | Formal ↔ casual ↔ terse |
| **Verbosity** | Explain reasoning ↔ show results only |
| **Ceremony** | Greetings/summaries/transitions ↔ straight to action |
| **Disagreement** | Defer to user ↔ push back when wrong |
| **Anti-patterns** | What phrases or behaviors to avoid (negative signals) |
| **Positive signals** | What behaviors to keep doing |

For each dimension the user leans into:
- Ask one follow-up question to get specifics
- Capture both what TO do and what NOT to do

For neutral dimensions: note the calibration result and move on.

**One question per message. Multiple choice when possible.**

### Handling Ambiguous or Conflicting Responses

When the user gives vague feedback ("both are fine", "somewhere in between") or contradicts themselves across dimensions:

**Ambiguous:** Reframe with a concrete scenario that forces a choice.
> User: "I like both A and B"
>
> Claude: "Let's make it concrete — you just pushed a broken migration and need help fast. Do you want me to explain what went wrong first, or just show the fix and explain after if you ask?"

**Conflicting:** Name the tension and let them resolve it.
> User said they want terse responses (Pair 1) but also detailed tradeoff breakdowns (Pair 2)
>
> Claude: "You lean terse for actions but detailed for decisions — should I default to brief and only expand when there's a real choice to make?"

**"I don't know":** Offer a sensible default they can adjust later.
> Claude: "Most people find a middle ground works — brief by default, detailed when it matters. I'll use that as the baseline and you can refine after trying it."

Don't push for precision on dimensions the user is genuinely neutral about — a reasonable default is better than a forced choice.

### 4. Refinement Mode

When an existing doc is found:
1. Show current doc sections briefly
2. Ask: "What's working well? What's not?"
3. Targeted questions on problem areas only
4. Can add/remove/modify specific sections without regenerating everything

### 5. Generate the Doc

Synthesize responses into the doc format:

```markdown
# Communication Style Preferences

## 1. Quick Reference

**MANDATORY:** Read at session start - affects all interactions.

[One-line summary of the user's style]

> **The Test**: [A concrete heuristic the user can use to check Claude's tone]

---

## 2. Effective Working Patterns

[Positive signals — what TO do, organized by theme]

---

## 3. Anti-Patterns

| Pattern | Instead |
|---------|---------|
| ... | ... |

---

## 4. When [Softer Tone] IS Appropriate

| Situation | Response |
|-----------|----------|
| ... | ... |

---

## 5. Key Principle

[The single most important guiding principle from the discovery]
```

**Before writing:**
- Show the generated doc to the user
- Ask if anything needs adjustment
- Confirm save location (default: `.claude/docs/essential-preferences-communication_style.md`)

**After writing:**
- Explain that `essential-*` docs are loaded at session start automatically (if session-start hook is configured)
- If no session-start hook exists, mention they may need to set one up

## Key Principles

- **One question per message** — don't overwhelm
- **Concrete over abstract** — examples, not theory
- **Both signals** — what to do AND what not to do
- **User's voice, not yours** — discover their preferences, don't project
- **Non-programmers welcome** — scenarios should be general enough for any Claude Code user

## Mid-Process Restart

If the user wants to start over or abandon mid-discovery:
- **"Start over"** → Discard collected preferences, return to step 2
- **"This isn't working"** → Ask what feels off — often they want to skip calibration and just describe what they want directly. Let them.
- **"Just give me something"** → Generate a reasonable default doc based on whatever you've collected so far, explicitly mark it as a starting point for `/build-communication-style refine` later

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Survey Mode** | Rapid-fire questions feels like a form | One question at a time, react to answers |
| **Projecting Preferences** | Assuming the user wants terse/direct because most devs do | Let calibration reveal actual preferences |
| **Skipping Positive Signals** | Only capturing "don't do X" | Explicitly ask what TO keep doing |
| **Overlong Doc** | 200-line style doc nobody reads | Keep it under 80 lines — Quick Reference must fit in a glance |
| **Generic Output** | Doc that could apply to anyone | Include user-specific examples and language from the conversation |
