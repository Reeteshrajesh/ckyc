https://github.com/isItObservable/karpenter/tree/master

""helm template karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "controller.interruptionQueue.enabled=false" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterControllerRole-${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  > karpenter.yaml
""

""
spec:
  role: KarpenterNodeRole-prod-eks-loquide # replace with your cluster name
  amiFamily: AL2023
  amiSelectorTerms:
    - id: "ami-0a2eccdf5bc77c675"
""


""
# Tag each private subnet
aws ec2 create-tags --resources <subnet-id> \
  --tags Key=karpenter.sh/discovery,Value=prod-eks-loquide

# Tag your node security group
aws ec2 create-tags --resources <security-group-id> \
  --tags Key=karpenter.sh/discovery,Value=prod-eks-loquide

""

""
apRoles: |
    - groups:
      - system:bootstrappers
      - system:nodes
      rolearn: arn:aws:iam::448775934010:role/eksctl-prod-eks-loquide-nodegroup--NodeInstanceRole-UjlivvmxLLKl
      username: system:node:{{EC2PrivateDNSName}}
    - groups:
      - system:bootstrappers
      - system:nodes
      # Uncomment below if running Windows workloads
      # - eks:kube-proxy-windows
      rolearn: arn:aws:iam::448775934010:role/KarpenterNodeRole-prod-eks-loquide
      username: system:node:{{EC2PrivateDNSName}}
""



""Use taints + tolerations and node affinity in your pod specs to control which workloads land on Spot vs. On-Demand nodes.

Example:

tolerations:
  - key: "karpenter.sh/capacity-type"
    operator: "Equal"
    value: "spot"
    effect: "NoSchedule"

This lets you safely schedule non-critical workloads on Spot without affecting critical services.""


--------
#######
-------



## ✅ Step-by-Step Production Setup Using AWS CLI(when we use sqs )

---

### **1. Create SQS Queue**

```bash
aws sqs create-queue --queue-name karpenter-interruption-queue
```

---

### **2. Get Queue ARN and URL**

```bash
QUEUE_NAME="karpenter-interruption-queue"
QUEUE_URL=$(aws sqs get-queue-url --queue-name $QUEUE_NAME --query "QueueUrl" --output text)
QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-name QueueArn --query "Attributes.QueueArn" --output text)
```

---

### **3. Attach SQS Policy to Allow EventBridge to Send Messages**

```bash
cat <<EOF > sqs-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEventBridgeSend",
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "sqs:SendMessage",
      "Resource": "$QUEUE_ARN"
    }
  ]
}
EOF

aws sqs set-queue-attributes \
  --queue-url $QUEUE_URL \
  --attributes Policy="$(<sqs-policy.json)"
```

---

### **4. Create EventBridge Rule for Spot Interruption**

```bash
aws events put-rule \
  --name karpenter-spot-interruption-rule \
  --event-pattern '{
    "source": ["aws.ec2"],
    "detail-type": ["EC2 Spot Instance Interruption Warning"]
  }'
```

---

### **5. Add Target to Forward Events to SQS**

```bash
aws events put-targets \
  --rule karpenter-spot-interruption-rule \
  --targets "Id"="1","Arn"="$QUEUE_ARN"
```

---

### **6. Grant KarpenterControllerRole IAM Permission to Read from SQS**

Make sure your `KarpenterControllerRole` has the following inline policy (attach via console or CLI):

```json
{
  "Effect": "Allow",
  "Action": [
    "sqs:ReceiveMessage",
    "sqs:DeleteMessage",
    "sqs:GetQueueAttributes",
    "sqs:GetQueueUrl"
  ],
  "Resource": "<QUEUE_ARN>"
}
```

---

### **7. Update Helm Installation of Karpenter**

Use the **same SQS queue name** you created (`karpenter-interruption-queue`):

```bash
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --namespace karpenter \
  --version "${KARPENTER_VERSION}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=karpenter-interruption-queue" \
  --set "controller.interruptionQueue.enabled=true" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterControllerRole-${CLUSTER_NAME}" \
  --set "controller.resources.requests.cpu=1" \
  --set "controller.resources.requests.memory=1Gi" \
  --set "controller.resources.limits.cpu=1" \
  --set "controller.resources.limits.memory=1Gi"
```

---

### ✅ Verification

You should see logs like:

```
Listening for interruption messages on SQS queue: karpenter-interruption-queue
```

You can test by manually terminating a spot EC2 instance and checking if Karpenter gracefully handles it.





# Spot vs On-Demand Node Management in Karpenter (Best Practices)

## Overview

Karpenter is a powerful autoscaler for Kubernetes that dynamically launches the right compute resources based on your application needs. It supports both **On-Demand** and **Spot** EC2 instances. This document explains the differences, best practices, and how to configure Karpenter for both instance types effectively.

---

## 1. Spot vs On-Demand Instances

### On-Demand Instances

* **Stable and reliable pricing**
* **Never interrupted by AWS**
* Ideal for **critical workloads** (e.g., system services, databases, monitoring stack)

### Spot Instances

* **Up to 90% cheaper** than On-Demand
* Can be **interrupted** with a 2-minute warning
* Best suited for **fault-tolerant, stateless, and scalable** workloads (e.g., batch jobs, frontend services, CI/CD runners)

---


## Workload Suitability Matrix

| Workload                    | Use Spot      | Use On-Demand |
| --------------------------- | ------------- | ------------- |
| CI/CD Runners               | ✅             | ❌             |
| Ingress Controllers         | ✅             | ✅ (HA setup)  |
| Prometheus / Grafana / Loki | ✅ (carefully) | ✅             |
| Web APIs / Microservices    | ✅             | ✅             |
| Databases (Postgres, etc.)  | ❌             | ✅             |
| Kafka, Redis, RabbitMQ      | ❌             | ✅             |

---

## Additional Recommendations

* Use `PodDisruptionBudgets` to ensure graceful drain and failover.
* Enable metrics and monitoring to track instance interruptions.
* Set realistic `.limits.cpu` in NodePool to prevent budget overruns.
* Use `consolidateAfter` and `disruption` policies to automate cost savings.
* Avoid Spot for workloads with persistent local storage.

---

## Conclusion

Combining Spot and On-Demand instances with Karpenter offers both cost-efficiency and reliability. Use labels, taints, and NodePools strategically to place the right workloads on the right capacity. Continuously monitor and adjust configurations as your application and infrastructure evolve.



```
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2 # Amazon Linux 2
  role: "KarpenterNodeRole-CLUSTER_NAME_TO_REPLACE" # replace with your cluster name
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "CLUSTER_NAME_TO_REPLACE" # replace with your cluster name
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "CLUSTER_NAME_TO_REPLACE" # replace with your cluster name
  amiSelectorTerms:
    - id: "ARM_AMI_ID_TO_REPLACE"
    - id: "AMD_AMI_ID_TO_REPLACE"
  tags:
    owner: OWNER_TO_REPLACE
    owner-email: OWNER_EMAIL_TO_REPLACE
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
      metadata:
        # Labels are arbitrary key-values that are applied to all nodes
        labels:
          type: operation
      spec:
        requirements:
          - key: kubernetes.io/arch
            operator: In
            values: ["amd64"]
          - key: kubernetes.io/os
            operator: In
            values: ["linux"]
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["on-demand"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: [ "m5","m5d","c5","c5d","c4","r4" ]
            minValues: 1
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: [  "16", "32" ]
          - key: user.defined.label/type
            operator: Exists
        nodeClassRef:
          group: karpenter.k8s.aws
          kind: EC2NodeClass
          name: default
        expireAfter: 72h # 30 * 24h = 720h
  limits:
    cpu: 1000


  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
    budgets:
      - nodes: "20%"
        reasons:
          - "Empty"
          - "Drifted"
          - "Underutilized"
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: application
spec:
  template:
      metadata:
        # Labels are arbitrary key-values that are applied to all nodes
        labels:
          type: app
      spec:
        requirements:
          - key: kubernetes.io/arch
            operator: In
            values: ["amd64"]
          - key: kubernetes.io/os
            operator: In
            values: ["linux"]
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["spot"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: [ "8","16", "32" ]
          - key: user.defined.label/type
            operator: Exists
        nodeClassRef:
          group: karpenter.k8s.aws
          kind: EC2NodeClass
          name: default
        expireAfter: 72h # 30 * 24h = 720h
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
    budgets:
      - nodes: "20%"
        reasons:
          - "Empty"
          - "Drifted"
          - "Underutilized"
      - nodes: "0"
        schedule: "@daily"
        duration: 10m
        reasons:
          - "Underutilized"
---

```

**Set Limits per NodePool**

Use `.spec.limits.cpu` to restrict how much CPU each NodePool can scale up to:

```yaml
limits:
  cpu: 1000
```

This prevents over-scaling and keeps cost predictable.

### **Disruption Budgets**

Ensure graceful consolidation without affecting workloads:

```yaml
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 1m
  budgets:
    - nodes: "20%"
      reasons:
        - "Empty"
        - "Drifted"
        - "Underutilized"
```

This prevents aggressive downsizing and ensures some headroom.

### **AMI Diversity**

Specify multiple AMI IDs for `amd64` and `arm64`:

```yaml
amiSelectorTerms:
  - id: "ami-xxxxxx" # ARM
  - id: "ami-yyyyyy" # AMD
```






---

### 🚀 1. **Karpenter with SQS (Recommended for Production)**

Karpenter **watches an SQS queue** to respond **faster and more reliably** to AWS interruption events like:

| Interruption Type             | Source                         |
| ----------------------------- | ------------------------------ |
| EC2 Spot instance termination | EC2/Spot via EventBridge → SQS |
| EC2 rebalance recommendations | EC2 via EventBridge → SQS      |
| Scheduled maintenance events  | EC2 via EventBridge → SQS      |

#### ✅ Benefits:

* **Proactive node management**: Karpenter can *gracefully drain* nodes before they're interrupted.
* **High availability**: It can spin up new nodes **before** losing old ones.
* **Better with Spot instances**: This setup is *critical* when using **Spot capacity** to save cost.

#### 🛠️ Setup Requires:

* An **SQS queue**.
* An **EventBridge rule** forwarding relevant EC2 events to the queue.
* Proper **IAM permissions** (Karpenter controller can read from SQS).

---

### 🧪 2. **Karpenter without SQS**

You can run Karpenter **without SQS**, and it will **still provision and deprovision nodes** based on:

* Pod scheduling needs.
* Node expiry (`ttlSecondsAfterEmpty`, etc.).
* Consolidation and right-sizing.

#### 🚫 Missing Capabilities:

* ❌ **No proactive Spot interruption handling**.
* ❌ **Cannot gracefully drain nodes during AWS-initiated events** (e.g., terminations).
* ❌ **Slower reaction to interruptions** — Karpenter will only react **after** the node is gone or unavailable.

#### ✅ Still Works For:

* **On-demand instances**.
* Simple auto-scaling based on pending pods.
* Cost optimization (consolidation).

---

### 🔍 Summary Comparison

| Feature                         | With SQS                      | Without SQS                     |
| ------------------------------- | ----------------------------- | ------------------------------- |
| Spot interruption handling      | ✅ Yes (fast, graceful)        | ❌ No (reactive only)            |
| Node lifecycle control          | ✅ Full (drain, replace early) | ⚠️ Partial                      |
| Works with EventBridge          | ✅ Yes                         | ❌ No                            |
| Required for full Karpenter use | ✅ Yes (esp. Spot, prod-grade) | ❌ Optional for testing/dev only |
| Extra setup (SQS, IAM, rules)   | ✅ Needed                      | ✅ None                          |

---

### ✅ Recommendation

* Use **SQS** in **production** or if using **Spot instances**.
* Use **without SQS** only for:

  * Dev/test environments
  * On-demand nodes only
  * Simpler scenarios where cost savings or fault tolerance aren't critical.

---
-----
    _-------
-------
------
------
------
-----

# Spot vs On-Demand Node Management in Karpenter (Best Practices)

## 📘 Overview

Karpenter is a powerful autoscaler for Kubernetes that dynamically launches the right compute resources based on your application needs. It supports both **On-Demand** and **Spot** EC2 instances. This document provides a comprehensive guide to understand their differences, use cases, setup in Karpenter, and best practices for workload placement and cost optimization.

---

## ☁️ 1. Spot vs On-Demand EC2 Instances

### On-Demand Instances

* **Stable and predictable** pricing
* **Guaranteed availability** (not subject to interruptions)
* Best for **critical or stateful** workloads (e.g., databases, monitoring stack)

### Spot Instances

* **Significantly cheaper** (up to 90% savings)
* **Can be interrupted** with a 2-minute warning
* Ideal for **stateless, fault-tolerant, scalable** workloads (e.g., batch jobs, CI/CD, microservices)

---

## ⚙️ 2. Karpenter Capacity Type Configuration

To select instance types:

```yaml
- key: karpenter.sh/capacity-type
  operator: In
  values: ["spot"] # or ["on-demand"]
```

Use this requirement in your NodePool spec to control provisioning type.

---

## 🧩 3. Recommended Setup: Separate NodePools

### a) On-Demand NodePool (critical workloads)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: on-demand-operation
spec:
  template:
    metadata:
      labels:
        type: operation
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
  nodeClassRef:
    name: private-nodeclass
  limits:
    cpu: "1000" # 1000 millicores = 1 vCPU
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
    budgets:
      - nodes: "20%"
        reasons:
          - "Empty"
          - "Drifted"
          - "Underutilized"
```

### b) Spot NodePool (stateless workloads)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot-application
spec:
  template:
    metadata:
      labels:
        type: app
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
  nodeClassRef:
    name: private-nodeclass
  limits:
    cpu: "1000"
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
    budgets:
      - nodes: "20%"
        reasons:
          - "Empty"
          - "Drifted"
          - "Underutilized"
```

---

## 🎯 4. Workload Placement Strategies

### a) Taints & Tolerations

Ensure only critical workloads can run on On-Demand nodes:

```yaml
# On-Demand node taint
spec:
  taints:
    - key: type
      value: operation
      effect: NoSchedule
```

```yaml
# Workload toleration
spec:
  tolerations:
    - key: "type"
      operator: "Equal"
      value: "operation"
      effect: "NoSchedule"
```

### b) NodeSelector / Affinity

```yaml
# Workload scheduled to Spot node
spec:
  nodeSelector:
    type: app
```

---

## 🧬 5. AMI & Architecture Support

Support ARM and AMD64 for flexibility and fallback:

```yaml
amiSelectorTerms:
  - id: "ami-arm64-example"
  - id: "ami-amd64-example"
```

Use tags or parameters instead of hardcoded AMIs in production.

---

## 🧱 6. EC2NodeClass for Private Workloads

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: private-nodeclass
spec:
  amiFamily: AL2
  role: "KarpenterNodeRole-CLUSTER_NAME" # Ensure IRSA setup for this role
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "CLUSTER_NAME"
        karpenter.sh/subnet-type: private
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "CLUSTER_NAME"
        karpenter.sh/sg-type: private
  amiSelectorTerms:
    - id: "ami-arm64-example"
    - id: "ami-amd64-example"
  tags:
    owner: YOUR_NAME
    owner-email: YOUR_EMAIL@example.com
```

---

## 🌐 7. EC2NodeClass for Public Workloads

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: gateway-nodeclass
spec:
  amiFamily: AL2
  role: "KarpenterNodeRole-CLUSTER_NAME"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: CLUSTER_NAME
        karpenter.sh/subnet-type: public
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: CLUSTER_NAME
        karpenter.sh/sg-type: public
  amiSelectorTerms:
    - id: "ami-arm64-example"
    - id: "ami-amd64-example"
  tags:
    owner: YOUR_NAME
    owner-email: YOUR_EMAIL@example.com
```

---

## 🧮 8. Workload Suitability Matrix

| Workload                    | Spot ✅ | On-Demand ✅ |
| --------------------------- | ------ | ----------- |
| CI/CD Runners               | ✅      | ❌           |
| Ingress Controllers         | ✅      | ✅ (HA)      |
| Prometheus / Grafana / Loki | ✅\*    | ✅           |
| Web APIs / Microservices    | ✅      | ✅           |
| Databases (Postgres, etc.)  | ❌      | ✅           |
| Kafka, Redis, RabbitMQ      | ❌      | ✅           |

\*Carefully test stateful scenarios before using Spot.

---

## 🧠 9. Additional Best Practices

* Use `PodDisruptionBudgets` (PDBs) for HA setups
* Enable Karpenter metrics for interruption tracking
* Avoid Spot if pods use local hostPath/ephemeral storage
* Use `consolidateAfter` for cost-efficient rebalancing
* Combine NodePools with overlapping selectors for fallback

---

## 🏷️ 10. Tagging Requirements for Karpenter

Tag your AWS resources correctly:

| Resource       | Tag Key                  | Value         |
| -------------- | ------------------------ | ------------- |
| Public Subnet  | karpenter.sh/subnet-type | public        |
| Private Subnet | karpenter.sh/subnet-type | private       |
| Both Subnets   | karpenter.sh/discovery   | CLUSTER\_NAME |
| Public SG      | karpenter.sh/sg-type     | public        |
| Private SG     | karpenter.sh/sg-type     | private       |

---

## 📦 11. Helm-Based Workload Targeting

### Gateway Helm Chart:

```yaml
spec:
  template:
    metadata:
      labels:
        workload: gateway
  nodeSelector:
    workload: gateway
```

### Microservices Helm Chart:

```yaml
spec:
  template:
    metadata:
      labels:
        workload: private
  nodeSelector:
    workload: private
```

---



### ✅ What’s the difference between Karpenter NodePool and EC2NodeClass?

| Aspect           | `NodePool`                                                                        | `EC2NodeClass`                                                                               |
| ---------------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Purpose          | Defines the *how many*, *what type*, and *placement logic* of nodes to provision. | Defines the *infrastructure template* used to launch EC2 instances (AMI, subnet, SG, etc.).  |
| Scope            | Kubernetes scheduling and policy (e.g., labels, taints, limits).                  | AWS-specific configuration (e.g., AMI, subnets, IAM role).                                   |
| Think of it as   | "What nodes to run for what kind of workload."                                    | "How to build those nodes in AWS."                                                           |
| Key Fields       | `requirements`, `limits`, `template`, `disruption`, `consolidation`               | `amiFamily`, `amiSelectorTerms`, `subnetSelectorTerms`, `securityGroupSelectorTerms`, `role` |
| IRSA Needed?     | No (purely K8s-level config)                                                      | Yes (requires IAM role for EC2)                                                              |
| Subnet & SG Tags | Not needed                                                                        | Required for subnet and SG discovery                                                         |
| Example Use Case | One NodePool for Spot workloads, another for On-Demand                            | One EC2NodeClass for private workload (microservices), another for public (gateway)          |
| Reusability      | Can reference same EC2NodeClass from multiple NodePools                           | Can be shared across multiple NodePools                                                      |

---



## ✅ Conclusion

Combining **Spot** and **On-Demand** provisioning with Karpenter delivers an optimal blend of **cost savings** and **resilience**. Use **NodePools**, **NodeClasses**, taints/tolerations, and proper AWS tagging to ensure effective, automated, and safe workload scheduling.



__------
------
-----
----

# 🔒 Production-Grade Karpenter Setup: Advanced Best Practices

## 🔁 1. Multi-AZ and Multi-Subnet Architecture

### Why?

* High availability
* Resilience to AZ failure
* Better Spot availability and lower interruption rates

### How to Do It:

* Tag **private and public subnets** in *all* availability zones:

```hcl
# Example subnet tags
"karpenter.sh/discovery"     = "your-cluster-name"
"karpenter.sh/subnet-type"   = "private"  # or public
```

* Ensure your `EC2NodeClass` allows Karpenter to select from all these subnets:

```yaml
subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: "your-cluster-name"
      karpenter.sh/subnet-type: private
```

---

## ⚖️ 2. Diversify Instance Types

### Why?

* Broader range increases provisioning success and cost savings
* Resilient to Spot pool exhaustion

### Example Requirement Block:

```yaml
requirements:
  - key: node.kubernetes.io/instance-type
    operator: In
    values:
      - t3.large
      - t3a.large
      - m6a.large
      - m6i.large
      - t4g.large  # for ARM workloads
```

> Also consider filtering by CPU architecture using `karpenter.k8s.aws/architecture`.

---

## 🧠 3. Instance Interruption Handling

### 🔔 Spot Interruption Notices

Use AWS’s **Node Termination Handler** to catch interruptions and cordon/drain nodes gracefully:

```bash
helm repo add aws https://aws.github.io/eks-charts
helm upgrade --install aws-node-termination-handler aws/aws-node-termination-handler \
  --set nodeSelector."karpenter\.sh/provisioner-name"=spot-application \
  --set enableSpotInterruptionDraining=true \
  --namespace kube-system
```

### 📦 Configure PodDisruptionBudgets (PDB)

Prevent all pods from being evicted at once during consolidation:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-pdb
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: my-app
```

---

## ⛳ 4. Pod Placement, Labels, and Affinities

| Workload Type     | Node Label         | Tolerations Required? | Example Use Case             |
| ----------------- | ------------------ | --------------------- | ---------------------------- |
| System Components | `workload=system`  | Yes                   | CoreDNS, kube-proxy, metrics |
| Microservices     | `workload=app`     | No                    | APIs, workers, queues        |
| Gateway/Ingress   | `workload=gateway` | Optional              | NGINX, Istio ingress         |

### Example:

```yaml
spec:
  nodeSelector:
    workload: app
```

Optional: Use `topologySpreadConstraints` to spread pods across AZs.

---

## 🔄 5. Consolidation & Disruption Budget

Use conservative settings in production:

```yaml
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 5m
  budgets:
    - nodes: "20%"
      reasons: ["Empty", "Drifted", "Underutilized"]
```

* Set `consolidateAfter` to at least `5m` to avoid aggressive churn.
* Watch for node "thrashing" (create → drain → terminate loops) in logs.

---

## 📊 6. Monitoring and Metrics (Grafana Dashboard Recommended)

### Metrics to Track:

| Metric                           | Why It Matters                                |
| -------------------------------- | --------------------------------------------- |
| `karpenter_nodes_created`        | Tracks how often nodes are spun up            |
| `karpenter_nodes_terminated`     | Indicates consolidation/interruption behavior |
| `karpenter_allocatable_cpu`      | Helps detect CPU starvation                   |
| `karpenter_instance_type_prices` | Spot vs On-Demand costs                       |

Would you like me to provide a **ready-to-import Grafana dashboard JSON** for Karpenter metrics?

---

## 💰 7. Cost Optimization

### Use Spot by Default with Fallback:

If Spot is not available, Karpenter falls back to On-Demand **if you don't restrict it**:

```yaml
requirements:
  - key: karpenter.sh/capacity-type
    operator: In
    values: ["spot", "on-demand"]
```

Use budgets and limits to control costs:

```yaml
limits:
  cpu: 2000
```

---

## 🔐 8. IAM and Security

### Use IRSA and Least Privilege

Attach only necessary policies to your Karpenter Node IAM Role:

* `AmazonEKSWorkerNodePolicy`
* `AmazonEC2ContainerRegistryReadOnly`
* `AmazonSSMManagedInstanceCore`
* Custom policies for:

  * `ec2:Describe*`
  * `ec2:RunInstances`
  * `ec2:TerminateInstances`
  * `ec2:CreateTags`

Never over-provision permissions in the `EC2NodeClass`.

---

## 🧪 9. Staging Test Plan (Before Production Rollout)

1. Deploy Karpenter in staging cluster
2. Use **chaos testing**:

   * Simulate Spot interruptions (manually terminate instances)
   * Force node consolidation
3. Observe:

   * Pod rescheduling times
   * Data loss (should be none for stateless apps)
   * Any spikes in latency/downtime

---

## 🧹 10. Additional Pro Tips

* **Set `terminationGracePeriodSeconds`** in your Deployments to allow graceful exits.
* **Use ResourceQuota** and **LimitRanges** to:

  * Prevent resource hogs
  * Enforce CPU/memory limits on namespaces
* Regularly review **CloudWatch billing reports** for unexpected On-Demand usage spikes
* If you have burst workloads (e.g., morning traffic), pre-warm nodes using **Scheduled Scalers** like [KEDA](https://keda.sh)

------
-----
-----

### 🧠 **15 Key Karpenter Terms Explained**

| Term                            | Description                                                                                         |
| ------------------------------- | --------------------------------------------------------------------------------------------------- |
| **NodePool**                    | Defines how Karpenter should provision nodes (includes capacity type, limits, disruption policies). |
| **EC2NodeClass**                | AWS-specific configuration like AMIs, subnets, SGs, IAM role, used by a NodePool.                   |
| **capacity-type**               | Determines if nodes should be Spot or On-Demand (`karpenter.sh/capacity-type`).                     |
| **requirements**                | Rules under `NodePool` specifying hardware, capacity-type, zones, architectures, etc.               |
| **consolidationPolicy**         | Governs whether Karpenter tries to consolidate underused nodes.                                     |
| **disruption**                  | Policy set inside `NodePool` to control node replacement, consolidation, and rolling updates.       |
| **amiSelectorTerms**            | A list of AMI IDs Karpenter is allowed to use. Supports ARM and AMD flexibility.                    |
| **subnetSelectorTerms**         | Tag-based filters to tell Karpenter which subnets it can use.                                       |
| **securityGroupSelectorTerms**  | Tag filters that specify what SGs to attach to nodes created.                                       |
| **provisioner** *(deprecated)*  | Old API in Karpenter v0.x, now replaced by `NodePool` in v1.x.                                      |
| **Pod Disruption Budget (PDB)** | Kubernetes native object to ensure minimum running pods during disruptions.                         |
| **taints & tolerations**        | Used to restrict workloads to certain nodes, like On-Demand only for critical apps.                 |
| **nodeSelector**                | A label-based way to assign workloads to specific types of nodes (e.g., Spot vs On-Demand).         |
| **interruption-handling**       | Spot interruption management with AWS Node Termination Handler to gracefully drain.                 |
| **limits.cpu**                  | A cap on total CPU (or memory) that a NodePool is allowed to provision. Helps budget control.       |

---
