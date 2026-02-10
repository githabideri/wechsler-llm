# llama-cpp Slot Persistence

Persistent KV cache slots for the llama-cpp container.

## Status
**WORKING** (verified 2026-02-10)

## Service

**Location:** `/etc/systemd/system/llama-server.service`

```ini
[Service]
Type=simple
WorkingDirectory=/opt/llama.cpp
ExecStart=/opt/llama.cpp/build/bin/llama-server \
  --model /mnt/models/gguf/nemotron-3-nano-30b-a3b/Nemotron-3-Nano-30B-A3B-IQ4_NL.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --ctx-size 32768 \
  --parallel 4 \
  --slot-save-path /var/lib/llama-cpp/slots \
  --reasoning-format none
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/llama-server.log
StandardError=append:/var/log/llama-server.log
```

## Slot Save/Restore API

**List slots:**
```bash
curl http://localhost:8080/slots
```

**Save slot:**
```bash
curl -X POST "http://localhost:8080/slots/0?action=save" \
  -H "Content-Type: application/json" \
  -d '{"filename": "agent-context-0"}'
```

**Restore slot:**
```bash
curl -X POST "http://localhost:8080/slots/0?action=restore" \
  -H "Content-Type: application/json" \
  -d '{"filename": "agent-context-0"}'
```

Slots are saved to `/var/lib/llama-cpp/slots/`.

## Test Results

- **Prompt processing:** ~50 tok/s
- **Generation:** ~42 tok/s
- **Save:** <1ms
- **Restore:** <1ms

## Health Check

```bash
ssh llama-cpp 'curl -s http://localhost:8080/health'
# Returns {"status":"ok"}
```

## Notes

- Context reduced to 32k (from 131k) due to GPU memory constraints when vLLM is also running
- Model auto-fits to available GPU memory (no fixed `--n-gpu-layers`)
- 4 parallel slots available for concurrent requests
