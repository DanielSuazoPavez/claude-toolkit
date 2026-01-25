# Philosophy: Reducing Entropy

## Core Question

> "What does the codebase look like *after*?"

Measure changes by the final code amount, not implementation effort. A refactor that takes 2 hours but removes 500 lines is better than a 30-minute change that adds 50.

## Three Questions Before Any Change

1. **Smallest viable codebase?** What's the minimum code needed to solve this? Not the minimum *change*, the minimum *result*.

2. **Net code reduction?** Does this change result in less total code? "Better organized but more code" = more entropy.

3. **What can be deleted?** Every change is an opportunity to remove obsolete code. Take it.

## Red Flags

- **Status quo bias**: "Keep what exists" without questioning if it should exist
- **Over-engineering**: Building for flexibility you don't need
- **Unnecessary abstraction**: Layers that don't pay for themselves
- **Type safety theater**: Complex types that don't prevent real bugs
- **Readability bloat**: Comments and structure that add lines without clarity

## Bias Toward Deletion

When in doubt, delete. Code that doesn't exist:
- Has no bugs
- Needs no tests
- Requires no documentation
- Never confuses anyone

## When This Doesn't Apply

- Framework-driven projects with conventions (follow the framework)
- Regulatory/compliance requirements (keep what's required)
- Code that's genuinely minimal already

## The Uncomfortable Truth

> "The proposed change should result in less total code. 'Better organized' but more code equals more entropy."

Most "refactors" add code. Question whether that's actually improvement.
