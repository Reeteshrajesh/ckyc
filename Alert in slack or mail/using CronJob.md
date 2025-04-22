# 🚨 Kubernetes Pending Pod Alert to Slack (No Prometheus)

This setup will automatically monitor for any **Pending pods** in your Kubernetes cluster and send an alert to **Slack** every 5 minutes using a Kubernetes **CronJob** — no need for Prometheus or Grafana.

---

## 📦 What This Does

- Checks for any pods in `Pending` state across **all namespaces**.
- If found, sends a Slack message using a **Slack Incoming Webhook**.
- Runs automatically every 5 minutes via a **Kubernetes CronJob**.

---

## 🔧 Prerequisites

1. A Kubernetes cluster with `kubectl` access.
2. A Slack workspace and a **Slack Incoming Webhook URL**.
3. Kubernetes access permissions to **list pods in all namespaces**.

---

## 🪝 Step 1: Create Slack Webhook

1. Go to [Slack Incoming Webhooks](https://my.slack.com/services/new/incoming-webhook/).
2. Choose a target channel.
3. Copy the Webhook URL (it looks like: `https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX`).

---

## 🛠️ Step 2: Create CronJob YAML

Save the following as `pending-pod-alert-cronjob.yaml`.

> **Replace** `YOUR/SLACK/WEBHOOK` with your actual Slack Webhook URL.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pending-pod-checker
  namespace: monitoring
spec:
  schedule: "*/5 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: check-pod-status
            image: bitnami/kubectl:latest
            command:
              - /bin/sh
              - -c
              - |
                apk add --no-cache curl jq > /dev/null

                ALERTS=""

                # Check Pending Pods
                PENDING=$(kubectl get pods --all-namespaces --field-selector=status.phase=Pending -o json)
                PENDING_COUNT=$(echo "$PENDING" | jq '.items | length')
                if [ "$PENDING_COUNT" -gt 0 ]; then
                  ALERTS="${ALERTS}\n*Pending Pods:*"
                  echo "$PENDING" | jq -r '.items[] | "- \(.metadata.namespace)/\(.metadata.name)"' >> /tmp/pod_alerts.txt
                  ALERTS="${ALERTS}\n$(cat /tmp/pod_alerts.txt)"
                fi

                # Check CrashLoopBackOff and ImagePullBackOff
                ERRORS=$(kubectl get pods --all-namespaces -o json | jq -r '
                  .items[] |
                  . as $pod |
                  .status.containerStatuses[]? |
                  select(.state.waiting.reason == "CrashLoopBackOff" or .state.waiting.reason == "ImagePullBackOff") |
                  "- \($pod.metadata.namespace)/\($pod.metadata.name): \(.state.waiting.reason)"
                ')
                if [ ! -z "$ERRORS" ]; then
                  ALERTS="${ALERTS}\n*Backoff Pods:*"
                  ALERTS="${ALERTS}\n$ERRORS"
                fi

                # Send alert if any found
                if [ ! -z "$ALERTS" ]; then
                  curl -X POST -H 'Content-type: application/json' \
                    --data "{\"text\":\"⚠️ *Pod Alert Report:*\n$ALERTS\"}" \
                    https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK
                fi
            env:
            - name: KUBECONFIG
              value: /root/.kube/config
          restartPolicy: OnFailure
          serviceAccountName: pending-alert-sa

```

---

## 🔐 Step 3: Add RBAC (Permissions)

Create the required **ServiceAccount**, **ClusterRole**, and **ClusterRoleBinding** so the job can read pod statuses.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pending-alert-sa
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pending-pod-check-role
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pending-pod-check-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pending-pod-check-role
subjects:
  - kind: ServiceAccount
    name: pending-alert-sa
    namespace: monitoring
```

---

## 🚀 Step 4: Apply All Resources

```bash
# Create namespace if not exists
kubectl create namespace monitoring

# Apply RBAC
kubectl apply -f rbac.yaml

# Apply CronJob
kubectl apply -f pending-pod-alert-cronjob.yaml
```

---

## ✅ Result

Every 5 minutes, the cluster checks for `Pending` pods.  
If it finds any, a message like this will be sent to Slack:

```
:warning: 3 pod(s) are in Pending state!
```

---

## 📌 Optional Improvements

- Send email alerts using Mailgun/SendGrid.
- Add retry logic or backoff in the script.
- Log alerts to a file or database.
- Extend check to include `CrashLoopBackOff` or `ImagePullBackOff`.

---

## 🧼 Cleanup

To remove everything:

```bash
kubectl delete -f pending-pod-alert-cronjob.yaml
kubectl delete -f rbac.yaml
```

---

## 📞 Support

Feel free to open an issue or contact your DevOps team if this fails to alert or needs improvements.
```
