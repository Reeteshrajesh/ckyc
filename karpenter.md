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



## ✅ Step-by-Step Production Setup Using AWS CLI

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

