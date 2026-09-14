#!/usr/bin/env bash
# LOCAL MACHINE ONLY: run this from the user's laptop/workstation.
# VM bootstrap code lives in bootstrap/cloud-init.yaml and runs only on first boot.
set -euo pipefail
cd "$(dirname "$0")/terraform"
ROOT=$(cd .. && pwd)
SETTINGS=${SETTINGS_FILE:-$ROOT/settings.yaml}
command -v terraform >/dev/null || { echo 'Install Terraform first: https://developer.hashicorp.com/terraform/install'; exit 1; }
[ -f "$SETTINGS" ] || { echo "Missing $SETTINGS (copy settings.yaml.example first)"; exit 1; }
KEY_PATH=$(python3 - "$SETTINGS" <<'PY'
import os, sys, yaml
s = yaml.safe_load(open(sys.argv[1])) or {}
print(os.path.expanduser(s.get('ssh_private_key_path', '~/.ssh/oci-agent-vm_ed25519')))
PY
)
SSH_PUBLIC=$(python3 - "$SETTINGS" <<'PY'
import sys, yaml
print((yaml.safe_load(open(sys.argv[1])) or {}).get('ssh_public_key', '') or '')
PY
)
if [ -z "$SSH_PUBLIC" ]; then
  mkdir -p "$(dirname "$KEY_PATH")"; chmod 700 "$(dirname "$KEY_PATH")"
  [ -f "$KEY_PATH" ] || ssh-keygen -t ed25519 -f "$KEY_PATH" -N '' -C 'oci-agent-vm'
  SSH_PUBLIC=$(ssh-keygen -y -f "$KEY_PATH")
fi
export SSH_PUBLIC
python3 - "$SETTINGS" > settings.auto.tfvars.json <<'PY'
import json, os, sys
try:
    import yaml
except ImportError:
    raise SystemExit('PyYAML is required: sudo apt-get install python3-yaml')
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
# Keep non-Terraform settings (Telegram tokens, key path, etc.) out of
# Terraform variables/state. They are handled by a later, explicit post-boot
# step rather than being embedded in OCI metadata.
allowed = {
    'region', 'oci_profile', 'tenancy_ocid', 'vcn_id', 'subnet_id',
    'instance_id', 'enable_provisioning', 'availability_domain',
    'compartment_ocid', 'ssh_public_key', 'instance_name',
    'instance_ocpus', 'instance_memory_gb', 'ssh_ingress_cidr', 'install_git',
}
data = {k: v for k, v in data.items() if k in allowed}
data['ssh_public_key'] = os.environ['SSH_PUBLIC'].strip()
print(json.dumps(data, indent=2))
PY
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
rm -f settings.auto.tfvars.json
