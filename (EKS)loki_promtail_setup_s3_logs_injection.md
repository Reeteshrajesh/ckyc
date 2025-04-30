# 📦 Loki + Promtail on EKS (S3-Backed Logging)

This repository documents the setup of **Grafana Loki** and **Promtail** in an **EKS cluster** where many services run. Logs are persisted to an **S3 bucket** and can be queried through **Grafana**.

---

## 📚 Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Install Loki](#install-loki)
- [Install Promtail](#install-promtail)
- [Connect to Grafana](#connect-to-grafana)
- [Loki Configuration](#loki-configuration)
- [Promtail Configuration](#promtail-configuration)
- [Extras](#extras)

---

## 🧱 Architecture

```
+-------------------+       +-------------+       +--------+
|   EKS Nodes       | <---> |  Promtail   | <---> |  Loki  |
| (K8s workloads)   |       | (DaemonSet) |       | (S3)   |
+-------------------+       +-------------+       +--------+
                                       |
                                   +-------+
                                   | S3    |
                                   +-------+
```

---

## ✅ Prerequisites

- Kubernetes: EKS running
- Tools: `kubectl`, `helm`, `awscli`
- S3 Bucket created (e.g. `my-loki-logs`)
- OIDC + IRSA setup (recommended for AWS access)

---

## 🚀 Install Loki

### 1. Add Helm Repo:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### 2. Create Namespace:

```bash
kubectl create namespace observability
```

### 3. Create `loki-values.yaml`:

```yaml
loki:
  enabled: true
  isReadOnly: false

  config:
    server:
      http_listen_port: 3100
    common:
      path_prefix: /var/loki
      storage:
        s3:
          bucketnames: your-s3-bucket
          region: your-region
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
        s3: s3://your-s3-bucket
        s3forcepathstyle: true
      boltdb_shipper:
        active_index_directory: /var/loki/index
        cache_location: /var/loki/boltdb-cache
        shared_store: s3

    compactor:
      working_directory: /var/loki/compactor
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

    table_manager:
      retention_deletes_enabled: true
      retention_period: 168h

  persistence:
    enabled: true
    size: 20Gi
    storageClassName: gp2
```

### 4. Install Loki:

```bash
helm upgrade --install loki grafana/loki-stack \
  --namespace observability \
  -f loki-values.yaml
```

---

## 🔧 Install Promtail

### 1. Create `promtail-values.yaml`:

```yaml
config:
  clients:
    - url: http://loki:3100/loki/api/v1/push
  positions:
    filename: /var/log/positions.yaml
  scrape_configs:
    - job_name: kubernetes-pods
      kubernetes_sd_configs:
        - role: pod
      relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_app]
          target_label: app
        - source_labels: [__meta_kubernetes_namespace]
          target_label: namespace
        - source_labels: [__meta_kubernetes_pod_name]
          target_label: pod
        - action: replace
          source_labels: [__meta_kubernetes_pod_container_name]
          target_label: container
        - action: replace
          replacement: /var/log/pods/*/*/*.log
          target_label: __path__

rbac:
  create: true

serviceAccount:
  create: true
  name: promtail
```

### 2. Install Promtail:

```bash
helm upgrade --install promtail grafana/promtail \
  --namespace observability \
  -f promtail-values.yaml
```

---

## 📊 Connect to Grafana

1. Install Grafana (if not already):
   ```bash
   helm upgrade --install grafana grafana/grafana \
     --namespace observability \
     --set adminPassword='admin'
   ```

2. Access it:
   ```bash
   kubectl port-forward svc/grafana 3000:80 -n observability
   ```

3. Login with:
   - **User**: admin
   - **Pass**: admin

4. Add Loki as a data source:
   - URL: `http://loki:3100`

---

## 📄 Loki Configuration Reference

The `loki-values.yaml` file configures:

- S3 chunk and index storage
- TSDB schema (`v13`)
- Ingestion retention and compaction
- Memory-based KV store (suitable for single-node Loki)

---

## 📄 Promtail Configuration Reference

The `promtail-values.yaml` file configures:

- DaemonSet on all nodes
- Relabeling Kubernetes pod logs
- Tagging logs with `namespace`, `app`, `pod`, `container`
- Push to Loki endpoint

---

## 🎯 Extras

- Add custom labels like `environment` in Promtail's relabel configs
- Use `kubectl logs -l app=promtail` to troubleshoot
- Tune log retention in Loki's `retention_period`
- Secure Loki with ingress + auth (production)

---

## 🙌 Credits

- [Grafana Loki Docs](https://grafana.com/docs/loki/)
- [Promtail Docs](https://grafana.com/docs/loki/latest/clients/promtail/)
- [Helm Charts](https://github.com/grafana/helm-charts)
