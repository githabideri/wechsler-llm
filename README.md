# wechsler-llm

Ops + infrastructure toolkit for a **multi‑container LXC LLM stack** (Proxmox‑first, portable elsewhere).

This repo isn't an app — it's the **glue**: configs, scripts, and runbooks that keep a distributed local LLM stack consistent, reproducible, and safe to update.

## Idea

Modern local LLM setups are **powerful but fragile**:

- multiple containers  
- multiple inference servers  
- custom patches  
- different models & routes  
- power management  

This repo keeps the operational truth in one place so upgrades are safe, changes are documented, and the stack is restartable.

## Scope

- **Proxmox LXC first**, but works on any Linux host (VM, bare metal, Docker)
- **No secrets** stored here (use env or secrets manager)
- **Composable** — each piece can be used independently

## Core Concept: Clean Backend Switching

Only one GPU-heavy backend runs at a time. Switching is:

1. **Save** active KV cache state (slots for llama-cpp, automatic for LMCache)
2. **Stop** current backend
3. **Start** new backend
4. **Restore** cached state

This ensures each backend gets full GPU resources and cache state survives switches.

## Structure

```
wechsler-llm/
├─ lmcache/       # vLLM KV-cache persistence (LMCache) ✅
├─ llama-cpp/     # llama.cpp slot persistence ✅
├─ llama-swap/    # llama.cpp model switching configs (planned)
├─ power/         # GPU WoL + shutdown scripts (planned)
├─ openclaw/      # patches + update playbooks (planned)
├─ runbooks/      # upgrade/rollback/checklists (planned)
└─ docs/          # architecture notes (planned)
```

## Intended Use

### With OpenClaw + localbot-ctl (full stack)
Use this repo as the ops layer that powers LocalBot:

- `localbot-ctl` handles chat commands (`/lbm`, `/lbe`, etc.)
- **wechsler-llm** provides the backend plumbing:
  - KV cache persistence (LMCache + llama-cpp slots)
  - Backend switching (llama-cpp ↔ vLLM)
  - Power control (WoL + shutdown)
  - Update runbooks

### Standalone / generic use
Each component works independently without OpenClaw:

- llama-cpp slot persistence for any llama.cpp deployment
- LMCache setup for any vLLM deployment
- Power scripts for any GPU server

## Status

Active. Evolving as the stack grows.
