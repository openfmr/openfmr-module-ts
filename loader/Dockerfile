# =============================================================================
# OpenFMR Terminology Service — Bulk Loader Container
# =============================================================================
# This image provides the HAPI FHIR CLI tool for uploading terminology
# packages (LOINC, SNOMED GPS, RxNorm) into the Terminology Server.
#
# It is designed to be run as a transient (one-shot) container:
#   1. Wait for the FHIR server to become available.
#   2. Scan /data for terminology zip files.
#   3. Upload each file via `hapi-fhir-cli upload-terminology`.
#   4. Exit.
#
# Build context: ./loader
# =============================================================================

# ---------------------------------------------------------------------------
# Base Image
# ---------------------------------------------------------------------------
# Eclipse Temurin JRE 17 on Alpine — lightweight but fully capable of
# running the HAPI FHIR CLI JAR.
# ---------------------------------------------------------------------------
FROM eclipse-temurin:17-jre-alpine

LABEL maintainer="OpenFMR Team"
LABEL description="Terminology bulk-loader for the OpenFMR Terminology Service"

# ---------------------------------------------------------------------------
# System Dependencies
# ---------------------------------------------------------------------------
# - bash:   Required for our shell scripts.
# - curl:   Used to poll the FHIR server's /metadata endpoint.
# - jq:     Useful for parsing FHIR JSON responses (optional but handy).
# ---------------------------------------------------------------------------
RUN apk add --no-cache bash curl jq unzip

# ---------------------------------------------------------------------------
# HAPI FHIR CLI
# ---------------------------------------------------------------------------
# Download the HAPI FHIR CLI JAR. This tool provides the
# `upload-terminology` command used to bulk-load CodeSystems.
#
# The version should align with the HAPI FHIR Server image version.
# Using 7.6.0 as a stable recent release.
# ---------------------------------------------------------------------------
ARG HAPI_CLI_VERSION=7.6.0
ENV HAPI_CLI_JAR=/opt/hapi-fhir-cli.jar

RUN curl -fSL \
      "https://github.com/hapifhir/hapi-fhir/releases/download/v${HAPI_CLI_VERSION}/hapi-fhir-${HAPI_CLI_VERSION}-cli.zip" \
      -o /tmp/hapi-cli.zip && \
    unzip -q /tmp/hapi-cli.zip -d /opt/ && \
    # The archive extracts a directory; find and rename the JAR for consistency.
    find /opt -name "hapi-fhir-cli.jar" -exec mv {} ${HAPI_CLI_JAR} \; && \
    rm -rf /tmp/hapi-cli.zip && \
    # Verify the JAR is present
    test -f ${HAPI_CLI_JAR} || (echo "ERROR: HAPI CLI JAR not found after extraction" && exit 1)

# ---------------------------------------------------------------------------
# Scripts
# ---------------------------------------------------------------------------
WORKDIR /app

COPY wait-for-it.sh  /app/wait-for-it.sh
COPY load-terminology.sh /app/load-terminology.sh

RUN chmod +x /app/wait-for-it.sh /app/load-terminology.sh

# ---------------------------------------------------------------------------
# Data Volume
# ---------------------------------------------------------------------------
# Terminology zip files (loinc.zip, snomed.zip, rxnorm.zip) should be
# mounted at /data.
# ---------------------------------------------------------------------------
VOLUME ["/data"]

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
# 1. Wait for the FHIR server's capability statement endpoint.
# 2. Execute the terminology loading script.
# ---------------------------------------------------------------------------
ENTRYPOINT ["/app/wait-for-it.sh"]
CMD ["/app/load-terminology.sh"]
