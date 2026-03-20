# OpenFMR Terminology Service (TS) Module

> **Part of [OpenFMR](https://github.com/openfmr) — A modular, fully FHIR-native Health Information Exchange.**

The **Terminology Service (TS)** module provides a centralised, standards-based terminology server for the OpenFMR HIE. It enables all other modules to validate codes, expand ValueSets, look up concepts, and translate between code systems using FHIR Terminology operations (`$lookup`, `$validate-code`, `$expand`, `$translate`, `$subsumes`).

Built on the [HAPI FHIR JPA Server](https://hapifhir.io/), this module is specifically tuned for the high-memory, high-I/O demands of indexing large code systems such as **SNOMED CT**, **LOINC**, **RxNorm**, and **ICD-10**.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      openfmr_global_net                        │
│                                                                 │
│  ┌──────────────┐   ┌──────────────────┐   ┌──────────────┐   │
│  │  ts-postgres  │◄──│  ts-fhir-server  │   │  ts-loader   │   │
│  │  (PostgreSQL) │   │   (HAPI FHIR)    │◄──│  (One-shot)  │   │
│  │               │   │   Port: 8080     │   │              │   │
│  └──────────────┘   └──────────────────┘   └──────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

| Service | Image | Purpose |
|---------|-------|---------|
| `ts-postgres` | `postgres:15` | Dedicated database, tuned for terminology indexing |
| `ts-fhir-server` | `hapiproject/hapi:latest` | FHIR R4 Terminology Server (2–4 GB heap) |
| `ts-loader` | Custom (Alpine + HAPI CLI) | Transient container for bulk-loading terminology zips |

---

## Prerequisites

- **Docker** ≥ 20.10 and **Docker Compose** ≥ 2.x
- The **openfmr-core** module must be running (creates the `openfmr_global_net` network)
- **≥ 8 GB of RAM** allocated to Docker (SNOMED/LOINC indexing is very memory-intensive)

---

## Quick Start

### 1. Clone and Configure

```bash
git clone <repository-url> openfmr-module-ts
cd openfmr-module-ts

# Create your environment file
cp .env.example .env
# Edit .env and set a strong password for TS_POSTGRES_PASSWORD
```

### 2. Start the Core Services

```bash
docker-compose up -d ts-postgres ts-fhir-server
```

Wait for the FHIR server to become healthy (this can take 1–2 minutes on first start):

```bash
# Check health status
docker-compose ps

# Or poll the metadata endpoint directly
curl http://localhost:8084/fhir/metadata
```

### 3. Verify the Server

Once healthy, you should receive a FHIR `CapabilityStatement` from:

```
http://localhost:8084/fhir/metadata
```

---

## Loading Terminology Packages

The `ts-loader` service is a **one-shot container** that bulk-imports terminology packages into the FHIR server using the HAPI FHIR CLI.

### Step 1: Download the Terminology Files

> **⚠️ Important:** These files are licensed and must be downloaded manually from their official sources.

| Terminology | Source | Rename to |
|-------------|--------|-----------|
| **LOINC** | [loinc.org/downloads](https://loinc.org/downloads/) | `loinc.zip` |
| **SNOMED CT GPS** | [SNOMED International](https://www.snomed.org/snomed-ct/Other-SNOMED-products/Global-Patient-Set) | `snomed.zip` |
| **RxNorm** | [NLM/NIH](https://www.nlm.nih.gov/research/umls/rxnorm/docs/rxnormfiles.html) | `rxnorm.zip` |
| **ICD-10** | [WHO / CMS](https://www.cms.gov/medicare/coding-billing/icd-10-codes) | `icd10.zip` |

### Step 2: Place Files in the `data/` Directory

```bash
# Example: copy your downloaded LOINC file
cp ~/Downloads/Loinc_2.77.zip ./data/loinc.zip

# Example: copy SNOMED GPS
cp ~/Downloads/SnomedCT_GlobalPatientSetRF2.zip ./data/snomed.zip
```

### Step 3: Run the Loader

```bash
docker-compose up ts-loader
```

The loader will:
1. Wait for the FHIR server to be fully available
2. Scan `/data` for recognised terminology files
3. Upload each file found using `hapi-fhir-cli upload-terminology`
4. Print a summary and exit

**⏱ Expected Loading Times:**

| Terminology | Approximate Time | Notes |
|-------------|-----------------|-------|
| LOINC | 5–15 minutes | ~100K concepts |
| SNOMED GPS | 30–90 minutes | ~40K concepts, complex hierarchy |
| RxNorm | 15–30 minutes | Varies by release |

> **Note:** Loading times depend heavily on available RAM and disk speed. Ensure Docker has at least 8 GB of RAM allocated.

### Step 4: Verify the Upload

After loading, query the server for the terminology:

```bash
# Check LOINC
curl "http://localhost:8084/fhir/CodeSystem?url=http://loinc.org"

# Check SNOMED
curl "http://localhost:8084/fhir/CodeSystem?url=http://snomed.info/sct"

# Test a concept lookup
curl "http://localhost:8084/fhir/CodeSystem/\$lookup?system=http://loinc.org&code=8867-4"
```

---

## File Structure

```
openfmr-module-ts/
├── docker-compose.yml          # Service definitions and orchestration
├── .env.example                # Environment variable template
├── README.md                   # This file
├── config/
│   └── hapi-application.yaml   # HAPI FHIR server configuration
├── data/
│   └── .gitkeep                # Place terminology zip files here
└── loader/
    ├── Dockerfile              # Loader container image definition
    ├── wait-for-it.sh          # FHIR server readiness poller
    └── load-terminology.sh     # Terminology upload orchestrator
```

---

## Configuration Reference

### Environment Variables (`.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `TS_POSTGRES_DB` | `hapi_ts` | PostgreSQL database name |
| `TS_POSTGRES_USER` | `hapi_ts_user` | PostgreSQL username |
| `TS_POSTGRES_PASSWORD` | `hapi_ts_pass` | PostgreSQL password (**change this!**) |
| `TS_FHIR_PORT` | `8084` | Host port for the FHIR server |

### PostgreSQL Tuning (in `docker-compose.yml`)

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `shared_buffers` | 1 GB | Cache terminology data in memory |
| `max_locks_per_transaction` | 256 | Handle massive DDL during indexing |
| `work_mem` | 64 MB | Complex sort/hash for concept hierarchies |
| `maintenance_work_mem` | 512 MB | Faster index creation |
| `max_wal_size` | 2 GB | Reduce checkpoint frequency during imports |

### JVM Configuration

The FHIR server runs with `JAVA_OPTS="-Xms2g -Xmx4g"`. To adjust:

```yaml
# In docker-compose.yml, under ts-fhir-server > environment:
JAVA_OPTS: "-Xms2g -Xmx6g"  # Increase max heap to 6 GB
```

---

## Integration with OpenFMR

Other OpenFMR modules can reach the Terminology Service at:

```
http://ts-fhir-server:8080/fhir
```

This URL is resolvable within the `openfmr_global_net` Docker network. Use it for:

- **Code validation:** `POST /fhir/CodeSystem/$validate-code`
- **ValueSet expansion:** `GET /fhir/ValueSet/$expand`
- **Concept lookup:** `GET /fhir/CodeSystem/$lookup`
- **Code translation:** `POST /fhir/ConceptMap/$translate`

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `OutOfMemoryError` during loading | Increase `JAVA_OPTS` `-Xmx` value and Docker memory limit |
| Loader times out waiting for server | Increase `MAX_WAIT` env var in docker-compose for ts-loader |
| `openfmr_global_net` not found | Start openfmr-core first: `cd ../openfmr-core && docker-compose up -d` |
| Database connection refused | Ensure `ts-postgres` is healthy: `docker-compose ps` |

---

## License

This module is part of the OpenFMR project. See the root repository for license details.
