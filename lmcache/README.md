# LMCache Setup (vLLM)

Persistent KV cache for the vLLM container.

## Status
**WORKING** (verified 2026-02-10)

## Config

**Location:** `/etc/lmcache.yaml`

```yaml
chunk_size: 256
local_cpu: true
max_local_cpu_size: 4      # GB
reserve_local_cpu_size: 0
local_disk: /var/lib/lmcache
max_local_disk_size: 50    # GB
use_layerwise: false
save_decode_cache: false
```

## vLLM Service

**Location:** `/etc/systemd/system/vllm.service`

```ini
[Service]
User=vllmuser
Environment=VLLM_USE_V1=1
Environment=LMCACHE_CONFIG_FILE=/etc/lmcache.yaml
ExecStart=/home/vllmuser/.venv/bin/vllm serve cyankiwi/Qwen3-VL-4B-Instruct-AWQ-4bit \
  --host 0.0.0.0 --port 8000 \
  --max-model-len 12288 \
  --gpu-memory-utilization 0.9 \
  --kv-transfer-config '{"kv_connector":"LMCacheConnectorV1","kv_role":"kv_both"}'
```

## Test Results

Same prompt twice:
- **Cold:** 3.24s
- **Warm (cached):** 0.08s

## Health Check

```bash
ssh vllm 'curl -s http://localhost:8000/v1/models'
# Returns 200 when ready
```

Note: `/health` endpoint doesn't respond in this vLLM build.

## Troubleshooting

**GPU memory stuck:** If vLLM fails with "not enough GPU memory" but nvidia-smi shows no processes, the GPU state is stale. Either:
- Kill all vllm processes and restart
- Reboot the GPU host if persists

**max_model_len too high:** Lower it if KV cache allocation fails.
