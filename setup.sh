#!/usr/bin/env bash
# LOCAL MACHINE ONLY: run this from the user's laptop/workstation.
# VM bootstrap code lives in bootstrap/cloud-init.yaml and runs only on first boot.
set -euo pipefail
cd "$(dirname "$0")/terraform"
ROOT=$(cd .. && pwd)
SETTINGS=${SETTINGS_FILE:-$ROOT/settings.yaml}
TERRAFORM=$(command -v terraform || true)
[ -n "$TERRAFORM" ] || [ ! -x "$HOME/.local/bin/terraform" ] || TERRAFORM="$HOME/.local/bin/terraform"
[ -n "$TERRAFORM" ] || { echo 'Install Terraform first: https://developer.hashicorp.com/terraform/install'; exit 1; }
OCI=$(command -v oci || true)
[ -n "$OCI" ] || [ ! -x "$HOME/bin/oci" ] || OCI="$HOME/bin/oci"
[ -n "$OCI" ] || { echo 'Install the OCI CLI first: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm'; exit 1; }
command -v python3 >/dev/null || { echo 'Install Python 3 first: https://www.python.org/downloads/'; exit 1; }
command -v ssh-keygen >/dev/null || { echo 'Install OpenSSH (including ssh-keygen) first.'; exit 1; }
command -v ssh >/dev/null || { echo 'Install OpenSSH (including the ssh client) first.'; exit 1; }
python3 -c 'import yaml' 2>/dev/null || { echo 'Install PyYAML first: python3 -m pip install --user pyyaml'; exit 1; }
[ -f "$SETTINGS" ] || { echo "Missing $SETTINGS (copy settings.yaml.example first)"; exit 1; }
OCI_PROFILE=$(python3 - "$SETTINGS" <<'PY'
import sys, yaml
s = yaml.safe_load(open(sys.argv[1])) or {}
print(s.get('oci_profile') or 'DEFAULT')
PY
)
if ! "$OCI" iam region-subscription list --profile "$OCI_PROFILE" >/dev/null; then
  echo "OCI CLI authentication failed for profile '$OCI_PROFILE'. Configure or log in to OCI before running setup.sh." >&2
  echo "Verify with: $OCI iam region-subscription list --profile $OCI_PROFILE" >&2
  exit 1
fi
TENANCY_OCID=$(python3 - "$SETTINGS" "$OCI_PROFILE" <<'PY'
import configparser, os, sys, yaml

settings = yaml.safe_load(open(sys.argv[1])) or {}
configured = str(settings.get('tenancy_ocid') or '').strip()
if configured and 'REPLACE' not in configured.upper() and 'YOUR_TENANCY' not in configured.upper():
    print(configured)
    raise SystemExit(0)

profile = sys.argv[2]
config_path = os.path.expanduser(os.environ.get('OCI_CLI_CONFIG_FILE', '~/.oci/config'))
parser = configparser.RawConfigParser()
if not parser.read(config_path):
    raise SystemExit(f"OCI config file not found: {config_path}")
if profile == parser.default_section:
    values = parser.defaults()
elif parser.has_section(profile):
    values = parser[profile]
else:
    raise SystemExit(f"OCI profile not found in {config_path}: {profile}")
tenancy = values.get('tenancy', '').strip()
if not tenancy:
    raise SystemExit(f"OCI profile has no tenancy OCID: {profile}")
print(tenancy)
PY
) || {
  echo "Could not determine the tenancy OCID from OCI profile '$OCI_PROFILE'. Set tenancy_ocid in settings.yaml to override it." >&2
  exit 1
}
export TENANCY_OCID
ENABLE_PROVISIONING=$(python3 - "$SETTINGS" <<'PY'
import sys, yaml
s = yaml.safe_load(open(sys.argv[1])) or {}
print('true' if s.get('enable_provisioning', True) is not False else 'false')
PY
)
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
elif [ ! -r "$KEY_PATH" ]; then
  echo "ssh_private_key_path is required and readable when ssh_public_key is supplied: $KEY_PATH" >&2
  exit 1
fi
export SSH_PUBLIC
trap 'rm -f settings.auto.tfvars.json' EXIT
python3 - "$SETTINGS" > settings.auto.tfvars.json <<'PY'
import json, os, sys
try:
    import yaml
except ImportError:
    raise SystemExit('PyYAML is required: sudo apt-get install python3-yaml')
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
# Keep non-Terraform settings (Telegram tokens, key path, etc.) out of
# Terraform variables/state. They are handled by the explicit post-boot SSH step below
# rather than being embedded in OCI metadata.
allowed = {
    'region', 'oci_profile', 'tenancy_ocid', 'vcn_id', 'subnet_id',
    'instance_id', 'enable_provisioning', 'availability_domain', 'fault_domain',
    'compartment_ocid', 'ssh_public_key', 'instance_name',
    'instance_ocpus', 'instance_memory_gb', 'ssh_ingress_cidr', 'install_git',
}
data = {k: v for k, v in data.items() if k in allowed}
data['ssh_public_key'] = os.environ['SSH_PUBLIC'].strip()
data['tenancy_ocid'] = os.environ['TENANCY_OCID']
print(json.dumps(data, indent=2))
PY
"$TERRAFORM" init
"$TERRAFORM" fmt -recursive
"$TERRAFORM" validate
"$TERRAFORM" plan
if [ "$ENABLE_PROVISIONING" != true ]; then
  printf 'Provisioning disabled; plan completed without applying changes.\n'
  exit 0
fi
"$TERRAFORM" apply
PUBLIC_IP=$("$TERRAFORM" output -raw created_instance_public_ip 2>/dev/null || true)
if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "null" ]; then
  printf '\nVM public IP: %s\n' "$PUBLIC_IP"
  printf 'SSH command: ssh -i %s ubuntu@%s\n' "$KEY_PATH" "$PUBLIC_IP"

  VNC_SSH_ARGS=(-i "$KEY_PATH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
  printf 'Waiting for SSH/cloud-init before retrieving the VNC password...\n'
  VNC_SSH_READY=false
  for _ in $(seq 1 30); do
    if ssh "${VNC_SSH_ARGS[@]}" "ubuntu@$PUBLIC_IP" 'true' >/dev/null 2>&1; then
      VNC_SSH_READY=true
      break
    fi
    sleep 10
  done
  if [ "$VNC_SSH_READY" = true ] && ssh "${VNC_SSH_ARGS[@]}" "ubuntu@$PUBLIC_IP" 'timeout 900 cloud-init status --wait' >/dev/null 2>&1; then
    VNC_PASSWORD=$(ssh "${VNC_SSH_ARGS[@]}" "ubuntu@$PUBLIC_IP" 'cat ~/.config/remote-desktop/vnc-password.txt' 2>/dev/null || true)
    if [ -n "$VNC_PASSWORD" ]; then
      printf 'VNC password: %s\n' "$VNC_PASSWORD"
      printf 'VNC password file: ~/.config/remote-desktop/vnc-password.txt\n'
      printf 'Warning: treat the VNC password as a secret and do not commit or share it.\n' >&2
    else
      printf 'Warning: VNC password was not available; retrieve it over SSH after cloud-init completes.\n' >&2
    fi
  else
    printf 'Warning: SSH/cloud-init was not ready; VNC password was not retrieved.\n' >&2
  fi

  TELEGRAM_PAYLOAD=$(python3 - "$SETTINGS" <<'PY'
import json, re, sys, yaml
s = yaml.safe_load(open(sys.argv[1])) or {}
tg = s.get('telegram') or {}
users = tg.get('allowed_users') or []
hermes = tg.get('hermes_bot_token') or ''
cc = tg.get('cc_connect_bot_token') or ''
if not hermes and not cc:
    raise SystemExit(0)
if not isinstance(users, list) or not users or any(not re.fullmatch(r'[0-9]+', str(u)) for u in users):
    raise SystemExit('Telegram tokens supplied but allowed_users is empty or contains a non-numeric ID')
for name, token in [('hermes_bot_token', hermes), ('cc_connect_bot_token', cc)]:
    if token and (not isinstance(token, str) or not re.fullmatch(r'[0-9]+:[A-Za-z0-9_-]+', token)):
        raise SystemExit(f'{name} has an invalid Telegram token format')
print(json.dumps({'hermes_bot_token': hermes, 'cc_connect_bot_token': cc,
                  'allowed_users': [str(u) for u in users]}))
PY
  ) || {
    printf 'Warning: Telegram setup skipped because settings.yaml is invalid.\n' >&2
    TELEGRAM_PAYLOAD=''
  }
  if [ -n "$TELEGRAM_PAYLOAD" ] && [ -r "$KEY_PATH" ]; then
    SSH_ARGS=(-i "$KEY_PATH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
    printf 'Waiting for SSH/cloud-init before configuring Telegram...\n'
    SSH_READY=false
    for _ in $(seq 1 30); do
      if ssh "${SSH_ARGS[@]}" "ubuntu@$PUBLIC_IP" 'true' >/dev/null 2>&1; then
        SSH_READY=true
        break
      fi
      sleep 10
    done
    if [ "$SSH_READY" = true ]; then
      if ssh "${SSH_ARGS[@]}" "ubuntu@$PUBLIC_IP" 'timeout 900 cloud-init status --wait' >/dev/null 2>&1; then
        if ! printf '%s' "$TELEGRAM_PAYLOAD" | ssh "${SSH_ARGS[@]}" "ubuntu@$PUBLIC_IP" 'python3 /usr/local/sbin/configure-agent-telegram.py'; then
          printf 'Warning: automatic Telegram setup failed; configure it manually on the VM.\n' >&2
        fi
      else
        printf 'Warning: cloud-init did not finish; Telegram setup was not attempted.\n' >&2
      fi
    else
      printf 'Warning: SSH was not ready; Telegram setup was not attempted.\n' >&2
    fi
  elif [ -n "$TELEGRAM_PAYLOAD" ]; then
    printf 'Warning: SSH private key is unavailable; Telegram setup was not attempted.\n' >&2
  fi
fi
