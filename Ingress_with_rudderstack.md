# ✅ Exposing RudderStack on EKS via HTTPS using NGINX Ingress & cert-manager

---

## 📁 Prerequisites

* RudderStack is already deployed in the `eventmanage` namespace.
* Kubernetes cluster running (e.g., EKS).
* Helm installed.
* You own a public domain (e.g., `yourdomain.com`).
* DNS is managed anywhere except Cloudflare (we are not using Cloudflare here).

---

## 1️⃣ Install NGINX Ingress Controller (public LoadBalancer)

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.publishService.enabled=true
```

---

## 2️⃣ Get NGINX LoadBalancer External IP

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

Output example:

```
NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
ingress-nginx-controller   LoadBalancer   yy.yyy.yyy.yy   xx.xx.xxx.xx    80:xxxx/TCP,443:xxxx/TCP
```

> Copy the `EXTERNAL-IP` (`xx.xx.xxx.xx` in this example)

---

## 3️⃣ Create DNS Record

### On your DNS provider (e.g., Route 53, Namecheap, GoDaddy):

* Create an `A` Record:

  * **Name:** `rudderstack.yourdomain.com`
  * **Type:** A
  * **Value:** `xx.xx.xxx.xx` (your NGINX LoadBalancer IP)

> ⚠️ **DO NOT use proxy mode or CDN for the domain.** Let DNS resolve directly to the LoadBalancer.

---

## 4️⃣ Install cert-manager (to get free HTTPS from Let's Encrypt)

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
```

Wait a few seconds and confirm it’s running:

```bash
kubectl get pods -n cert-manager
```

---

## 5️⃣ Create ClusterIssuer (for Let's Encrypt production certs)

Save this to `clusterissuer.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
```

Apply it:

```bash
kubectl apply -f clusterissuer.yaml
```

---

## 6️⃣ Create RudderStack Ingress (with TLS enabled)

Save this as `rudderstack-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rudderstack-ingress
  namespace: eventmanager
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  rules:
    - host: rudderstack.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-release-rudderstack
                port:
                  number: 80
  tls:
    - hosts:
        - rudderstack.yourdomain.com
      secretName: rudderstack-tls
```

> ✅ Replace:
>
> * `yourdomain.com` with your real domain
> * `my-release-rudderstack` with the name of your RudderStack service (`kubectl get svc -n eventmanage`)

Apply it:

```bash
kubectl apply -f rudderstack-ingress.yaml
```

---

## 7️⃣ Confirm TLS Certificate Issuance

```bash
kubectl describe certificate -n eventmanage
```

You should see:

* **Ready:** True
* **Secret Name:** `rudderstack-tls`

---

## 8️⃣ Verify Access

Use `curl` or browser:

```bash
curl -I https://rudderstack.yourdomain.com
```

Expected output:

```http
HTTP/2 200
server: nginx/...
...
```

---
