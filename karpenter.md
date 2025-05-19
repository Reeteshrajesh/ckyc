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
