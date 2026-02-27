# Job_Search

## OpenClaw on AWS (Claude 3.5 base + Claude Opus 4.6 task model)

This repo includes scripts to provision an EC2-hosted OpenClaw instance configured to:

- Use **Claude 3.5 Sonnet** (or higher) as the planning/base model.
- Use **Claude Opus 4.6** as the execution model for real tasks.

> Note: Anthropic model IDs can change over time. The script defaults to `claude-3-5-sonnet-latest` and `claude-opus-4-6`, and both are overridable via flags.

---

## Where should I run the scripts?

Run both scripts from **your local machine or a CI runner** that has:

- AWS CLI access to your target account.
- Network access to AWS APIs.
- Permission to write files in the current directory (the setup script writes a `.pem` file).

Recommended:

1. Clone this repository locally.
2. `cd` into the repo root.
3. Run scripts as `./scripts/...`.

Example:

```bash
git clone <your-repo-url>
cd Job_Search
./scripts/create_openclaw_aws.sh --help
```

---

## What should I do before running setup?

Use this preflight checklist **before** `create_openclaw_aws.sh`:

1. **Install dependencies**
   - `aws` CLI
   - `bash` (v4+ recommended)

2. **Authenticate AWS CLI**
   - Run `aws configure` (or use SSO/profile-based auth).
   - Confirm identity:
     ```bash
     aws sts get-caller-identity
     ```

3. **Set region/profile intentionally**
   - Either pass `--region` to the script, or set `AWS_REGION`/`AWS_DEFAULT_REGION`.
   - If using a non-default profile:
     ```bash
     export AWS_PROFILE=<profile-name>
     ```

4. **Confirm required IAM permissions**
   - EC2: create/run/describe/terminate instances, security groups, key pairs.
   - VPC/Subnet describe permissions.
   - SSM parameter read (`/aws/service/ami-amazon-linux-latest/...`).

5. **Prepare your Anthropic key securely**
   - Export key in your shell:
     ```bash
     export ANTHROPIC_API_KEY=<your-key>
     ```
   - Avoid pasting secrets into shell history when possible.

6. **Pick secure network settings**
   - Set `--ssh-cidr` to your IP/CIDR (do not leave broad open SSH in production).
   - Decide if app port should be public or later restricted via SG/ALB/WAF.

7. **Decide cost mode**
   - Default on-demand `t3a.large` for balanced cost/effectiveness.
   - Add `--spot` if interruption is acceptable.

---

## Why this instance choice is a cost/effectiveness middle ground

Default instance type in the script is **`t3a.large`**:

- **2 vCPU / 8 GiB RAM** is usually enough for API-driven OpenClaw where heavy inference runs in Anthropic API.
- **No GPU** required, avoiding major cost increase.
- **`t3a`** is often cheaper than `t3` with similar practical performance for this workload.
- Handles moderate orchestration concurrency.

If your workload grows:

- Move to `t3a.xlarge` first (simple vertical scaling).
- Use `--spot` for cost-sensitive non-critical environments.

---

## Provision OpenClaw

```bash
./scripts/create_openclaw_aws.sh \
  --anthropic-api-key "$ANTHROPIC_API_KEY" \
  --region us-east-1
```

### Common options

```bash
./scripts/create_openclaw_aws.sh \
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
./scripts/destroy_openclaw_aws.sh \
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
