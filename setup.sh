#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/terraform"
ROOT=$(cd .. && pwd)
SETTINGS=${SETTINGS_FILE:-$ROOT/settings.yaml}
command -v terraform >/dev/null || { echo 'Install Terraform first: https://developer.hashicorp.com/terraform/install'; exit 1; }
python3 - "$SETTINGS" > settings.auto.tfvars.json <<'PY'
import json, sys
try:
    import yaml
except ImportError:
    raise SystemExit('PyYAML is required: sudo apt-get install python3-yaml')
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
print(json.dumps(data, indent=2))
PY
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
rm -f settings.auto.tfvars.json
