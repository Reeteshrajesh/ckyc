

# 🚀 CKYC Project Deployment with Helm & ArgoCD

This project deploys the CKYC Integration Service using Helm and ArgoCD on a Kubernetes cluster.

---

## 📁 Folder Structure

```bash
ckyc-project/ 
│
├── charts/
│   └── ckyc/                         # Helm chart for CKYC
│       ├── Chart.yaml               # Helm metadata
│       ├── values.yaml              # Default values (edit for production)
│       ├── templates/
│       │   ├── deployment.yaml      # Main Deployment manifest
│       │   ├── service.yaml         # Service definition
│       │   ├── configmap.yaml       # For ckyc-properties.yml
│       │   ├── secret.yaml          # For .jks, pem, certs, env values
│       │   ├── _helpers.tpl         # Helper templates
│       │   └── NOTES.txt            # Optional Helm usage notes
│       └── files/                   # (Optional) extra files used in templates
│
├── ckyc/
│   ├── digio-ckyc/
│   │   └── ckyc-properties.yml      # App config (used in ConfigMap)
│   └── ckyc-keys/
│       ├── digio.jks
│       ├── digio_pub.pem
│       ├── digio_key.pem
│       ├── digio_cert.pem
│       ├── other1.key
│       └── other2.cert
│
├── argocd/
│   └── app-ckyc.yaml                # ArgoCD Application manifest
```

---

## 🧩 Install ArgoCD (Once)

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml 
```

---

## 🌐 Port Forward to Access ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 
```

> 🔗 Access the UI at: [https://localhost:8080](https://localhost:8080)

---

## 🔐 Login to ArgoCD

```bash
# Default username: admin
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

---

## 🚀 Deploy CKYC via ArgoCD

1. Create the application manifest in `argocd/app-ckyc.yaml`
2. Apply it using:

```bash
kubectl apply -f argocd/app-ckyc.yaml
```

ArgoCD will automatically sync the Helm chart and deploy your CKYC service.





kubectl create namespace argocd\nkubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  179  kubectl get pods -n argocd
  180  kubectl get svc -n argocd
  181  kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0 &
  182  kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
