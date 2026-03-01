#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/create_openclaw_aws.sh --anthropic-api-key <key> [options]

Required:
  --anthropic-api-key <key>    Anthropic API key used by OpenClaw.

Optional:
  --region <region>            AWS region (default: us-east-1)
  --instance-type <type>       EC2 instance type (default: t3a.large)
  --name-prefix <name>         Prefix for created resources (default: openclaw)
  --ssh-cidr <cidr>            CIDR allowed to SSH (default: 0.0.0.0/0)
  --openclaw-port <port>       Port OpenClaw listens on (default: 3000)
  --volume-gb <size>           Root EBS size in GiB (default: 30)
  --base-model <model-id>      Planner/base model (default: claude-3-5-sonnet-latest)
  --task-model <model-id>      Execution/task model (default: claude-opus-4-6)
  --openclaw-image <image>     Container image (default: ghcr.io/openclaw/openclaw:latest)
  --spot                        Launch as a spot instance to reduce cost.
  --help                        Show this help text.

Examples:
  scripts/create_openclaw_aws.sh \
    --anthropic-api-key "$ANTHROPIC_API_KEY" \
    --region us-east-1

  scripts/create_openclaw_aws.sh \
    --anthropic-api-key "$ANTHROPIC_API_KEY" \
    --spot \
    --ssh-cidr 203.0.113.10/32
USAGE
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' is not installed." >&2
    exit 1
  fi
}

set_key_file_permissions() {
  local key_file="$1"

  if chmod 400 "$key_file" 2>/dev/null; then
    return 0
  fi

  case "${OSTYPE:-}" in
    msys*|cygwin*|win32*)
      echo "Warning: could not apply chmod 400 to $key_file in this Windows shell." >&2
      echo "If SSH rejects the key, run this in PowerShell:" >&2
      echo "  icacls \"$key_file\" /inheritance:r /grant:r \"$USERNAME:R\"" >&2
      ;;
    *)
      echo "Error: failed to secure key file permissions for $key_file." >&2
      exit 1
      ;;
  esac
}

REGION="us-east-1"
INSTANCE_TYPE="t3a.large"
NAME_PREFIX="openclaw"
SSH_CIDR="0.0.0.0/0"
OPENCLAW_PORT="3000"
VOLUME_GB="30"
BASE_MODEL="claude-3-5-sonnet-latest"
TASK_MODEL="claude-opus-4-6"
OPENCLAW_IMAGE="ghcr.io/openclaw/openclaw:latest"
ANTHROPIC_API_KEY=""
USE_SPOT="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --anthropic-api-key)
      ANTHROPIC_API_KEY="${2:-}"
      shift 2
      ;;
    --region)
      REGION="${2:-}"
      shift 2
      ;;
    --instance-type)
      INSTANCE_TYPE="${2:-}"
      shift 2
      ;;
    --name-prefix)
      NAME_PREFIX="${2:-}"
      shift 2
      ;;
    --ssh-cidr)
      SSH_CIDR="${2:-}"
      shift 2
      ;;
    --openclaw-port)
      OPENCLAW_PORT="${2:-}"
      shift 2
      ;;
    --volume-gb)
      VOLUME_GB="${2:-}"
      shift 2
      ;;
    --base-model)
      BASE_MODEL="${2:-}"
      shift 2
      ;;
    --task-model)
      TASK_MODEL="${2:-}"
      shift 2
      ;;
    --openclaw-image)
      OPENCLAW_IMAGE="${2:-}"
      shift 2
      ;;
    --spot)
      USE_SPOT="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$ANTHROPIC_API_KEY" ]]; then
  echo "Error: --anthropic-api-key is required." >&2
  usage
  exit 1
fi

for cmd in aws base64 date mktemp; do
  require_cmd "$cmd"
done

TIMESTAMP="$(date +%Y%m%d%H%M%S)"
RESOURCE_PREFIX="${NAME_PREFIX}-${TIMESTAMP}"
SECURITY_GROUP_NAME="${RESOURCE_PREFIX}-sg"
KEY_NAME="${RESOURCE_PREFIX}-key"
KEY_FILE="${KEY_NAME}.pem"
TAG_SPEC="ResourceType=instance,Tags=[{Key=Name,Value=${RESOURCE_PREFIX}},{Key=Project,Value=OpenClaw}]"

cleanup_files() {
  [[ -n "${USER_DATA_FILE:-}" && -f "$USER_DATA_FILE" ]] && rm -f "$USER_DATA_FILE"
}
trap cleanup_files EXIT

echo "Resolving default VPC and subnet in region $REGION ..."
VPC_ID="$(aws ec2 describe-vpcs --region "$REGION" --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
  echo "Error: no default VPC found in region $REGION." >&2
  exit 1
fi

SUBNET_ID="$(aws ec2 describe-subnets --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true --query 'Subnets[0].SubnetId' --output text)"
if [[ "$SUBNET_ID" == "None" || -z "$SUBNET_ID" ]]; then
  echo "Error: no default subnet found in region $REGION." >&2
  exit 1
fi

echo "Creating security group $SECURITY_GROUP_NAME ..."
SECURITY_GROUP_ID="$(aws ec2 create-security-group \
  --region "$REGION" \
  --group-name "$SECURITY_GROUP_NAME" \
  --description "OpenClaw access (${RESOURCE_PREFIX})" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text)"

aws ec2 authorize-security-group-ingress \
  --region "$REGION" \
  --group-id "$SECURITY_GROUP_ID" \
  --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":22,\"ToPort\":22,\"IpRanges\":[{\"CidrIp\":\"${SSH_CIDR}\",\"Description\":\"SSH\"}]},{\"IpProtocol\":\"tcp\",\"FromPort\":${OPENCLAW_PORT},\"ToPort\":${OPENCLAW_PORT},\"IpRanges\":[{\"CidrIp\":\"0.0.0.0/0\",\"Description\":\"OpenClaw\"}]}]" >/dev/null

echo "Creating key pair $KEY_NAME ..."
aws ec2 create-key-pair --region "$REGION" --key-name "$KEY_NAME" --query 'KeyMaterial' --output text > "$KEY_FILE"
set_key_file_permissions "$KEY_FILE"

AMI_ID="$(aws ssm get-parameter --region "$REGION" --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query 'Parameter.Value' --output text)"

echo "Using AMI: $AMI_ID"

USER_DATA_FILE="$(mktemp)"
cat > "$USER_DATA_FILE" <<USERDATA
#!/bin/bash
set -euxo pipefail

dnf update -y
dnf install -y docker git
action="enable"
systemctl ${action} --now docker
usermod -aG docker ec2-user

mkdir -p /opt/openclaw
cat > /opt/openclaw/.env <<ENVVARS
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
OPENCLAW_BASE_MODEL=${BASE_MODEL}
OPENCLAW_TASK_MODEL=${TASK_MODEL}
OPENCLAW_AWS_REGION=${REGION}
ENVVARS

cat > /opt/openclaw/docker-compose.yml <<COMPOSE
services:
  openclaw:
    image: ${OPENCLAW_IMAGE}
    container_name: openclaw
    restart: unless-stopped
    ports:
      - "${OPENCLAW_PORT}:${OPENCLAW_PORT}"
    env_file:
      - .env
COMPOSE

cd /opt/openclaw
docker compose up -d
USERDATA

RUN_ARGS=(
  --region "$REGION"
  --image-id "$AMI_ID"
  --instance-type "$INSTANCE_TYPE"
  --count 1
  --key-name "$KEY_NAME"
  --security-group-ids "$SECURITY_GROUP_ID"
  --subnet-id "$SUBNET_ID"
  --tag-specifications "$TAG_SPEC"
  --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":${VOLUME_GB},\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]"
  --user-data "file://${USER_DATA_FILE}"
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled"
)

if [[ "$USE_SPOT" == "true" ]]; then
  RUN_ARGS+=(--instance-market-options "MarketType=spot,SpotOptions={SpotInstanceType=one-time,InstanceInterruptionBehavior=terminate}")
fi

echo "Launching EC2 instance ..."
INSTANCE_ID="$(aws ec2 run-instances "${RUN_ARGS[@]}" --query 'Instances[0].InstanceId' --output text)"

echo "Waiting for instance to be running ..."
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
PUBLIC_DNS="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicDnsName' --output text)"
PUBLIC_IP="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"

echo
echo "OpenClaw instance created successfully."
echo "  Instance ID:     $INSTANCE_ID"
echo "  Region:          $REGION"
echo "  Instance type:   $INSTANCE_TYPE"
echo "  Security group:  $SECURITY_GROUP_ID"
echo "  SSH key file:    $KEY_FILE"
echo "  Public IP:       $PUBLIC_IP"
echo "  Public DNS:      $PUBLIC_DNS"
echo "  OpenClaw URL:    http://${PUBLIC_IP}:${OPENCLAW_PORT}"
echo
echo "SSH command:"
echo "  ssh -i ${KEY_FILE} ec2-user@${PUBLIC_DNS}"
echo
echo "IMPORTANT: Restrict SSH access after verification and rotate API keys if key file is exposed."
