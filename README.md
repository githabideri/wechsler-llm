# wechsler-llm

Ops + infrastructure toolkit for a **multi‑container LXC LLM stack** (Proxmox‑first, portable elsewhere).

This repo isn’t an app — it’s the **glue**: configs, scripts, and runbooks that keep a distributed local LLM stack consistent, reproducible, and safe to update.

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

## Intended Use

### 1) With OpenClaw + localbot-ctl (full stack)
Use this repo as the ops layer that powers LocalBot:

- `localbot-ctl` handles commands (`/lbm`, `/lbe`, etc.)
- **wechsler-llm** provides the backend plumbing:
  - llama-swap configs
  - LMCache setup
  - power control (WoL + shutdown)
  - update runbooks

➡️ Result: LocalBot gets model switching + caching + power awareness.

### 2) Standalone / generic use
If you don’t run OpenClaw at all, this repo still works:

- Run llama-swap for GGUF model switching
- Run vLLM + LMCache for persistent prefix caching
- Use the power scripts independently
- Follow runbooks for updates and maintenance

➡️ Result: portable ops toolkit for any multi-container LLM setup.

## Structure

```
wechsler-llm/
├─ lmcache/       # vLLM KV-cache persistence (LMCache)
├─ llama-swap/    # llama.cpp model switching configs
├─ power/         # GPU WoL + shutdown scripts
├─ openclaw/      # patches + update playbooks
├─ runbooks/      # upgrade/rollback/checklists
└─ docs/          # architecture notes
```

## Status

Active. Evolving as the stack grows.
