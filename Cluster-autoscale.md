# Cluster Autoscaler (CA) in EKS – Setup, Prerequisites, and Comparison with Karpenter

## Overview

Cluster Autoscaler (CA) is a Kubernetes component that automatically adjusts the number of nodes in your cluster based on the scheduling needs of pods. In EKS, CA interacts with AWS Auto Scaling Groups (ASGs) to scale the nodes up and down.

This document covers:

* Prerequisites for using CA in EKS
* Step-by-step setup of CA
* Common configurations
* Comparison with Karpenter
* Pros and cons of each approach

---

## Prerequisites

1. **EKS Cluster with Managed or Self-managed Node Groups**
2. **Auto Scaling Groups Tagged Properly**

   * `k8s.io/cluster-autoscaler/enabled = "true"`
   * `k8s.io/cluster-autoscaler/<cluster-name> = "owned"`
3. **IAM Role for Cluster Autoscaler (IRSA)**

   * Permissions:

     ```json
     {
       "Version": "2012-10-17",
       "Statement": [
         {
           "Effect": "Allow",
           "Action": [
             "autoscaling:DescribeAutoScalingGroups",
             "autoscaling:DescribeAutoScalingInstances",
             "autoscaling:SetDesiredCapacity",
             "autoscaling:TerminateInstanceInAutoScalingGroup",
             "ec2:DescribeLaunchTemplateVersions",
             "ec2:DescribeInstanceTypes"
           ],
           "Resource": "*"
         }
       ]
     }
     ```

---

## Cluster Autoscaler Setup

### 1. **Add Required Tags to Node Groups**

```bash
aws autoscaling create-or-update-tags \
  --tags ResourceId=<asg-name>,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true

aws autoscaling create-or-update-tags \
  --tags ResourceId=<asg-name>,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/<cluster-name>,Value=owned,PropagateAtLaunch=true
```

### 2. **Create IAM Policy and Role for CA**

* Attach the IAM policy shown above to a role.
* Annotate the Kubernetes service account with the IAM role:

```bash
eksctl create iamserviceaccount \
  --name cluster-autoscaler \
  --namespace kube-system \
  --cluster <cluster-name> \
  --attach-policy-arn arn:aws:iam::<account-id>:policy/ClusterAutoscalerPolicy \
  --approve \
  --override-existing-serviceaccounts
```

### 3. **Install Cluster Autoscaler (Helm)**

```bash
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=<cluster-name> \
  --set awsRegion=<region> \
  --set rbac.serviceAccount.create=false \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --set cloudProvider=aws \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.skip-nodes-with-system-pods=false \
  --set extraArgs.expander=least-waste
```

---

## Cluster Autoscaler Flags

| Flag                                  | Description                            |
| ------------------------------------- | -------------------------------------- |
| `--balance-similar-node-groups`       | Spread pods across ASGs                |
| `--expander=least-waste`              | Select ASG with least resource waste   |
| `--scale-down-delay-after-add=10m`    | Wait before scaling down               |
| `--skip-nodes-with-system-pods=false` | Allows draining nodes with system pods |

---

## Cluster Autoscaler vs Karpenter

| Feature                              | Cluster Autoscaler           | Karpenter                             |
| ------------------------------------ | ---------------------------- | ------------------------------------- |
| **Node Provisioning**                | Based on ASG                 | Direct EC2 provisioning               |
| **Granular Control**                 | ASG level (min/max/desired)  | Pod-level resource fitting            |
| **Scaling Speed**                    | Slower (1-2 minutes)         | Faster (provision node directly)      |
| **Spot Support**                     | Manual ASG setup             | Native support, fallback to on-demand |
| **Instance Type Flexibility**        | Limited to ASG configuration | Automatic best-fit selection          |
| **Custom Metrics (e.g. Kafka, SQS)** | ❌ Not supported              | ✅ With KEDA                           |
| **Multi-AZ balancing**               | Manual via ASG config        | Built-in balancing                    |

---

## Pros & Cons

### ✅ Cluster Autoscaler

* Simple to set up with existing ASGs
* Reliable and battle-tested
* Best when node types are fixed and known

### ❌ Cluster Autoscaler

* Slower reaction time
* Doesn’t support custom pod metrics
* Needs manual ASG tuning

### ✅ Karpenter (with optional KEDA)

* Rapid node provisioning
* Intelligent instance type selection
* Native support for spot/on-demand balance
* Works well with event-driven systems (via KEDA)

### ❌ Karpenter

* More moving parts (IAM, CRDs, Provisioners)
* Needs careful config (zones, limits)
* Scaling time can be affected by EC2 capacity issues

---

## Final Recommendation

| Use Case                                               | Recommended Tool   |
| ------------------------------------------------------ | ------------------ |
| Predictable workloads, known instance types            | Cluster Autoscaler |
| Dynamic workloads, event-driven (Kafka, SQS, CronJobs) | Karpenter + KEDA   |
| Need fine-grained scaling with mixed instances         | Karpenter          |

If you're moving towards microservice scalability, dynamic provisioning, and cost optimization with spot/on-demand strategies, **Karpenter + KEDA** is the future-proof stack.


----
----
----
----



# Cluster Autoscaler Terraform Setup

### `main.tf`

```hcl
provider "aws" {
  region = var.region
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = var.cluster_name
  cluster_version = "1.29"
  subnets         = var.subnets
  vpc_id          = var.vpc_id

  manage_aws_auth_configmap = true

  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 5
      desired_size = 2

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      tags = {
        "k8s.io/cluster-autoscaler/enabled"           = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      }
    }
  }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "ClusterAutoscalerPolicy"
  description = "EKS Cluster Autoscaler Policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstanceTypes"
        ]
        Resource = "*"
      }
    ]
  })
}

module "cluster_autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.34.0"

  role_name                         = "cluster-autoscaler-irsa"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [var.cluster_name]

  oidc_providers = {
    eks = {
      provider_arn               = data.aws_eks_cluster.cluster.identity[0].oidc.issuer
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"

  values = [
    yamlencode({
      autoDiscovery = {
        clusterName = var.cluster_name
      }
      awsRegion = var.region
      rbac = {
        serviceAccount = {
          create = false
          name   = "cluster-autoscaler"
        }
      }
      cloudProvider = "aws"
      extraArgs = {
        balance-similar-node-groups = "true"
        skip-nodes-with-system-pods = "false"
        expander                     = "least-waste"
      }
    })
  ]
}
```

---

## Cluster Autoscaler Flags

| Flag                                  | Description                            |
| ------------------------------------- | -------------------------------------- |
| `--balance-similar-node-groups`       | Spread pods across ASGs                |
| `--expander=least-waste`              | Select ASG with least resource waste   |
| `--scale-down-delay-after-add=10m`    | Wait before scaling down               |
| `--skip-nodes-with-system-pods=false` | Allows draining nodes with system pods |



Let us know if you'd like a Karpenter Terraform setup next.
