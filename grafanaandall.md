# EKS Cluster Monitoring and Logging Setup

This document provides a complete guide to setting up **monitoring and logging** for an **Amazon EKS cluster** using:

## 🛠️ Overview of Setup via Helm

### 1. **Prometheus (via kube-prometheus-stack)**

- Scrapes control plane + workloads metrics
- Auto-discovers all services
- Provides alerting (via Alertmanager)

### 2. **Grafana**

- Automatically installed with dashboards
- Integrated with Prometheus + Loki

### 3. **Loki**

- Logs aggregation
- Stores logs in S3
- Queried by Grafana

### 4. **Grafana Alloy**

- Collects logs from nodes/pods
- Sends to Loki

---

## 🚀 Overview

| Tool           | Role                                 |
|----------------|--------------------------------------|
| Prometheus     | Kubernetes + app metrics             |
| Grafana        | Dashboards and alerts                |
| Grafana Alloy  | Log collection from nodes/pods       |
| Loki           | Log aggregation + S3 storage backend |
| S3             | Long-term log storage                |

---

## 🧰 Prerequisites

- EKS Cluster with IAM OIDC provider enabled
- kubectl + Helm installed
- Existing CloudWatch setup (optional)
- IRSA roles and S3 bucket (e.g., `loki-logs-bucket`)

---

## 🛠️ Install via Helm (Step-by-Step)

### 1. Add Helm Repositories

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

---

### 2. Deploy Prometheus & Grafana

```bash
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

This includes:
- Prometheus
- Grafana
- kube-state-metrics
- Node exporter
- Alertmanager

---

### 3. Deploy Loki with S3 Backend

Create `loki-values.yaml`:

```yaml
loki:
  auth_enabled: false

  storage:
    type: s3
    s3:
      region: us-east-1
      bucketnames: loki-logs-bucket
      endpoint: s3.amazonaws.com
      s3ForcePathStyle: false

  commonConfig:
    replication_factor: 1
    path_prefix: /var/loki

  schemaConfig:
    configs:
      - from: 2022-01-01
        store: boltdb-shipper
        object_store: s3
        schema: v11
        index:
          prefix: index_
          period: 24h

serviceAccount:
  create: true
  name: loki
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/loki-irsa-role
```

Install Loki:

```bash
helm install loki grafana/loki -n logging --create-namespace -f loki-values.yaml
```

---

### 4. Deploy Grafana Alloy for Log Forwarding

Create ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-alloy-config
  namespace: logging
data:
  config.alloy: |
    logging {
      level = "info"
    }

    discovery.kubernetes "pods" {
      role = "pod"
    }

    loki.source.kubernetes "logs" {
      targets = discovery.kubernetes.pods.targets
      forward_to = [loki.write.default.receiver]
    }

    loki.write "default" {
      endpoint {
        url = "http://loki.logging.svc.cluster.local:3100/loki/api/v1/push"
      }
    }
```

Apply:
```bash
kubectl apply -f grafana-alloy-config.yaml
```

Install Alloy:
```bash
helm install grafana-alloy grafana/grafana-agent \
  -n logging \
  --set configMap.create=false \
  --set configMap.name=grafana-alloy-config \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::<ACCOUNT_ID>:role/grafana-alloy-irsa-role
```

---

### 5. Add Loki to Grafana

```bash
helm upgrade --reuse-values monitoring prometheus-community/kube-prometheus-stack \
  --set grafana.additionalDataSources[0].name=Loki \
  --set grafana.additionalDataSources[0].type=loki \
  --set grafana.additionalDataSources[0].url=http://loki.logging.svc.cluster.local:3100
```

---

## 🔐 IAM Roles & Permissions (IRSA)

### IAM Policy for Loki IRSA Role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::loki-logs-bucket",
        "arn:aws:s3:::loki-logs-bucket/*"
      ]
    }
  ]
}
```

Use `eksctl` or Terraform to bind this to Loki/Alloy service accounts.

---

## ✅ Validation Steps

### Grafana Dashboards

```bash
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
```

Login at `http://localhost:3000` (default: admin/prom-operator)

### Loki Logs

- Go to **Explore** in Grafana
- Select **Loki**
- Run query: `{namespace="default"}`

### S3 Bucket

Check for `index_` and `chunks` in your bucket to verify logs are pushed.

---

## 📦 What's Next?

- Migrate application logging to structured logs
- Add tracing (Tempo)
- Add Thanos for long-term metrics storage
- Replace CloudWatch log agents completely

---

## 🔗 References

- [Grafana Alloy](https://grafana.com/docs/alloy/latest/)
- [Loki Helm Chart](https://github.com/grafana/helm-charts/tree/main/charts/loki)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)

---

