# 🔔 Real-time Kubernetes Pod Alerts to Slack using kubernetes-event-exporter without using Prometheus/Grafana

This guide walks you through setting up the lightweight [`kubernetes-event-exporter`](https://github.com/resmoio/kubernetes-event-exporter) to receive **real-time Slack alerts** when your Kubernetes pods:

- Enter `Pending` state (`FailedScheduling`)
- Crash (`CrashLoopBackOff`)
- Fail to pull images (`ImagePullBackOff`)
- Or any other failure event

No Prometheus or Grafana required.

---

## ✅ What You'll Get

- Instant Slack messages when pods fail
- Filters to include only important pod events
- Minimal setup using Helm
- Fully customizable alert messages

---

## 🛠️ Prerequisites

- Kubernetes cluster access
- [Helm](https://helm.sh/docs/intro/install/) installed
- A **Slack webhook URL** for the alerts

---

## 🪝 Step 1: Create a Slack Webhook

1. Go to: https://my.slack.com/services/new/incoming-webhook/
2. Choose a channel (e.g. `#k8s-alerts`)
3. Copy the webhook URL — it looks like:  
   `https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX`

---

## 📦 Step 2: Add the Helm Repo

```bash
helm repo add kiwigrid https://kiwigrid.github.io
helm repo update
```

---

## ⚙️ Step 3: Create Custom Config (`event-exporter-values.yaml`)

Save this YAML file:

```yaml
config:
  logLevel: "info"

  route:
    routes:
      - match:
          - receiver: "slack"
        drop:
          - involvedObject.kind != "Pod"  # Only alert on Pod-related events
        continue: false

  receivers:
    - name: "slack"
      slack:
        webhook: "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
        username: "k8s-event-exporter"
        icon_emoji: ":kubernetes:"
        message:
          text: |
            *[{{ .InvolvedObject.Namespace }}/{{ .InvolvedObject.Name }}]*: 
            *{{ .Reason }}* - {{ .Message }}
```

> 🔁 **Customize** message format or add filters (e.g., on `reason` like `CrashLoopBackOff`, `ImagePullBackOff`, etc.)

---

## 🚀 Step 4: Install the Event Exporter

```bash
helm install k8s-event-exporter kiwigrid/kubernetes-event-exporter \
  --namespace monitoring --create-namespace \
  -f event-exporter-values.yaml
```

---

## ✅ Example Slack Messages

```
[default/my-api-7c7c57bd95-sf5jp]: CrashLoopBackOff - Back-off restarting failed container
[default/nginx-xyz123]: FailedScheduling - 0/3 nodes are available: Insufficient memory
[payments/payment-processor]: ImagePullBackOff - Failed to pull image "xyz/payment:latest"
```
---------------------
---------------------

## ✅ By Default: Helm Chart Takes Care of It

If you install `kubernetes-event-exporter` via the **official Helm chart** like this:

```bash
helm install k8s-event-exporter kiwigrid/kubernetes-event-exporter \
  --namespace monitoring --create-namespace
```

👉 **YES**, it **automatically creates** the necessary:

- **ServiceAccount**
- **ClusterRole**
- **ClusterRoleBinding**

So **you don't need to do anything extra manually.** It's all handled inside the Helm chart.

---

## 🔐 What Permissions Are Required?

The event exporter **watches Kubernetes events**, so it needs read-only access to the `events` resource.

Here's what the underlying `ClusterRole` allows:

```yaml
rules:
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]
```

That's it — simple and safe.

---

## 🤝Summary in Hindi:

> Agar aap Helm chart se install kar rahe ho, to `ServiceAccount`, `Role`, aur `RoleBinding` ki tension lene ki zaroorat **nahi** hai.  
> Chart khud sab kuch bana deta hai. Bas webhook configure karke use karna shuru kar do. 🔥

----------------------
----------------------
## 🧼 Cleanup

To uninstall:

```bash
helm uninstall k8s-event-exporter -n monitoring
```

---

## 🧠 Tips & Tricks

- **Filter by reason** using:
  ```yaml
  match:
    - reason: "CrashLoopBackOff"
  ```
- Add more `receivers` to send alerts to **multiple Slack channels** or **email**.
- Extend message fields using Go templating:  
  https://github.com/resmoio/kubernetes-event-exporter/blob/main/docs/configuration.md

---

## 📚 References

- [kubernetes-event-exporter GitHub](https://github.com/resmoio/kubernetes-event-exporter)
- [Helm Chart Repo](https://github.com/kiwigrid/helm-charts/tree/main/charts/kubernetes-event-exporter)
- [Slack Webhook Setup](https://api.slack.com/messaging/webhooks)

---

## 📞 Need Help?

If you're not receiving alerts:
- Check your Slack webhook config
- Run `kubectl get events --all-namespaces` to confirm events exist
- Review pod logs: `kubectl logs -l app.kubernetes.io/name=kubernetes-event-exporter -n monitoring`
