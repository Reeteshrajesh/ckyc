# AWS Secrets CSI Helm Test Setup

This guide helps you verify AWS Secrets Store CSI driver integration in multiple Kubernetes namespaces (`dev`, `qa`, `stage`, `prod`) using a simple Helm chart.

---

## ✅ What’s Included

| Resource | Purpose |
|---------|---------|
| `ServiceAccount` | With IRSA role for accessing AWS Secrets Manager |
| `SecretProviderClass` | Defines AWS secret(s) to mount |
| `Pod` | BusyBox container for secret access verification |

---

## 🚀 Quick Start

### 1. Chart Directory Structure

```
csi-secrets-test/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── serviceaccount.yaml
    ├── secretproviderclass.yaml
    └── pod.yaml
```

---

### 2. Helm Chart Files

#### `Chart.yaml`

```yaml
apiVersion: v2
name: csi-secrets-test
description: A test setup to verify AWS Secrets CSI integration
version: 0.1.0
```

#### `values.yaml`

```yaml
namespace: dev
secretName: my-app-secret

serviceAccount:
  name: csi-secrets-sa
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/csi-secrets-role-dev

secretProviderClass:
  name: aws-secrets
  provider: aws

pod:
  name: csi-test-pod
  image: busybox
  command: ["sleep", "3600"]
```

#### `templates/serviceaccount.yaml`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.serviceAccount.name }}
  namespace: {{ .Values.namespace }}
  annotations:
    {{- toYaml .Values.serviceAccount.annotations | nindent 4 }}
```

#### `templates/secretproviderclass.yaml`

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: {{ .Values.secretProviderClass.name }}
  namespace: {{ .Values.namespace }}
spec:
  provider: {{ .Values.secretProviderClass.provider }}
  parameters:
    objects: |
      - objectName: "{{ .Values.secretName }}"
        objectType: "secretsmanager"
```

#### `templates/pod.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ .Values.pod.name }}
  namespace: {{ .Values.namespace }}
spec:
  serviceAccountName: {{ .Values.serviceAccount.name }}
  containers:
  - name: test
    image: {{ .Values.pod.image }}
    command: {{ .Values.pod.command }}
    volumeMounts:
    - name: secrets-store
      mountPath: "/mnt/secrets-store"
      readOnly: true
  volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: {{ .Values.secretProviderClass.name }}
```

---

## 🧪 Deploying Per Namespace

```bash
helm install test-secrets ./csi-secrets-test \
  --namespace dev \
  --create-namespace \
  --set namespace=dev \
  --set secretName=my-app-secret \
  --set serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=arn:aws:iam::<account-id>:role/csi-secrets-role-dev
```

Repeat for other namespaces:

```bash
helm install test-secrets-qa ./csi-secrets-test \
  --namespace qa \
  --create-namespace \
  --set namespace=qa \
  --set secretName=my-app-secret \
  --set serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=arn:aws:iam::<account-id>:role/csi-secrets-role-qa
```

---

## ✅ Verifying Secret Mount

```bash
kubectl exec -n dev -it csi-test-pod -- ls /mnt/secrets-store
kubectl exec -n dev -it csi-test-pod -- cat /mnt/secrets-store/my-app-secret
```

---

## 🧹 Cleanup

```bash
helm uninstall test-secrets -n dev
helm uninstall test-secrets-qa -n qa
```

---

## 🧠 Pro Tip

You can wrap this into CI tests or automate secret validation across environments!
