# 🪵 Loki + Promtail Local Logging Stack (macOS) with S3 Backend

This project sets up a minimal yet production-aligned observability stack **locally on macOS**, using:

- **Loki** for log aggregation and long-term storage in **Amazon S3**
- **Promtail** to collect and push logs to Loki
- Optional: **Grafana** to visualize logs

---

## 🧱 Folder Structure

All files and binaries live in a single flat working directory (no nested `loki-setup/` folder):

```
.
├── loki                      # Loki binary (downloaded)
├── promtail                  # Promtail binary (downloaded)
├── loki-config.yaml          # Loki config using S3 backend
├── promtail-config.yaml      # Promtail config for log scraping
├── .env                      # AWS credentials and bucket config
├── promtail-positions.yaml   # Auto-created by Promtail
└── loki-data/
    ├── index/
    ├── boltdb-cache/
    └── compactor/
```

---

## 📦 Prerequisites

- macOS with `curl` and basic UNIX tools
- AWS account with an S3 bucket created
- Loki + Promtail binaries downloaded

---

## 🔐 Step 1: Create `.env`

Create a file named `.env` in your working directory:

```dotenv
S3_BUCKET_NAME=your-s3-bucket-name
AWS_REGION=your-region
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
```

Load it in your shell before running anything:

```bash
source .env
```

---

## 🧱 Step 2: Create Loki Data Folders

```bash
mkdir -p loki-data/index loki-data/boltdb-cache loki-data/compactor
```

---

## ⚙️ Step 3: Loki Config (`loki-config.yaml`)

```yaml
auth_enabled: false
server:
  http_listen_port: 3100
  grpc_listen_port: 9095
  log_level: info

common:
  path_prefix: ./loki-data
  storage:
    s3:
      bucketnames: ${S3_BUCKET_NAME}
      region: ${AWS_REGION}
      access_key_id: ${AWS_ACCESS_KEY_ID}
      secret_access_key: ${AWS_SECRET_ACCESS_KEY}
  ring:
    kvstore:
      store: inmemory
  replication_factor: 1

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: s3
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  aws:
    s3: s3://${S3_BUCKET_NAME}
    s3forcepathstyle: true
  boltdb_shipper:
    active_index_directory: ./loki-data/index
    cache_location: ./loki-data/boltdb-cache
    shared_store: s3

ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 1m
  chunk_retain_period: 1m
  chunk_target_size: 1572864
  max_chunk_age: 1h

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  max_cache_freshness_per_query: 10m
  max_entries_limit_per_query: 100000
  ingestion_rate_mb: 15
  ingestion_burst_size_mb: 20

compactor:
  working_directory: ./loki-data/compactor
  shared_store: s3
  compaction_interval: 10m

query_range:
  align_queries_with_step: true
  parallelise_shardable_queries: true
  max_retries: 5

table_manager:
  retention_deletes_enabled: true
  retention_period: 168h

query_scheduler:
  max_outstanding_requests_per_tenant: 1000
```

---

## 📥 Step 4: Promtail Config (`promtail-config.yaml`)

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: ./promtail-positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          host: ${HOSTNAME}
          __path__: /path/to/your/test.log
```

> 🔁 Replace `/path/to/your/test.log` with any real log file you want to monitor.

---

## ▶️ Step 5: Run Loki and Promtail

### Start Loki

```bash
./loki -config.file=loki-config.yaml -config.expand-env=true
```

Loki will start listening on `localhost:3100`.

### Start Promtail

```bash
./promtail -config.file=promtail-config.yaml
```

---

## 📊 Step 6: View Logs in Grafana (Optional)

1. Open Grafana: [http://localhost:3000](http://localhost:3000)
2. Add Loki as a data source: `http://localhost:3100`
3. Go to **Explore**
4. Run a query: `{job="varlogs"}`

You should now see logs flowing in!

---

## 🛑 Stopping Services

To stop:

```bash
ps aux | grep loki       # Find Loki PID
kill -9 <PID>

ps aux | grep promtail   # Find Promtail PID
kill -9 <PID>
```

---

## ✅ Verification Checklist

- [x] Logs visible in Grafana Explore
- [x] Chunks and indexes appear in S3 bucket
- [x] No errors in Loki or Promtail output
- [x] `localhost:3100/metrics` responds

---

## 📎 Notes

- You can use any local `.log` file with Promtail for testing
- All logs are durably stored in your configured S3 bucket
- Loki is using TSDB schema v13 for scalable indexing

---

## 🧪 Optional Enhancements

- Add Tempo for tracing
- Use Prometheus + Alloy for metrics
- Set up alerting in Grafana for error logs
- Tail container logs using `/var/log/containers/*.log` on Linux

---

## 🙋 Need Help?

Feel free to reach out if you want:

- A test log generator script
- Dockerized setup for easier startup
- Grafana pre-configured dashboards

----------------
----------------

# 🔧 Loki Configuration Explained

This config is tailored for **local development on macOS**, with **S3 as long-term log storage**, and **TSDB schema** for optimal query performance and compaction support.

### 🖥️ `server`

```yaml
server:
  http_listen_port: 3100
  grpc_listen_port: 9095
  log_level: info
```

- **http_listen_port**: Exposes Loki's REST API on `localhost:3100`.
- **grpc_listen_port**: Sets gRPC to port 9095 (used internally, often required for clustering or ingesters).
- **log_level**: Logging verbosity. `info` is good for general operational visibility.

---

### 📂 `common`

```yaml
common:
  path_prefix: ./loki-data
  storage:
    s3: ...
```

- **path_prefix**: All local data (e.g., indexes, cache) is stored inside `./loki-data`.
- **storage.s3**: Defines the **S3 bucket** where logs, indexes, and other data will persist.
- Credentials and region are injected securely via environment variables (`.env` file).

---

### 🪝 `ring`

```yaml
ring:
  kvstore:
    store: inmemory
replication_factor: 1
```

- **ring.kvstore**: Controls the internal service discovery/state sharing. `inmemory` is ideal for single-instance setups.
- **replication_factor: 1**: No redundancy (since we're not running multiple Loki replicas).

---

### 🧬 `schema_config`

```yaml
schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: s3
      schema: v13
      index:
        prefix: index_
        period: 24h
```

- **store: tsdb**: Enables **Time Series Database (TSDB)** format for logs — best for efficient queries and future-proofing.
- **object_store: s3**: Stores chunks and indexes in S3.
- **index.prefix/period**: Index chunks are created every 24 hours, prefixed with `index_`.

---

### 🏪 `storage_config`

```yaml
storage_config:
  aws:
    s3: s3://${S3_BUCKET_NAME}
    s3forcepathstyle: true
  boltdb_shipper:
    active_index_directory: ./loki-data/index
    cache_location: ./loki-data/boltdb-cache
    shared_store: s3
```

- **boltdb_shipper**: Writes indexes locally and ships them to S3.
- **active_index_directory**: Local path for index files before upload.
- **cache_location**: Stores temporary cache data.
- **shared_store**: Declares that S3 is the shared long-term store.

---

### 🧃 `ingester`

```yaml
ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 1m
  chunk_retain_period: 1m
  chunk_target_size: 1572864
  max_chunk_age: 1h
```

- The **ingester** handles log ingestion, chunking, and flushing.
- **chunk_idle_period**: If no new logs come in after 1 minute, flush the chunk.
- **chunk_target_size**: Target chunk size ~1.5 MB.
- **max_chunk_age**: Flush any chunk older than 1 hour.

---

### 🚦 `limits_config`

```yaml
limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  max_cache_freshness_per_query: 10m
  max_entries_limit_per_query: 100000
  ingestion_rate_mb: 15
  ingestion_burst_size_mb: 20
```

- **reject_old_samples**: Disallows stale log data (older than 7 days).
- **max_entries_limit_per_query**: Prevents excessive log flooding during queries.
- **ingestion_rate_mb** and **burst_size_mb**: Throttling limits for ingestion.

---

### 📦 `compactor`

```yaml
compactor:
  working_directory: ./loki-data/compactor
  shared_store: s3
  compaction_interval: 10m
```

- Compacts and optimizes index data.
- Runs every 10 minutes.
- Uses S3 as the shared storage for compaction output.

---

### 🔎 `query_range`

```yaml
query_range:
  align_queries_with_step: true
  parallelise_shardable_queries: true
  max_retries: 5
```

- Controls how queries behave.
- **parallelise_shardable_queries** improves performance.
- Retries up to 5 times on failure.

---

### 🧹 `table_manager`

```yaml
table_manager:
  retention_deletes_enabled: true
  retention_period: 168h
```

- Automatically deletes old logs after 7 days (168 hours).
- Helps keep your S3 bucket clean and costs low.

---

### 📋 `query_scheduler`

```yaml
query_scheduler:
  max_outstanding_requests_per_tenant: 1000
```

- Limits the number of concurrent outstanding queries per tenant to prevent overload.

---

## ✅ Summary

- Logs are ingested locally via Promtail.
- Stored and indexed in **S3** using **TSDB schema**.
- Supports efficient querying, compaction, and retention.
- Secrets are injected via `.env` file for security.
- Ready for production-style observability while staying local-friendly.

----------------------
----------------------

# 📄 Promtail Configuration Explained

This config is designed for:

- macOS local development
- Forwarding logs to **Loki running at `localhost:3100`**
- Scraping plain text logs (e.g., system or app logs)

---

### ✅ `promtail-config.yaml`

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0
```

- **http_listen_port**: Promtail’s internal web interface (for health checks, etc.) runs on port 9080.
- **grpc_listen_port**: Disabled (`0`) as we don't need gRPC communication in this standalone setup.

---

```yaml
positions:
  filename: ./promtail-positions.yaml
```

- Keeps track of the **last read line per log file**.
- Ensures Promtail resumes from where it left off across restarts.
- This file is auto-managed and safe to keep in your repo or `.gitignore`.

---

```yaml
clients:
  - url: http://localhost:3100/loki/api/v1/push
```

- Sends logs to your local Loki instance at port 3100.
- This must match the actual address and port Loki is listening on.

---

```yaml
scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          host: ${HOSTNAME}
          __path__: /var/log/*.log
```

This is the heart of Promtail — it tells it **what logs to scrape** and how to label them.

#### 🔍 Explanation:
- **job_name: system** – Logical name for this scraping job.
- **targets** – Required but unused; `localhost` is a dummy value.
- **labels**:
  - **job** – LogQL will show this under `{job="varlogs"}` — useful for filtering in Grafana.
  - **host** – Dynamically inserts your Mac's hostname using `${HOSTNAME}` (make sure it’s exported in your shell).
  - **__path__** – Glob pattern for logs to watch.

> **⚠️ macOS Note:**  
> `/var/log/*.log` may not contain readable logs or may be empty due to macOS system protections.  
> You can change it to a dev log path like:

```yaml
__path__: /Users/yourname/dev/logs/*.log
```

Or even test it with a simple log file you generate:

```yaml
__path__: ./sample.log
```
