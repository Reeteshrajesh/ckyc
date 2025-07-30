# digio-ckyc-helm

Helm chart to deploy the **Digio CKYC microservice** to a Kubernetes cluster.  
Includes configuration for secure mounting of keystore files via Kubernetes secrets.

---

## 📁 Folder Structure

```

digio-ckyc-helm/
├── Chart.yaml
├── README.md
├── templates/
│   ├── \_helpers.tpl
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── secret.yaml
│   └── ingress.yaml (optional)
├── ckyc-keys/
│   ├── digio\_ckyc\_key.jks
│   └── digio\_ckyc\_key.pem
├── values.yaml

````

---

## ⚙️ Chart Configuration

This Helm chart includes:

- Deployment configuration
- Service (ClusterIP by default)
- Secret creation from mounted key files
- Volume mounts from Kubernetes secrets

---

## 🔐 Secret Handling

Secrets are created using:
```yaml
{{ (.Files.Get "ckyc-keys/digio_ckyc_key.jks") | b64enc }}
````

Files under `ckyc-keys/` are automatically encoded and injected into a Kubernetes `Secret`.

> Ensure `ckyc-keys/` is present **before packaging** the Helm chart.

---

## 🚀 Usage

### 1. Install Helm (if not already)

```bash
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
```

### 2. Package the chart

```bash
helm package digio-ckyc-helm
```

Or install directly from folder:

```bash
helm install digio-ckyc ./digio-ckyc-helm -n your-namespace
```

> Make sure the target namespace exists:

```bash
kubectl create ns your-namespace
```

---

## 🧪 Testing Deployment

```bash
kubectl get pods -n your-namespace
kubectl logs -l app=digio-ckyc -n your-namespace
```

Check if the secret was mounted:

```bash
kubectl exec -it <pod-name> -n your-namespace -- ls /app/secure-keys
```

You should see:

```
digio_ckyc_key.jks
digio_ckyc_key.pem
```

---

## 🛠 Customization via `values.yaml`

| Key                | Type   | Description                 | Default           |
| ------------------ | ------ | --------------------------- | ----------------- |
| `replicaCount`     | int    | Number of pod replicas      | `1`               |
| `image.repository` | string | Container image repo        | `your-repo/ckyc`  |
| `image.tag`        | string | Container image tag         | `latest`          |
| `service.port`     | int    | Port exposed by the service | `8080`            |
| `namespace`        | string | Kubernetes namespace        | `default`         |
| `resources`        | object | CPU/memory limits/requests  | See `values.yaml` |
| `env`              | list   | Environment variables       | Key-value pairs   |

Edit `values.yaml` to match your environment.

---

## 🔄 Upgrade

```bash
helm upgrade digio-ckyc ./digio-ckyc-helm -n your-namespace
```

---

## 🧼 Uninstall

```bash
helm uninstall digio-ckyc -n your-namespace
```

---

## ✅ Best Practices

* Store actual key files (`.jks`, `.pem`) outside Git and mount them dynamically during deployment or CI.
* Use sealed secrets or external secret managers (e.g., AWS Secrets Manager) in production.
* Use RBAC and namespace isolation to protect sensitive mounts.

---

## 👥 Maintainers

| Name          | Email                      |
| ------------- | -------------------------- |
| Reetesh Kumar | `uttamreetesh@gmail.com`   |

---

## 📄 License

MIT — use responsibly.
