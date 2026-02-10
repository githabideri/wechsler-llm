#!/usr/bin/env bash
set -euo pipefail

# wechsler.sh — Clean backend switching for LLM inference
#
# Usage:
#   wechsler.sh switch <llama-cpp|vllm>
#   wechsler.sh status [--json]
#   wechsler.sh save    [slot_name]
#   wechsler.sh restore [slot_name]
#
# Environment (override via env or config file):
#   GPU_HOST       — GPU server SSH host for reachability check (default: llama-cpp)
#   LLAMA_HOST     — llama-cpp SSH host (default: llama-cpp)
#   LLAMA_PORT     — llama-cpp port (default: 8080)
#   VLLM_HOST      — vllm SSH host (default: vllm)
#   VLLM_PORT      — vllm port (default: 8000)
#   SLOT_NAME      — default slot filename (default: localbot)
#   HEALTH_TIMEOUT — seconds to wait for health (default: 120)
#   SLOT_PATH      — remote path for saved slots (default: /mnt/models/cache/llama-cpp/slots)

GPU_HOST="${GPU_HOST:-llama-cpp}"
LLAMA_HOST="${LLAMA_HOST:-llama-cpp}"
LLAMA_PORT="${LLAMA_PORT:-8080}"
VLLM_HOST="${VLLM_HOST:-vllm}"
VLLM_PORT="${VLLM_PORT:-8000}"
SLOT_NAME="${SLOT_NAME:-localbot}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-120}"
SLOT_PATH="${SLOT_PATH:-/mnt/models/cache/llama-cpp/slots}"

LLAMA_URL="http://localhost:${LLAMA_PORT}"
VLLM_URL="http://localhost:${VLLM_PORT}"

log() { echo "[wechsler] $*"; }
err() { echo "[wechsler] ERROR: $*" >&2; }

# Check if GPU server is reachable via SSH
check_gpu_server() {
    ssh -o ConnectTimeout=3 -o BatchMode=yes "$GPU_HOST" "true" >/dev/null 2>&1
}

# Check if a backend is healthy (run on the target host)
check_health() {
    local host="$1" url="$2" endpoint="$3"
    ssh -o ConnectTimeout=3 "$host" "curl -sf ${url}${endpoint}" >/dev/null 2>&1
}

# Wait for a backend to become healthy
wait_healthy() {
    local host="$1" url="$2" endpoint="$3" elapsed=0
    log "Waiting for ${host} to become healthy..."
    while [ "$elapsed" -lt "$HEALTH_TIMEOUT" ]; do
        if check_health "$host" "$url" "$endpoint"; then
            log "${host} is healthy (${elapsed}s)"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    err "${host} not healthy after ${HEALTH_TIMEOUT}s"
    return 1
}

# Save llama-cpp slot to disk
save_slot() {
    local name="${1:-$SLOT_NAME}"
    log "Saving slot 0 as '${name}'..."
    local result
    result=$(ssh "$LLAMA_HOST" "curl -sf -X POST '${LLAMA_URL}/slots/0?action=save' \
        -H 'Content-Type: application/json' \
        -d '{\"filename\": \"${name}\"}'") || {
        err "Failed to save slot"
        return 1
    }
    log "Saved: ${result}"
}

# Restore llama-cpp slot from disk
restore_slot() {
    local name="${1:-$SLOT_NAME}"
    log "Restoring slot 0 from '${name}'..."
    local result
    result=$(ssh "$LLAMA_HOST" "curl -sf -X POST '${LLAMA_URL}/slots/0?action=restore' \
        -H 'Content-Type: application/json' \
        -d '{\"filename\": \"${name}\"}'") || {
        log "No saved slot '${name}' found, starting fresh"
        return 0
    }
    log "Restored: ${result}"
}

# Determine full state
get_state() {
    if ! check_gpu_server; then
        echo "gpu-offline"
        return
    fi
    if check_health "$LLAMA_HOST" "$LLAMA_URL" "/health"; then
        echo "llama-cpp"
    elif check_health "$VLLM_HOST" "$VLLM_URL" "/v1/models"; then
        echo "vllm"
    else
        echo "gpu-idle"
    fi
}

cmd_status() {
    local json_mode=false
    [ "${1:-}" = "--json" ] && json_mode=true

    local state
    state=$(get_state)

    if $json_mode; then
        local slots_json="null" saved_json="[]" gpu_json="null"

        if [ "$state" = "llama-cpp" ]; then
            slots_json=$(ssh "$LLAMA_HOST" "curl -sf ${LLAMA_URL}/slots" 2>/dev/null) || slots_json="null"
        fi

        if [ "$state" != "gpu-offline" ]; then
            # Get saved slot filenames
            saved_json=$(ssh "$LLAMA_HOST" "ls -1 ${SLOT_PATH}/ 2>/dev/null | \
                python3 -c 'import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))'" 2>/dev/null) || saved_json="[]"

            # Get GPU memory
            gpu_json=$(ssh "$GPU_HOST" "nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | \
                python3 -c '
import sys, json
gpus = []
for line in sys.stdin:
    parts = [p.strip() for p in line.split(\",\")]
    if len(parts) == 3:
        gpus.append({\"id\": int(parts[0]), \"used_mib\": int(parts[1]), \"total_mib\": int(parts[2])})
print(json.dumps(gpus))
'" 2>/dev/null) || gpu_json="null"
        fi

        cat <<EOF
{"state":"${state}","active_backend":"$([ "$state" = "llama-cpp" ] || [ "$state" = "vllm" ] && echo "$state" || echo "none")","slots":${slots_json},"saved_slots":${saved_json},"gpu_memory":${gpu_json}}
EOF
    else
        log "State: ${state}"
        case "$state" in
            gpu-offline)
                log "GPU server is not reachable"
                ;;
            gpu-idle)
                log "GPU server is up, no backend running"
                ;;
            llama-cpp)
                local slots
                slots=$(ssh "$LLAMA_HOST" "curl -sf ${LLAMA_URL}/slots" 2>/dev/null | \
                    python3 -c "import sys,json; s=json.load(sys.stdin); print(f'Slots: {len(s)}, ctx/slot: {s[0][\"n_ctx\"]}')" 2>/dev/null) || true
                [ -n "$slots" ] && log "$slots"
                ;;
            vllm)
                log "vLLM is active"
                ;;
        esac

        # Show saved slots
        if [ "$state" != "gpu-offline" ]; then
            local saved
            saved=$(ssh "$LLAMA_HOST" "ls -lh ${SLOT_PATH}/ 2>/dev/null" | grep -v ^total || true)
            if [ -n "$saved" ]; then
                log "Saved slots:"
                echo "$saved"
            else
                log "No saved slots on disk"
            fi
        fi
    fi
}

cmd_switch() {
    local target="$1"
    local state
    state=$(get_state)

    # Check GPU server is reachable
    if [ "$state" = "gpu-offline" ]; then
        err "GPU server is offline. Power it on first."
        return 1
    fi

    # Already running?
    if [ "$state" = "$target" ]; then
        log "${target} is already active"
        return 0
    fi

    # Stop current backend (with slot save if llama-cpp)
    case "$state" in
        llama-cpp)
            save_slot "$SLOT_NAME" || true
            log "Stopping llama-cpp..."
            ssh "$LLAMA_HOST" "systemctl stop llama-server" || true
            ;;
        vllm)
            log "Stopping vLLM..."
            ssh "$VLLM_HOST" "systemctl stop vllm" || true
            ;;
        gpu-idle)
            log "No backend currently active"
            ;;
    esac

    # Start target backend
    case "$target" in
        llama-cpp)
            log "Starting llama-cpp..."
            ssh "$LLAMA_HOST" "systemctl start llama-server"
            wait_healthy "$LLAMA_HOST" "$LLAMA_URL" "/health"
            restore_slot "$SLOT_NAME" || true
            ;;
        vllm)
            log "Starting vLLM..."
            ssh "$VLLM_HOST" "systemctl start vllm"
            wait_healthy "$VLLM_HOST" "$VLLM_URL" "/v1/models"
            ;;
        *)
            err "Unknown backend: ${target} (use llama-cpp or vllm)"
            return 1
            ;;
    esac

    log "Switched to ${target}"
}

cmd_stop() {
    local state
    state=$(get_state)

    case "$state" in
        llama-cpp)
            save_slot "$SLOT_NAME" || true
            log "Stopping llama-cpp..."
            ssh "$LLAMA_HOST" "systemctl stop llama-server"
            log "Stopped"
            ;;
        vllm)
            log "Stopping vLLM..."
            ssh "$VLLM_HOST" "systemctl stop vllm"
            log "Stopped"
            ;;
        gpu-idle)
            log "No backend running"
            ;;
        gpu-offline)
            log "GPU server is offline"
            ;;
    esac
}

# Main
case "${1:-help}" in
    switch)
        [ -z "${2:-}" ] && { err "Usage: wechsler.sh switch <llama-cpp|vllm>"; exit 1; }
        cmd_switch "$2"
        ;;
    status)
        cmd_status "${2:-}"
        ;;
    stop)
        cmd_stop
        ;;
    save)
        save_slot "${2:-$SLOT_NAME}"
        ;;
    restore)
        restore_slot "${2:-$SLOT_NAME}"
        ;;
    help|--help|-h)
        echo "Usage: wechsler.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  switch <llama-cpp|vllm>  Switch active backend (saves/restores slots)"
        echo "  status [--json]          Show state, GPU info, saved slots"
        echo "  stop                     Stop active backend (saves slots first)"
        echo "  save [name]              Save llama-cpp slot to disk"
        echo "  restore [name]           Restore llama-cpp slot from disk"
        ;;
    *)
        err "Unknown command: $1"
        exit 1
        ;;
esac
