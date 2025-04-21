Great! Since you're **using localhost with port-forwarding** instead of a real domain, you don’t need Ingress, TLS, or DNS setup. Let’s simplify everything for local development.

---

# 🧪 RudderStack Local CDP Setup (Using Port Forward & Amplitude)

## 🔧 Prerequisites

- Kubernetes cluster running locally (e.g., kind, minikube, k3s)
- Helm installed
- kubectl access to the cluster

---

## 📥 Step 1: Install RudderStack with Helm (Local Dev)

### 1.1 Add Helm Repo

```bash
helm repo add rudderstack https://rudderstack.github.io/helm-charts
helm repo update
```

### 1.2 Create `rudder-local-values.yaml`

```yaml
replicaCount: 1

ingress:
  enabled: false

env:
  - name: LOG_LEVEL
    value: "debug"

postgres:
  enabled: true
  postgresqlPassword: rudderpass
  persistence:
    enabled: true
    size: 2Gi

redis:
  enabled: true
  auth:
    enabled: false

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 300m
    memory: 512Mi
```

---

### 1.3 Install RudderStack

```bash
helm install rudderstack rudderstack/rudderstack \
  --namespace rudderstack \
  --create-namespace \
  -f rudder-local-values.yaml
```

---

## 🚪 Step 2: Port Forward to Access the UI

```bash
kubectl port-forward svc/rudderstack-data-plane 8080:80 -n rudderstack
```

Now open [http://localhost:8080](http://localhost:8080) in your browser.

---

## 🟢 Step 3: Create a Source

1. In the RudderStack dashboard → click **Sources** → **Add Source**
2. Choose **JavaScript**
3. Name it e.g., `Local Web App`
4. Copy the **WRITE KEY**

---

## 🧑‍💻 Step 4: Add SDK to Your Web App

Add this to your local frontend:

```html
<script src="https://cdn.rudderlabs.com/v1.1/rudder-analytics.min.js"></script>
<script>
  rudderanalytics.load("YOUR_WRITE_KEY", "http://localhost:8080");

  rudderanalytics.identify("user123", {
    email: "user@example.com",
    name: "Test User"
  });

  rudderanalytics.track("Button Clicked", {
    label: "Get Started"
  });
</script>
```

✅ Make sure `WRITE_KEY` matches the one from your source.

---

## 🎯 Step 5: Add Amplitude as a Destination

1. Go to **Destinations** → **Add Destination**
2. Choose **Amplitude**
3. Paste your **Amplitude API Key**
4. Link it to your source (`Local Web App`)
5. Enable it

---

## ✅ Test It All

- Open your local frontend page
- Trigger the event (`Button Clicked`)
- Go to **Live Events** in RudderStack to verify
- Confirm it appears in Amplitude

---

## 🧹 Summary

| Task                    | Status |
|-------------------------|--------|
| Helm install (local)    | ✅     |
| Port forward setup      | ✅     |
| Source & SDK configured | ✅     |
| Amplitude hooked up     | ✅     |
| Events flowing          | ✅     |

---

Need help writing a test HTML page or checking Amplitude event status? I got you!
