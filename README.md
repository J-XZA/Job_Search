# Job_Search

## OpenClaw on AWS (Claude 3.5 base + Claude Opus 4.6 task model)

This repo now includes scripts to provision an EC2-hosted OpenClaw instance configured to:

- Use **Claude 3.5 Sonnet** (or higher) as the planning/base model.
- Use **Claude Opus 4.6** as the execution model for real tasks.

> Note: Anthropic model IDs can change over time. The script defaults to `claude-3-5-sonnet-latest` and `claude-opus-4-6`, and both are overridable via flags.

---

## Why this instance choice is the best cost/effectiveness middle ground

Default instance type in the script is **`t3a.large`**:

- **2 vCPU / 8 GiB RAM** is usually enough for an API-driven OpenClaw service where heavy model inference is handled by Anthropic API.
- **No GPU** required, which avoids major cost increase.
- **`t3a`** is typically cheaper than `t3` while keeping comparable performance.
- Supports moderate concurrency for orchestration workflows.

If your workload grows:

- Move to `t3a.xlarge` first (simple vertical scaling).
- Use `--spot` for cost-sensitive non-critical environments.

---

## Prerequisites

- AWS CLI configured with credentials and default account access.
- Permissions for EC2, VPC, SSM parameter read, and key pair/security group management.
- An Anthropic API key.

---

## Provision OpenClaw

```bash
scripts/create_openclaw_aws.sh \
  --anthropic-api-key "$ANTHROPIC_API_KEY" \
  --region us-east-1
```

### Common options

```bash
scripts/create_openclaw_aws.sh \
  --anthropic-api-key "$ANTHROPIC_API_KEY" \
  --region us-east-1 \
  --instance-type t3a.large \
  --base-model claude-3-5-sonnet-latest \
  --task-model claude-opus-4-6 \
  --ssh-cidr 203.0.113.10/32 \
  --spot
```

The script will:

1. Discover your default VPC/subnet.
2. Create a security group (SSH + OpenClaw app port).
3. Create an EC2 key pair and save `<name>.pem` locally.
4. Launch an Amazon Linux 2023 EC2 instance.
5. Install Docker and run OpenClaw via Docker Compose.

Output includes the instance ID, public IP/DNS, key file, and OpenClaw URL.

---

## Cleanup

```bash
scripts/destroy_openclaw_aws.sh \
  --instance-id i-xxxxxxxxxxxxxxxxx \
  --region us-east-1 \
  --security-group-id sg-xxxxxxxxxxxxxxxxx \
  --key-name openclaw-YYYYMMDDHHMMSS-key \
  --key-file openclaw-YYYYMMDDHHMMSS-key.pem
```

---

## Security notes

- Restrict SSH ingress with `--ssh-cidr` (avoid `0.0.0.0/0` in production).
- Rotate API keys if exposed.
- Consider placing OpenClaw behind an ALB + TLS if internet-facing.
