
### 1. **KEDA (Kubernetes Event-Driven Autoscaling)**

* **Purpose:**
  Autoscaling of Kubernetes **workloads (pods)** based on external event metrics, not just CPU or memory.

* **What it scales:**
  **Pods** (workloads, deployments, statefulsets, etc.)

* **How it works:**

  * KEDA monitors external event sources like Kafka queues, RabbitMQ, Azure Event Hubs, Prometheus metrics, HTTP requests, etc.
  * When a trigger threshold is crossed (e.g., queue length > X), KEDA scales the number of pods up or down accordingly.
  * Works by deploying a custom controller and metrics adapter to expose external metrics to the Kubernetes Horizontal Pod Autoscaler (HPA).
  * Supports scaling down to zero pods (useful for serverless-like behavior).

* **Use case:**
  Event-driven workloads that need to scale based on message queue length, event counts, or custom metrics.

---

### 2. **Karpenter**

* **Purpose:**
  **Node autoscaling** in Kubernetes — automatically provisions and manages nodes (VMs) based on pod scheduling needs.

* **What it scales:**
  **Nodes** (worker machines in the cluster)

* **How it works:**

  * Karpenter watches unschedulable pods and provisions new nodes that best fit the pods’ resource requests and constraints.
  * It uses cloud provider APIs (e.g., AWS EC2 API) to launch instances dynamically and can terminate underutilized nodes.
  * It’s flexible and supports advanced features like provisioning different instance types, using spot instances, and setting custom provisioning strategies.
  * It can respond quickly to changes and optimize node resources.

* **Use case:**
  Efficient, cloud-native node provisioning and autoscaling in Kubernetes clusters, especially on AWS.

---

### 3. **Cluster Autoscaler**

* **Purpose:**
  Another **node autoscaler** that adjusts the number of nodes based on pod scheduling pressure.

* **What it scales:**
  **Nodes**

* **How it works:**

  * Cluster Autoscaler watches pods that can’t be scheduled due to lack of resources and adds nodes to fix that.
  * It also scales down nodes that are underutilized and whose pods can be moved to other nodes.
  * Works with cloud providers like AWS, GCP, Azure, etc., via their managed autoscaling groups (like AWS ASG).
  * Scaling decisions are based mainly on pending pods and node utilization.

* **Use case:**
  General purpose node autoscaling integrated with cloud-managed autoscaling groups, widely used in many Kubernetes setups.

---

## Summary Table

| Feature            | KEDA                      | Karpenter                          | Cluster Autoscaler                           |
| ------------------ | ------------------------- | ---------------------------------- | -------------------------------------------- |
| Scales             | Pods (workloads)          | Nodes                              | Nodes                                        |
| Metrics            | External event-driven     | Pod scheduling & resource requests | Pod scheduling & utilization                 |
| Scale to zero pods | Yes                       | No                                 | No                                           |
| Cloud integration  | No direct cloud infra ops | Deep cloud API integration         | Uses cloud managed autoscaling groups (ASGs) |
| Provisioning       | No                        | Yes (creates nodes dynamically)    | No (manages existing ASGs)                   |
| Use case           | Event-driven apps         | Dynamic node provisioning          | Autoscaling nodes in managed clusters        |

---

### To put it simply:

* **KEDA** = *scales your pods* based on custom event metrics beyond CPU/memory.
* **Karpenter** = *scales your nodes* by launching new VMs or instances dynamically and flexibly.
* **Cluster Autoscaler** = *scales your nodes* by managing existing autoscaling groups, adding/removing nodes based on pod demand.

------
------
------
------


# KEDA Setup in a New EKS Cluster

---

## Prerequisites

1. **EKS cluster up and running**

   * Kubernetes version 1.21+ (recommended)
   * `kubectl` configured and connected to your EKS cluster
   * `helm` installed (v3+)

2. **IAM Permissions**

   * Your user/role needs permissions to install CRDs and deploy apps on the cluster.

3. **Optional: External Event Source** (for actual scaling triggers)

   * For testing, we can use a simple built-in scaler like CPU or a dummy scaler.

---

## Step 1: Configure kubectl for your EKS cluster

Make sure you can talk to your cluster:

```bash
aws eks --region <region> update-kubeconfig --name <cluster-name>
kubectl get nodes
```

You should see your nodes listed.

---

## Step 2: Install KEDA via Helm

KEDA provides an official Helm chart, which is the easiest way to install.

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace
```

This will:

* Create a namespace called `keda`
* Install KEDA operator and CRDs

---

## Step 3: Verify KEDA installation

```bash
kubectl get pods -n keda
```

You should see something like:

```
NAME                      READY   STATUS    RESTARTS   AGE
keda-operator-xxxxxx      1/1     Running   0          1m
```

---

## Step 4: Create a simple test deployment with KEDA autoscaling

Here’s a minimal example that uses the built-in CPU scaler:

### Deployment YAML (test-app.yaml)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keda-test-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keda-test-app
  template:
    metadata:
      labels:
        app: keda-test-app
    spec:
      containers:
        - name: app
          image: nginx
          resources:
            requests:
              cpu: 100m
            limits:
              cpu: 500m
```

### ScaledObject YAML (scaledobject.yaml)

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: keda-test-app-scaledobject
spec:
  scaleTargetRef:
    name: keda-test-app
  minReplicaCount: 1
  maxReplicaCount: 5
  triggers:
  - type: cpu
    metadata:
      type: Utilization
      value: "50"
```

---

Apply these manifests:

```bash
kubectl apply -f test-app.yaml
kubectl apply -f scaledobject.yaml
```

---

## Step 5: Test scaling behavior

* Check pod count:

```bash
kubectl get pods -l app=keda-test-app
```

* To trigger scaling, increase CPU load inside the pod or scale manually and watch KEDA scale based on CPU.

---

## Optional: Test event-driven scaling with external triggers

If you want to test more complex scalers (e.g., RabbitMQ, Kafka), you’ll need:

* The event source running and accessible
* Corresponding trigger config in `ScaledObject`

But the CPU scaler is good for a quick smoke test.

---

# Summary of commands:

```bash
aws eks --region <region> update-kubeconfig --name <cluster-name>

helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace

kubectl apply -f test-app.yaml
kubectl apply -f scaledobject.yaml
```



----
----
----

## KEDA kaam karne ka tarika (How KEDA works)

1. **Monitor karta hai external events ya metrics ko**

   * KEDA continuously monitor karta hai kuch **external event sources** (jaise message queues — Kafka, RabbitMQ, AWS SQS), ya cluster ke andar ke **metrics** (CPU usage, memory usage, custom Prometheus metrics, etc).
   * Ye monitoring karne ke liye KEDA apna **Scaler Controller** chalata hai.

2. **Trigger define hota hai**

   * Aap `ScaledObject` naam ka Kubernetes resource create karte hain jisme aap batate ho ki kaunse pod ko scale karna hai, minimum aur maximum replicas kitne chahiye, aur kaunsa trigger (metric ya event) use karna hai.
   * Example: "Jab queue length 100 se zyada ho, toh pods ko 5 tak badhao."

3. **Autoscaling decision leta hai**

   * Jab KEDA ko lage ki trigger criteria fulfill ho raha hai (jaise queue mein messages badh gaye hain ya CPU load high hai), toh wo Kubernetes HPA (Horizontal Pod Autoscaler) ko inform karta hai.
   * HPA us hisaab se **pods ka number badhata ya kam karta hai**.

4. **Scale to zero bhi kar sakta hai**

   * Agar events nahi aa rahe ya demand zero ho jaye, toh KEDA pods ko **zero tak scale down kar sakta hai**, matlab workload bilkul band bhi kar sakta hai — ye bahut useful hai serverless-like scenarios mein.

5. **Kaam karta hai controller and metrics adapter ke through**

   * KEDA ke paas ek **operator/controller** hota hai jo continuously triggers ko monitor karta hai.
   * Aur ek **metrics adapter** hota hai jo external metrics ko Kubernetes metrics API ke format mein HPA ko provide karta hai.

---

### Example flow:

* Aapka app ek RabbitMQ queue se messages process karta hai.
* KEDA monitor karta hai queue length.
* Jab queue length badh jaata hai, KEDA pod replicas badha deta hai, taaki zyada messages jaldi process ho sakein.
* Jab queue khatam ho jaata hai, KEDA pods ko dheere-dheere kam kar deta hai, ya zero tak le jaata hai.

---

### Summary:

| Step                    | Description                                         |
| ----------------------- | --------------------------------------------------- |
| Monitor events/metrics  | External triggers ya CPU usage dekhna               |
| Check trigger condition | Scale up/down karne ke liye threshold compare karna |
| Communicate with HPA    | Pods ke replicas badhana/ghatana                    |
| Scale pods              | Actual pod count change karna                       |

---

KEDA basically **pods ko event-driven ya metric-driven scale karta hai**, jisse aapke workloads efficient aur cost-effective chal sakein.


----
----
----

## Production me KEDA use karne se pehle dhyan dene wali baatein

### 1. **Cluster Stability aur Capacity Planning**

* **Node autoscaling setup hona chahiye** (Cluster Autoscaler ya Karpenter)
  KEDA sirf pods ko scale karta hai, nodes ko nahi. Agar pods zyada ho jaayein aur nodes available nahi hain, toh pods scheduling fail ho sakti hai.

* **Sufficient resources ensure karein**
  Cluster me enough CPU/memory capacity hona chahiye taaki scaling ke baad pods schedule ho saken.

---

### 2. **Metrics Server aur External Metrics Setup**

* **Metrics Server ka proper setup hona chahiye**
  KEDA CPU/memory scaling ke liye Kubernetes Metrics Server pe depend karta hai.

* **External metrics ka reliable source** (jaise Prometheus, Azure Monitor, AWS CloudWatch) hona chahiye
  Agar aap external event sources se scale kar rahe hain, toh unka monitoring system robust hona chahiye.

---

### 3. **Security & IAM Permissions**

* **Least privilege IAM roles setup karein** (especially AWS environment me)
  Agar aap AWS services (SQS, DynamoDB, CloudWatch, etc.) ko scaler ke liye use kar rahe hain, toh KEDA ko required IAM permissions dena zaroori hai via IRSA (IAM Roles for Service Accounts).

* **RBAC rules properly configure karein**
  KEDA operator ke paas required permissions hone chahiye lekin extra privileges avoid karein.

---

### 4. **ScaledObject & Trigger Configuration**

* **Trigger thresholds carefully tune karein**
  Agar threshold bohot low ya high hoga, toh scaling ya to unnecessary ho sakta hai ya workload delay ho sakta hai.

* **MinReplicaCount aur MaxReplicaCount set karein**
  Yeh boundaries aapke application ke load aur SLA ke hisaab se define honi chahiye.

* **Cooldown period samjhein**
  KEDA scaling decisions ko kuch delay ke saath apply karta hai taaki rapid fluctuation se bacha ja sake.

---

### 5. **Monitoring and Alerting**

* **KEDA ke metrics ko monitor karein**
  Jaise scaling events, pod counts, errors, etc. (Prometheus aur Grafana se).
  Aapko alert set karne chahiye agar scaling fail ho ya pods crash kar rahe ho.

* **Application health check aur readiness probes**
  Autoscaling ke sath app ki health important hoti hai. Make sure readiness/liveness probes properly configured hain.

---

### 6. **Testing & Validation**

* **Load testing karke scaling behavior validate karein**
  Realistic load scenarios me KEDA ka response test karein.

* **Disaster recovery plan banayein**
  Agar autoscaling galat ho jaye toh fallback ya manual intervention ke liye plan ready rahe.

---

### 7. **Logging and Troubleshooting**

* **KEDA operator logs regularly check karein**
  KEDA ke pod logs me errors ya warnings ko dekhein.

* **Event and audit logging enable karein**
  Taaki pata chale ki kab aur kyun scaling hua.

---

### 8. **Versioning and Updates**

* **KEDA ka stable production version use karein**
  Latest stable release lekin thoroughly test kiya hua.

* **Upgrade process plan karein**
  Downtime avoid karne ke liye rolling upgrade strategies implement karein.

---

## Summary checklist before production:

| Checkpoint                                        | Importance |
| ------------------------------------------------- | ---------- |
| Node autoscaling (Cluster Autoscaler / Karpenter) | High       |
| Metrics Server & external metrics                 | High       |
| IAM roles (least privilege)                       | High       |
| Trigger tuning and scaling limits                 | High       |
| Monitoring & alerting setup                       | High       |
| Health probes on applications                     | Medium     |
| Load testing & validation                         | High       |
| Logging & troubleshooting ready                   | Medium     |
| Use stable KEDA version                           | High       |

---
---
---


## **IAM Role for KEDA (for AWS Scalers)**

If you want KEDA to scale based on AWS services (e.g., SQS, DynamoDB), create an IAM role and link it via IRSA.

### Example IAM policy for SQS access:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility"
      ],
      "Resource": "arn:aws:sqs:<region>:<account-id>:<queue-name>"
    }
  ]
}
```

### Create IAM Role and ServiceAccount for KEDA Operator

* Follow AWS IRSA setup to associate this role with KEDA’s service account in `keda` namespace.
