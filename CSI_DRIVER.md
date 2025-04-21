# AWS Secrets CSI Helm Test Setup

This setup allows Kubernetes pods to securely access secrets and parameters stored in:

- **AWS Secrets Manager** – for credentials, API keys, etc.
- **AWS Systems Manager Parameter Store** – for config values
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
csi-secrets-app/
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
secretArn: ""  # Optional: use ARN instead of name

serviceAccount:
  name: csi-secrets-sa
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/csi-secrets-role-dev

secretProviderClass:
  name: aws-secrets
  provider: aws

secrets:
  enabled: true
  mountPath: /mnt/secrets-store
  secretProviderClass: aws-secrets

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
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

➡️ After that line, insert the `volumeMounts`:

```yaml
          volumeMounts:
            - name: secrets-store
              mountPath: {{ .Values.secrets.mountPath }}
              readOnly: true
```

Then below your existing:

```yaml
      {{- with .Values.tolerations }}
```

➡️ Add the `volumes` section:

```yaml
      volumes:
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: {{ .Values.secrets.secretProviderClass }}
```

---

### ✅ Deployment Snippet (Final Additions)

```yaml
          volumeMounts:
            - name: secrets-store
              mountPath: {{ .Values.secrets.mountPath }}
              readOnly: true
...
      volumes:
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: {{ .Values.secrets.secretProviderClass }}
```

---

### Install the Secrets Store CSI Driver (if not already)

```bash
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts

helm install -n kube-system csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver
```


---

### 🔧 Install the AWS Provider for the CSI Driver

```bash
helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws

helm install -n kube-system secrets-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws
```

---

### 🛡️ Ensure IAM Role Exists (IRSA) (we already have)

Your `ServiceAccount` needs to be annotated with an IAM role that has permission to access AWS Secrets Manager.  
Here’s the IAM policy example:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:<region>:<account-id>:secret:<secret-name>*"
    }
  ]
}
```

---

### 📦 Package & Install Your Helm Chart

```bash
**for excisting namespace**
helm install my-app ./csi-secrets-app \
  --namespace dev \
  --set namespace=dev \
  --set secretName=my-app-secret \
  --set serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=arn:aws:iam::<account-id>:role/csi-secrets-role-dev

----
helm install my-app ./csi-secrets-app \
  --namespace dev \
  --create-namespace \
  --set namespace=dev \
  --set secretName=my-app-secret \
  --set serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=arn:aws:iam::<account-id>:role/csi-secrets-role-dev
```

> You can swap `--set secretName=` with `--set secretArn=` if you’re using ARNs instead of names.

---

### Verify the Deployment

```bash
kubectl get pods -n dev

kubectl exec -n dev -it <your-pod-name> -- ls /mnt/secrets-store

kubectl exec -n dev -it <your-pod-name> -- cat /mnt/secrets-store/<your-secret-key>
```

---

### 🧼 Step 6: Cleanup (Optional)

```bash
helm uninstall my-app --namespace dev
```
