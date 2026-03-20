#!/usr/bin/env bash
# =============================================================================
# OpenFMR Terminology Service — Wait-for-FHIR-Server Script
# =============================================================================
# This script polls the HAPI FHIR server's /metadata (CapabilityStatement)
# endpoint until it responds with HTTP 200, indicating the server is fully
# initialised and ready to accept terminology uploads.
#
# Once the server is available, this script executes whatever command is
# passed as arguments (typically load-terminology.sh).
#
# Usage (set as Docker ENTRYPOINT):
#   /app/wait-for-it.sh /app/load-terminology.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# The FHIR server metadata endpoint to poll.
FHIR_METADATA_URL="${FHIR_METADATA_URL:-http://ts-fhir-server:8080/fhir/metadata}"

# Maximum time to wait for the server (in seconds).
MAX_WAIT="${MAX_WAIT:-600}"

# Interval between polling attempts (in seconds).
POLL_INTERVAL="${POLL_INTERVAL:-10}"

# ---------------------------------------------------------------------------
# Logging Helpers
# ---------------------------------------------------------------------------
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
log_warn()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; }

# ---------------------------------------------------------------------------
# Wait Loop
# ---------------------------------------------------------------------------
log_info "Waiting for FHIR server at: ${FHIR_METADATA_URL}"
log_info "Timeout: ${MAX_WAIT}s | Poll interval: ${POLL_INTERVAL}s"

elapsed=0

while [ "${elapsed}" -lt "${MAX_WAIT}" ]; do
    # Attempt to reach the metadata endpoint.
    if curl -sf --max-time 10 "${FHIR_METADATA_URL}" > /dev/null 2>&1; then
        log_info "FHIR server is ready! (responded after ${elapsed}s)"
        break
    fi

    log_info "Server not ready yet... retrying in ${POLL_INTERVAL}s (${elapsed}s/${MAX_WAIT}s)"
    sleep "${POLL_INTERVAL}"
    elapsed=$((elapsed + POLL_INTERVAL))
done

# Check if we timed out.
if [ "${elapsed}" -ge "${MAX_WAIT}" ]; then
    log_error "Timed out after ${MAX_WAIT}s waiting for FHIR server."
    log_error "Please ensure ts-fhir-server is running and accessible."
    exit 1
fi

# ---------------------------------------------------------------------------
# Execute the Downstream Command
# ---------------------------------------------------------------------------
# Pass control to the command provided as arguments (e.g., load-terminology.sh).
if [ "$#" -gt 0 ]; then
    log_info "Executing command: $*"
    exec "$@"
else
    log_warn "No command specified. Exiting."
    exit 0
fi
