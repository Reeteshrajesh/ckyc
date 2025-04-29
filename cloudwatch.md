# EKS CloudWatch Integration

This README provides step-by-step instructions to set up **Amazon CloudWatch** integration with your **EKS cluster** to collect **all logs and metrics**, using the following components:

- **CloudWatch Agent**: For collecting node and pod metrics.
- **Fluent Bit**: For shipping all container logs to CloudWatch Logs.
- **Container Insights**: For enhanced monitoring and dashboards in CloudWatch.

No filtering is applied — all logs and metrics are collected.

---

## Prerequisites

- AWS CLI configured
- `kubectl` and `helm` installed and configured for your EKS cluster
- EKS cluster up and running
- IAM role with required permissions
- [eks-charts Helm repo](https://github.com/aws/eks-charts)

---

## IAM Setup

Create an IAM policy and attach it to the worker node instance role or a Kubernetes service account.

### IAM Policy Example

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
        "logs:DescribeLogGroups",
        "logs:CreateLogGroup"
      ],
      "Resource": "*"
    }
  ]
}
```

Attach this policy to the appropriate IAM role (either node role or service account used by CloudWatch Agent and Fluent Bit).

---

## Step 1: Add Helm Repositories

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo add stable https://charts.helm.sh/stable
helm repo update
```

---

## Step 2: Install CloudWatch Agent (Logs + Metrics)

### Create `cloudwatch-agent-values.yaml`

```yaml
cloudWatch:
  agent:
    enabled: true
    config: |
      {
        "logs": {
          "logs_collected": {
            "files": {
              "collect_list": [
                {
                  "file_path": "/var/log/containers/*.log",
                  "log_group_name": "/aws/eks/container-logs",
                  "log_stream_name": "{instance_id}/{filename}",
                  "timestamp_format": "%Y-%m-%d %H:%M:%S",
                  "multi_line_start_pattern": "^\\d{4}-\\d{2}-\\d{2}"
                },
                {
                  "file_path": "/var/log/pods/*.log",
                  "log_group_name": "/aws/eks/pod-logs",
                  "log_stream_name": "{instance_id}/{pod_name}",
                  "timestamp_format": "%Y-%m-%d %H:%M:%S"
                }
              ]
            }
          }
        },
        "metrics": {
          "metrics_collected": {
            "cpu": {
              "measurement": ["usage_idle", "usage_user", "usage_system"],
              "metrics_collection_interval": 60
            },
            "mem": {
              "measurement": ["mem_used", "mem_free"],
              "metrics_collection_interval": 60
            },
            "disk": {
              "measurement": ["disk_used", "disk_free"],
              "metrics_collection_interval": 60
            },
            "net": {
              "measurement": ["bytes_sent", "bytes_recv"],
              "metrics_collection_interval": 60
            }
          }
        }
      }
```

### Install via Helm

```bash
helm install cloudwatch-agent eks/cloudwatch-agent -f cloudwatch-agent-values.yaml
```

---

## Step 3: Install Fluent Bit (for Logs)

```bash
helm install fluent-bit stable/fluent-bit \
  --set awsRegion=<your-region> \
  --set cloudWatch.logsGroupName=/aws/eks/all-logs \
  --set cloudWatch.logsStreamPrefix=k8s/
```

Replace `<your-region>` with your AWS region (e.g., `us-west-2`).

---

## Step 4: Enable Container Insights

Use the AWS CLI to enable Container Insights for your EKS cluster:

```bash
aws eks update-cluster-config \
  --region <your-region> \
  --name <cluster-name> \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator"],"enabled":true}]}'
```

Container Insights provides:
- Node and pod-level metrics
- CPU, memory, network, and disk usage
- Pre-built dashboards in the CloudWatch console

---

## Step 5: Verify Everything

- **CloudWatch Logs Console**:
  - Look under:
    - `/aws/eks/container-logs`
    - `/aws/eks/pod-logs`
    - `/aws/eks/all-logs`

- **CloudWatch Metrics Console**:
  - Browse `Container Insights` under **CloudWatch > Container Insights > Performance Monitoring**

---

## Optional: Uninstall Components

To remove the components:

```bash
helm uninstall cloudwatch-agent
helm uninstall fluent-bit
```

---

## References

- [Amazon CloudWatch Agent Docs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html)
- [EKS CloudWatch Logs](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html)
- [Container Insights Overview](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights.html)

---

## Author

DevOps Team  
Your Organization
