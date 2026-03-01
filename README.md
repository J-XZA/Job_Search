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

### Windows 11 notes

These scripts are Bash scripts. On Windows 11, run them from one of:

- **WSL2** (recommended), or
- **Git Bash**.

Do **not** run them directly in `cmd.exe`.

If you run from Git Bash and SSH later complains about private key permissions, run this from **PowerShell** in the repo directory:

```powershell
icacls ".\openclaw-<timestamp>-key.pem" /inheritance:r /grant:r "$env:USERNAME:R"
```

Then retry SSH.

---

## Pre-setup checklist (very specific)

Use this checklist **before** running `./scripts/create_openclaw_aws.sh`.

### 0) Decide exactly what you are building

You are preparing one EC2 VM that will:

- Run Docker + OpenClaw.
- Call Anthropic APIs using your API key.
- Be reachable over SSH from your machine.

That means you must prepare **three resource categories** ahead of time:

1. **AWS account access** (identity + permissions + region).
2. **Network source IP/CIDR** for SSH allow-listing.
3. **Anthropic API key** for model access.

---

### 1) Install required tools

#### macOS (Homebrew)

```bash
brew install awscli
```

#### Ubuntu / Debian

```bash
sudo apt-get update
sudo apt-get install -y awscli
```

#### Verify tools

```bash
aws --version
bash --version
```

What these commands mean:

- `aws --version`: confirms AWS CLI is installed and callable in your shell.
- `bash --version`: confirms you are running Bash (scripts are Bash-based).

---

### 2) Prepare AWS identity and credentials

You can use access keys, SSO, or an assumed role. The scripts only need that `aws` CLI commands succeed.

#### Option A: `aws configure` (access key based)

```bash
aws configure
```

You will be prompted for:

- `AWS Access Key ID`
- `AWS Secret Access Key`
- `Default region name` (example: `us-east-1`)
- `Default output format` (you can set `json`)

#### Option B: SSO profile

```bash
aws configure sso
aws sso login --profile <your-sso-profile>
export AWS_PROFILE=<your-sso-profile>
```

#### Verify identity (required)

```bash
aws sts get-caller-identity
```

What it means:

- This API call proves your credentials are valid and shows which account/user/role the script will use.
- If this fails, setup script will fail too.

---

### 3) Choose and verify AWS region

Pick one region first (for example `us-east-1`) and use it consistently.

#### Option A: pass region in script

```bash
./scripts/create_openclaw_aws.sh --region us-east-1 --anthropic-api-key "$ANTHROPIC_API_KEY"
```

#### Option B: set environment default

```bash
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
```

#### Quick region check

```bash
aws ec2 describe-availability-zones --region us-east-1 --query 'AvailabilityZones[].ZoneName' --output text
```

What it means:

- If this command returns zones, your region is reachable and your credentials can query EC2 there.

---

### 4) Confirm IAM permissions before you start

Minimum permissions needed by these scripts:

- `ec2:RunInstances`, `ec2:TerminateInstances`, `ec2:Describe*`
- `ec2:CreateSecurityGroup`, `ec2:AuthorizeSecurityGroupIngress`, `ec2:DeleteSecurityGroup`
- `ec2:CreateKeyPair`, `ec2:DeleteKeyPair`
- `ssm:GetParameter` for AWS public AMI parameter paths (Amazon Linux latest)

#### Fast preflight test

```bash
aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --region us-east-1
```

What it means:

- This confirms the script can fetch a valid Amazon Linux 2023 AMI ID through SSM.

If you get AccessDenied, ask your AWS admin for the IAM permissions above before running setup.

---

### 5) Prepare your public IP/CIDR for `--ssh-cidr`

The script opens SSH (port 22) only for the CIDR you provide. This is a security-critical setting.

#### Get your current public IP

```bash
curl -s https://checkip.amazonaws.com
```

If output is `198.51.100.25`, then use:

```text
198.51.100.25/32
```

Why `/32`?

- `/32` means exactly one IP address (yours), which is the safest standard option.

If your IP changes often (home ISP), you may need to update SG rules later or re-run with your new IP.

---

### 6) Get and secure your Anthropic API key

You need one valid key with model access for your selected models.

#### How to get it

1. Sign in to Anthropic Console.
2. Go to API key management.
3. Create a new key for this project.
4. Copy the key once and store it in a secure secret manager/password manager.

#### Export key in your current shell session

```bash
export ANTHROPIC_API_KEY='your-real-key-value'
```

#### Verify it is set (without printing secret)

```bash
test -n "$ANTHROPIC_API_KEY" && echo "ANTHROPIC_API_KEY is set" || echo "ANTHROPIC_API_KEY is missing"
```

Security notes:

- Do not commit keys into git.
- Avoid putting the raw key into shared shell history, chat logs, or screenshots.
- Prefer short-lived or project-scoped keys when possible.

---

### 7) Decide cost mode and instance shape

Default script choice is a balanced starting point:

- Instance type: `t3a.large` (2 vCPU, 8 GiB RAM)
- Purchase model: on-demand

Optional:

- Add `--spot` to reduce cost if interruptions are acceptable.
- Increase to `t3a.xlarge` if workload concurrency grows.

---

### 8) Final preflight commands (copy/paste)

Run these right before provisioning:

```bash
aws sts get-caller-identity
aws ec2 describe-availability-zones --region us-east-1 --query 'AvailabilityZones[].ZoneName' --output text
aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --region us-east-1 --query 'Parameter.Value' --output text
test -n "$ANTHROPIC_API_KEY" && echo "ANTHROPIC_API_KEY is set" || echo "ANTHROPIC_API_KEY is missing"
curl -s https://checkip.amazonaws.com
```

If all succeed, you are ready.

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
