# 📘 Loki + Grafana + Promtail Setup on EKS

This README provides a complete step-by-step guide for setting up Loki, Promtail, and Grafana in an Amazon EKS cluster running 30+ services across 10+ namespaces. The logs will be collected using Promtail and stored in an S3 bucket for 6 months, then transitioned to Glacier, and automatically deleted afterward.

---

## 📦 Components Used

- **Grafana Loki**: For storing and querying logs.
- **Promtail**: For collecting and pushing logs to Loki.
- **Grafana**: For visualizing logs and metrics.
- **AWS S3**: For log storage backend.

---

## 🧾 Prerequisites

- Amazon EKS cluster set up and `kubectl` context configured.
- Helm v3 installed.
- AWS CLI configured with necessary IAM permissions for S3.
- S3 bucket created (e.g., `test-devops-buckbuck`).

---

## 🛠️ Step-by-Step Setup

### Step 1: Create S3 Bucket Lifecycle Policy (Log Retention)

Set a lifecycle rule in your S3 bucket to transition logs to Glacier and delete after 6 months.

```json
{
  "Rules": [
    {
      "ID": "LogRetention",
      "Prefix": "",
      "Status": "Enabled",
      "Transitions": [
        {
          "Days": 180,
          "StorageClass": "GLACIER"
        }
      ],
      "Expiration": {
        "Days": 210
      }
    }
  ]
}
```

Apply this via AWS CLI or S3 console.

---

### Step 2: Deploy Loki + Grafana

#### a. Add Grafana Helm Repo
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

#### b. Save `loki-values.yaml`
Use the Loki config from earlier with inline S3 storage, compactor enabled, and retention configured.

```bash
loki:
  enabled: true  # Enables the Loki service in this Helm release

  image:
    repository: grafana/loki  # Official Loki image
    tag: 2.9.4  # Specific Loki version

  config:
    server:
      http_listen_port: 3100  # Loki's main HTTP port for queries and pushes

    compactor:
      working_directory: /var/loki/compactor  # Directory where compactor works
      shared_store: s3  # Use S3 as the shared store for compacted chunks
      compaction_interval: 10m  # Run compaction every 10 minutes to merge chunks
      retention_enabled: true  # Enable retention policy to delete old data

    common:
      path_prefix: /var/loki  # Base path for storing all local data
      storage:
        s3:
          bucketnames: test-devops-buckbuck  # S3 bucket for long-term storage
          region: ap-south-1  # AWS region of your S3 bucket
      ring:
        kvstore:
          store: inmemory  # Use in-memory store for the ring topology
      replication_factor: 1  # Only one replica needed for single-node setup (can increase for HA)

    schema_config:
      configs:
        - from: 2024-01-01  # Start date for this schema configuration
          store: boltdb-shipper  # Index backend to use (ships to S3)
          object_store: s3  # Store log chunks in S3
          schema: v12  # Schema version (v12 is current recommended)
          index:
            prefix: index_  # Prefix for index files
            period: 24h  # New index created every 24 hours

    storage_config:
      aws:
        s3: s3://test-devops-buckbuck  # S3 bucket URL
        s3forcepathstyle: true  # Needed for localstack/minio compatibility (safe to leave true)
      boltdb_shipper:
        active_index_directory: /var/loki/index  # Where active index is kept on disk
        cache_location: /var/loki/boltdb-cache  # Cache location for faster lookup
        shared_store: s3  # Remote store for index files

    index_gateway:
      enabled: true  # Index gateway improves performance in distributed setups

    ingester:
      lifecycler:
        ring:
          kvstore:
            store: inmemory  # In-memory ring configuration for simpler setup
      chunk_idle_period: 1m  # Time to wait before flushing idle chunks
      chunk_retain_period: 1m  # How long to keep chunks in memory before discarding
      chunk_target_size: 1572864  # Target chunk size in bytes (1.5MB)
      max_chunk_age: 1h  # Max age for chunks before they’re flushed regardless of size

    limits_config:
      reject_old_samples: true  # Reject logs older than a threshold
      reject_old_samples_max_age: 168h  # Max age of old logs accepted = 7 days

    table_manager:
      retention_deletes_enabled: true  # Allow deletion of old logs
      retention_period: 168h  # How long logs are kept before deletion (7 days, can extend to 180d)

  persistence:
    enabled: true  # Enable persistent volume for local storage
    accessModes:
      - ReadWriteOnce  # Access mode for the PVC
    size: 20Gi  # PVC size
    storageClassName: gp2  # AWS EBS storage class (can use gp3 for cost efficiency)

  extraVolumeMounts:
    - name: storage
      mountPath: /var/loki  # Mount volume to Loki's expected directory

  extraVolumes:
    - name: storage
      persistentVolumeClaim:
        claimName: loki-storage  # PVC name used above

grafana:
  enabled: true  # Enable Grafana in same chart (optional if using standalone Grafana)

  sidecar:
    datasources:
      enabled: true  # Automatically inject datasource config to Grafana

  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Loki
          type: loki
          uid: loki
          access: proxy
          orgId: 1
          url: http://myrelease-loki:3100  # URL of the Loki service
          basicAuth: false
          isDefault: true
          editable: true
          jsonData:
            maxLines: 1000  # Limit number of log lines per query
```



| Parameter | Explanation |
|----------|-------------|
| `persistence:` | Keeps local disk data persistent, useful for caching boltdb indexes or temporary buffering before S3 upload. |
| `compactor:` | Merges chunks and applies log retention (e.g. delete logs older than 7 days if set). Required for lifecycle + retention. |
| `schema_config.index.period: 24h` | New index every 24 hours—good for reducing lookup times. |
| `ingester.chunk_*` | Controls chunking behavior: size, idle time, and max age—affects memory and performance. |
| `limits_config.reject_old_samples_max_age: 168h` | Reject logs older than 7 days from ingestion—helps keep the system clean. |
| `table_manager.retention_period: 168h` | Time before old logs are deleted—extend to `4320h` for 6 months. |
| `boltdb_shipper.shared_store: s3` | Sends index files to S3 along with log data—reduces local disk use. |




```bash
helm install myrelease grafana/loki-stack \
  -f loki-values.yaml \
  --namespace logging \
  --create-namespace
```

---

### Step 3: Deploy Promtail

#### a. Save `promtail-valueseks.yaml`
Use the documented and updated version of Promtail values that includes correct relabeling, host log mounts, and docker parser.

```bash
promtail:
  enabled: true  # Enable Promtail deployment

  image:
    repository: grafana/promtail  # Promtail official image repo
    tag: 2.9.4  # Match version with Loki for compatibility

  config:
    clients:
      - url: http://myrelease-loki:3100/loki/api/v1/push  # Send logs to Loki service URL

    positions:
      filename: /run/promtail/positions.yaml  # Track last read line per file

    server:
      http_listen_port: 3101  # Promtail's own HTTP port

    scrape_configs:
      - job_name: kubernetes-pods  # Logical job name
        kubernetes_sd_configs:
          - role: pod  # Watch Kubernetes pods

        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_app]  # Get 'app' label if exists
            target_label: app
          - source_labels: [__meta_kubernetes_namespace]  # Include namespace
            target_label: namespace
          - source_labels: [__meta_kubernetes_pod_name]  # Include pod name
            target_label: pod
          - source_labels: [__meta_kubernetes_pod_container_name]  # Container name
            target_label: container
          - action: replace
            source_labels: [__meta_kubernetes_pod_node_name]  # Node name
            target_label: node
          - action: keep
            source_labels: [__meta_kubernetes_pod_phase]
            regex: Running  # Only collect logs from running pods

        pipeline_stages:
          - docker: {}  # Parse Docker log format

        static_configs:
          - targets: [localhost]  # Required but unused in Kubernetes context
            labels:
              job: varlogs
              __path__: /var/log/pods/*/*/*.log  # Location of pod logs on the node

  extraVolumes:
    - name: varlog
      hostPath:
        path: /var/log/pods  # Mount path to access pod logs on the host
    - name: containers
      hostPath:
        path: /var/lib/docker/containers  # Needed if using Docker engine directly

  extraVolumeMounts:
    - name: varlog
      mountPath: /var/log/pods  # Mount into container
      readOnly: true
    - name: containers
      mountPath: /var/lib/docker/containers  # Mount into container
      readOnly: true

  serviceAccount:
    create: true
    name: promtail-sa  # Dedicated service account for Promtail

  tolerations:
    - key: node-role.kubernetes.io/master
      effect: NoSchedule  # Allow Promtail on master nodes if needed

  resources:
    limits:
      memory: 200Mi  # Memory limit
      cpu: 100m  # CPU limit
    requests:
      memory: 100Mi  # Minimum memory guarantee
      cpu: 50m  # Minimum CPU guarantee

  podLabels:
    app: promtail  # Label for Promtail pods

  rbac:
    create: true  # Create RBAC roles

  serviceMonitor:
    enabled: true  # Enable metrics scraping by Prometheus if integrated

```

```bash
helm install promtail grafana/promtail \
  -f promtail-valueseks.yaml \
  --namespace logging
```

---

### Step 4: Validate Setup

- Visit **Grafana** (e.g., port-forward or use LoadBalancer).
- Go to **Explore → Choose data source `Loki`**.
- Start typing queries like:
  ```logql
  {namespace="your-namespace"}
  ```

---

## 🧠 Notes

- **Storage Efficiency**: Logs are stored in S3 with index separation via `boltdb-shipper`.
- **Compaction Enabled**: Ensures logs are deduplicated and compacted.
- **Retention**: 7 days in Loki table manager (can be tuned); long-term logs are offloaded to S3.
- **Security**: Ensure your Promtail and Loki pods have appropriate IAM roles (via IRSA).

---

## 🧹 Cleanup
To delete all components:
```bash
helm uninstall myrelease -n logging
helm uninstall promtail -n logging
kubectl delete ns logging
```

---

## 🔗 References
- [Grafana Loki Docs](https://grafana.com/docs/loki/latest/)
- [Promtail Docs](https://grafana.com/docs/loki/latest/clients/promtail/)
- [Helm Loki Chart](https://github.com/grafana/helm-charts/tree/main/charts/loki-stack)

---


