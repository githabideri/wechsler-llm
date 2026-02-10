#!/usr/bin/env bash
set -euo pipefail

# wechsler.sh — Clean backend switching for LLM inference
#
# Usage:
#   wechsler.sh switch <llama-cpp|vllm>
#   wechsler.sh status
#   wechsler.sh save    [slot_name]     # save llama-cpp slot to disk
#   wechsler.sh restore [slot_name]     # restore llama-cpp slot from disk
#
# Environment (override via env or config file):
#   LLAMA_HOST     — llama-cpp host (default: llama-cpp)
#   LLAMA_PORT     — llama-cpp port (default: 8080)
#   VLLM_HOST      — vllm host (default: vllm)
#   VLLM_PORT      — vllm port (default: 8000)
#   SLOT_NAME      — default slot filename (default: localbot)
#   HEALTH_TIMEOUT — seconds to wait for health (default: 120)

LLAMA_HOST="${LLAMA_HOST:-llama-cpp}"
LLAMA_PORT="${LLAMA_PORT:-8080}"
VLLM_HOST="${VLLM_HOST:-vllm}"
VLLM_PORT="${VLLM_PORT:-8000}"
SLOT_NAME="${SLOT_NAME:-localbot}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-120}"

LLAMA_URL="http://localhost:${LLAMA_PORT}"
VLLM_URL="http://localhost:${VLLM_PORT}"

log() { echo "[wechsler] $*"; }
err() { echo "[wechsler] ERROR: $*" >&2; }

# Check if a backend is healthy (run on the target host)
check_health() {
    local host="$1" url="$2" endpoint="$3"
    ssh "$host" "curl -sf ${url}${endpoint}" >/dev/null 2>&1
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

# Get which backend is currently running
get_active() {
    if check_health "$LLAMA_HOST" "$LLAMA_URL" "/health"; then
        echo "llama-cpp"
    elif check_health "$VLLM_HOST" "$VLLM_URL" "/v1/models"; then
        echo "vllm"
    else
        echo "none"
    fi
}

cmd_status() {
    local active
    active=$(get_active)
    log "Active backend: ${active}"

    if [ "$active" = "llama-cpp" ]; then
        local slots
        slots=$(ssh "$LLAMA_HOST" "curl -sf ${LLAMA_URL}/slots" 2>/dev/null) || true
        if [ -n "$slots" ]; then
            log "Slots: ${slots}"
        fi
    fi

    # List saved slot files
    local saved
    saved=$(ssh "$LLAMA_HOST" "ls -lh /mnt/models/cache/llama-cpp/slots/ 2>/dev/null" || true)
    if [ -n "$saved" ]; then
        log "Saved slots on disk:"
        echo "$saved"
    fi
}

cmd_switch() {
    local target="$1"
    local active
    active=$(get_active)

    if [ "$active" = "$target" ]; then
        log "${target} is already active"
        return 0
    fi

    # Stop current backend (with slot save if llama-cpp)
    case "$active" in
        llama-cpp)
            save_slot "$SLOT_NAME" || true
            log "Stopping llama-cpp..."
            ssh "$LLAMA_HOST" "systemctl stop llama-server" || true
            ;;
        vllm)
            log "Stopping vLLM..."
            ssh "$VLLM_HOST" "systemctl stop vllm" || true
            ;;
        none)
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

# Main
case "${1:-help}" in
    switch)
        [ -z "${2:-}" ] && { err "Usage: wechsler.sh switch <llama-cpp|vllm>"; exit 1; }
        cmd_switch "$2"
        ;;
    status)
        cmd_status
        ;;
    save)
        save_slot "${2:-$SLOT_NAME}"
        ;;
    restore)
        restore_slot "${2:-$SLOT_NAME}"
        ;;
    help|--help|-h)
        echo "Usage: wechsler.sh <switch|status|save|restore> [args]"
        echo ""
        echo "Commands:"
        echo "  switch <llama-cpp|vllm>  Switch active backend"
        echo "  status                   Show active backend and slot info"
        echo "  save [name]              Save llama-cpp slot to disk"
        echo "  restore [name]           Restore llama-cpp slot from disk"
        ;;
    *)
        err "Unknown command: $1"
        exit 1
        ;;
esac
