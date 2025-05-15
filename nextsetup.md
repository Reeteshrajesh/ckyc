# Loki, Promtail, and Grafana Setup on Kubernetes

This guide describes how to deploy **Loki**, **Promtail**, and **Grafana** using the **loki-stack** Helm chart.

---

## Prerequisites

* Kubernetes Cluster (Minikube, EKS, etc.)
* `kubectl` configured
* Helm v3 installed

---

## Steps to Deploy Loki, Promtail, and Grafana

### 1. Add Grafana Helm Repository

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### 2. Check Available Charts

```bash
helm search repo loki
```

### 3. Download Default Values

```bash
helm show values grafana/loki-stack > values.yaml
```

### 4. Update `values.yaml` as Needed

* Enable Grafana:

  ```yaml
  grafana:
    enabled: true
  ```
* Optionally, update Loki and Promtail image versions if needed:

  ```yaml
  loki:
    image:
      tag: <desired-loki-version>

  promtail:
    image:
      tag: <desired-promtail-version>
  ```

### 5. Install Loki Stack with Custom Values

```bash
helm install --values values.yaml loki grafana/loki-stack
```

### 6. Access Grafana UI

Forward Grafana service port:

```bash
kubectl port-forward svc/loki-grafana 3000:80
```

### 7. Get Grafana Admin Password

```bash
kubectl get secret loki-grafana -o jsonpath="{.data.admin-password}" | base64 --decode
```

### 8. Get Promtail Configuration (Optional)

If you need to inspect the deployed Promtail configuration:

```bash
kubectl get secret loki-promtail -o jsonpath="{.data.promtail\.yaml}" | base64 --decode > promtail.yaml
```

---

## Default URLs

* **Grafana UI**: [http://localhost:3000](http://localhost:3000)

  * **Username**: `admin`
  * **Password**: Retrieved from Step 7

---

## Useful Commands

### Uninstall Loki Stack

```bash
helm uninstall loki
```

### Clean up PVCs (optional)

```bash
kubectl delete pvc -l app.kubernetes.io/name=loki
```

---

## Notes

* This setup is suitable for **testing** and **basic usage**.
* For **production**, consider using separate charts for Loki, Promtail, and Grafana with persistent storage and scaling configurations.


-------------
--------------
----------------

## ✅ **Step-by-Step: Loki Logs to S3 in EKS (Production Ready)**

---

## ✅ 1. **Create IAM Role for Loki (IRSA)**

### 🟢 a. Get OIDC Provider for EKS:

```bash
aws eks describe-cluster --name <your-cluster-name> --query "cluster.identity.oidc.issuer" --output text
```

### 🟢 b. Create IAM Policy for S3 Access:

Save this as `loki-s3-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::liquide-loki-logs-bucket",
        "arn:aws:s3:::liquide-loki-logs-bucket/*"
      ]
    }
  ]
}
```

### 🟢 c. Create IAM Role for Loki IRSA:

```bash
aws iam create-policy --policy-name LokiS3AccessPolicy --policy-document file://loki-s3-policy.json
```

Use eksctl or AWS CLI to create role:

```bash
eksctl create iamserviceaccount \
  --name loki \
  --namespace default \
  --cluster <your-cluster-name> \
  --attach-policy-arn arn:aws:iam::<account-id>:policy/LokiS3AccessPolicy \
  --approve \
  --override-existing-serviceaccounts
```

---

## ✅ 2. **Update Helm values.yaml for Loki**

Here's your **production-ready Loki values.yaml snippet**:

```yaml
loki:
  serviceAccount:
    create: true
    name: loki
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/eksctl-mycluster-loki-irsa-role

  limits_config:
    retention_period: 168h
    max_chunk_age: 1m

  commonConfig:
    replication_factor: 1

  schemaConfig:
    configs:
      - from: 2023-01-01
        store: boltdb-shipper
        object_store: s3
        schema: v12
        index:
          prefix: index_
          period: 24h

  storage_config:
    boltdb_shipper:
      active_index_directory: /data/loki/index
      cache_location: /data/loki/cache
      shared_store: s3
    aws:
      bucketnames: liquide-loki-logs-bucket
      region: ap-south-1
      s3forcepathstyle: false

  ingester:
    lifecycler:
      ring:
        kvstore:
          store: memberlist
        replication_factor: 1
    chunk_idle_period: 1m
    chunk_retain_period: 5m
    max_transfer_retries: 0

  memberlist:
    join_members:
      - '{{ include "loki.fullname" . }}-memberlist'

  compactor:
    shared_store: s3
    working_directory: /data/loki/compactor
    retention_enabled: true
    compaction_interval: 5m
    retention_delete_delay: 2h
    retention_period: 168h

  persistence:
    enabled: true
    size: 10Gi
    storageClassName: gp2

```

---

## ✅ 3. **Promtail Configuration (Scraping Logs)**

Keep Promtail as is:

```yaml
promtail:
  enabled: true
  config:
    logLevel: info
    serverPort: 3101
    clients:
      - url: http://loki:3100/loki/api/v1/push
```
