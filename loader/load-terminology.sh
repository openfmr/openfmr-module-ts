#!/usr/bin/env bash
# =============================================================================
# OpenFMR Terminology Service — Terminology Loader Script
# =============================================================================
# This script scans the /data directory for terminology distribution files
# and uploads them to the HAPI FHIR Terminology Server using the HAPI CLI.
#
# Supported terminology packages:
#   • loinc.zip    — LOINC (Logical Observation Identifiers Names and Codes)
#   • snomed.zip   — SNOMED CT Global Patient Set (or full edition)
#   • rxnorm.zip   — RxNorm (US medication terminology)
#   • icd10.zip    — ICD-10 (International Classification of Diseases, 10th)
#
# Each file is processed independently. If a file is not present, it is
# simply skipped with an informational message.
#
# Exit codes:
#   0 — All found packages uploaded successfully (or none found).
#   1 — One or more uploads failed.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DATA_DIR="${DATA_DIR:-/data}"
FHIR_SERVER_URL="${FHIR_SERVER_URL:-http://ts-fhir-server:8080/fhir}"
HAPI_CLI_JAR="${HAPI_CLI_JAR:-/opt/hapi-fhir-cli.jar}"
FHIR_VERSION="${FHIR_VERSION:-r4}"

# Track overall success/failure.
FAILURES=0
UPLOADS=0

# ---------------------------------------------------------------------------
# Logging Helpers
# ---------------------------------------------------------------------------
log_info()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]    $*"; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"; }
log_warn()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]    $*"; }
log_error()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]   $*" >&2; }

# ---------------------------------------------------------------------------
# Upload Function
# ---------------------------------------------------------------------------
# Uploads a single terminology zip file to the FHIR server.
#
# Arguments:
#   $1 — Human-readable name of the terminology (e.g., "LOINC").
#   $2 — Filename to look for in DATA_DIR (e.g., "loinc.zip").
#   $3 — (Optional) Additional CLI flags.
# ---------------------------------------------------------------------------
upload_terminology() {
    local name="$1"
    local filename="$2"
    local extra_args="${3:-}"
    local filepath="${DATA_DIR}/${filename}"

    if [ ! -f "${filepath}" ]; then
        log_info "${name}: File '${filename}' not found in ${DATA_DIR}. Skipping."
        return 0
    fi

    local filesize
    filesize=$(du -h "${filepath}" | cut -f1)
    log_info "============================================================"
    log_info "${name}: Found '${filename}' (${filesize}). Starting upload..."
    log_info "  Server:  ${FHIR_SERVER_URL}"
    log_info "  Version: ${FHIR_VERSION}"
    log_info "============================================================"

    local start_time
    start_time=$(date +%s)

    # Execute the HAPI FHIR CLI upload-terminology command.
    # shellcheck disable=SC2086
    if java -jar "${HAPI_CLI_JAR}" upload-terminology \
        -v "${FHIR_VERSION}" \
        -t "${FHIR_SERVER_URL}" \
        -u "${filepath}" \
        ${extra_args}; then

        local end_time duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log_success "${name}: Upload completed successfully in ${duration}s."
        UPLOADS=$((UPLOADS + 1))
    else
        local end_time duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log_error "${name}: Upload FAILED after ${duration}s."
        log_error "${name}: Please check the server logs for details."
        FAILURES=$((FAILURES + 1))
    fi
}

# =============================================================================
# Main Execution
# =============================================================================
log_info "============================================================"
log_info "  OpenFMR Terminology Loader"
log_info "  Data directory : ${DATA_DIR}"
log_info "  FHIR server    : ${FHIR_SERVER_URL}"
log_info "  FHIR version   : ${FHIR_VERSION}"
log_info "============================================================"

# List what's in the data directory for debugging.
log_info "Contents of ${DATA_DIR}:"
ls -lh "${DATA_DIR}" 2>/dev/null || log_warn "  (directory is empty or inaccessible)"
echo ""

# ---------------------------------------------------------------------------
# Process each supported terminology package.
# ---------------------------------------------------------------------------

# LOINC — Logical Observation Identifiers Names and Codes
upload_terminology "LOINC" "loinc.zip"

# SNOMED CT — Systematized Nomenclature of Medicine (Global Patient Set)
upload_terminology "SNOMED CT" "snomed.zip"

# RxNorm — US Medication Terminology
upload_terminology "RxNorm" "rxnorm.zip"

# ICD-10 — International Classification of Diseases, 10th Revision
upload_terminology "ICD-10" "icd10.zip"

# =============================================================================
# Summary
# =============================================================================
echo ""
log_info "============================================================"
log_info "  Terminology Loading Complete"
log_info "  Packages uploaded : ${UPLOADS}"
log_info "  Failures          : ${FAILURES}"
log_info "============================================================"

if [ "${UPLOADS}" -eq 0 ] && [ "${FAILURES}" -eq 0 ]; then
    log_warn "No terminology files were found in ${DATA_DIR}."
    log_warn "To load terminologies, place the zip files in ./data/ and"
    log_warn "run:  docker-compose up ts-loader"
fi

if [ "${FAILURES}" -gt 0 ]; then
    log_error "${FAILURES} upload(s) failed. See logs above for details."
    exit 1
fi

log_success "All terminology uploads completed successfully."
exit 0
