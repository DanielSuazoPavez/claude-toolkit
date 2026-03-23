---
name: idea-20260320-exploration-claude_code_channels
description: Exploration idea — Claude Code Channels (Telegram/Discord) for remote session access without extra API costs
type: idea
---

**NOTE**: ONLY READ WITH USER EXPLICIT PERMISSION

## 1. Quick Reference

Claude Code Channels is the path for remote session access. Research preview, setup is straightforward, but permission-unblock problem remains.

## 2. Concept

Remote access to Claude Code sessions running on local PC, from phone/browser, without per-token API costs.

### Use case spectrum

1. **Check in** — see what a session found, read results from phone
2. **Unblock** — approve permissions remotely so background work doesn't stall
3. **Always-on assistant** — a session managing personal knowledge (Obsidian), triaging incoming items, staying available

## 3. Research findings (2026-03-20)

### Decision: Claude Code Channels

Official Anthropic feature. Separate plumbing from `claude remote-control`. Channels push events *into* a running session (messages arrive as MCP events). Uses CLI subscription.

### Channels vs Remote Control

| Feature | Direction | Best for |
|---------|-----------|----------|
| Remote Control | You push prompts to session | Steering from another device |
| Channels | External events push into session | Reacting to messages/webhooks while away |

### Setup (Telegram)

1. BotFather → `/newbot` → copy token
2. `/plugin install telegram@claude-plugins-official`
3. `/telegram:configure <token>`
4. Restart: `claude --channels plugin:telegram@claude-plugins-official`
5. Pair via code, set allowlist

Quick local test: `fakechat` plugin → `http://localhost:8787`

### What works / what doesn't

| Use case | Status |
|----------|--------|
| Check in from phone | Works — messages push into session |
| Unblock permissions | **Doesn't work** — session pauses until local approval (only `--dangerously-skip-permissions` bypasses) |
| Always-on assistant | Possible but session must stay open |

### Claw ecosystem — ruled out

OpenClaw, ZeroClaw, PicoClaw, NanoClaw, NullClaw all require API keys with per-token billing. Anthropic banned subscription OAuth tokens for third-party tools — accounts suspended.

### Prerequisite: permission design

The permission-unblock problem is solvable by designing tighter allow/deny permissions so Claude rarely needs to ask. Tracked separately in backlog as `permission-design`.

### Status

Research preview — syntax may change, only official plugins allowed for now.
