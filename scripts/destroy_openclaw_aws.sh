#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/destroy_openclaw_aws.sh --instance-id <id> --region <region> [--security-group-id <id>] [--key-name <name>] [--key-file <file>]
USAGE
}

INSTANCE_ID=""
REGION=""
SECURITY_GROUP_ID=""
KEY_NAME=""
KEY_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance-id)
      INSTANCE_ID="${2:-}"
      shift 2
      ;;
    --region)
      REGION="${2:-}"
      shift 2
      ;;
    --security-group-id)
      SECURITY_GROUP_ID="${2:-}"
      shift 2
      ;;
    --key-name)
      KEY_NAME="${2:-}"
      shift 2
      ;;
    --key-file)
      KEY_FILE="${2:-}"
      shift 2
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

if [[ -z "$INSTANCE_ID" || -z "$REGION" ]]; then
  echo "Error: --instance-id and --region are required." >&2
  usage
  exit 1
fi

echo "Terminating instance $INSTANCE_ID ..."
aws ec2 terminate-instances --region "$REGION" --instance-ids "$INSTANCE_ID" >/dev/null
aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$INSTANCE_ID"

if [[ -n "$SECURITY_GROUP_ID" ]]; then
  echo "Deleting security group $SECURITY_GROUP_ID ..."
  aws ec2 delete-security-group --region "$REGION" --group-id "$SECURITY_GROUP_ID" >/dev/null
fi

if [[ -n "$KEY_NAME" ]]; then
  echo "Deleting key pair $KEY_NAME ..."
  aws ec2 delete-key-pair --region "$REGION" --key-name "$KEY_NAME" >/dev/null
fi

if [[ -n "$KEY_FILE" && -f "$KEY_FILE" ]]; then
  rm -f "$KEY_FILE"
  echo "Deleted local key file $KEY_FILE"
fi

echo "Cleanup complete."
