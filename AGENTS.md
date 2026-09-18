# AI agent setup runbook

Use this runbook when an AI coding agent is asked to provision this repository. Commands in this
file are for the **local workstation** unless explicitly marked as VM commands.

## 1. Preflight

1. Inspect `README.md`, `settings.yaml` (without printing secrets), and the current Git status.
2. Confirm the OCI CLI is already installed and authenticated. Do not run an OCI login or create
   credentials on the user's behalf:

   ```bash
   oci iam region-subscription list --profile DEFAULT
   ```

   Use the profile from `settings.yaml` instead of `DEFAULT` when necessary. Stop and ask the
   user to authenticate if this command fails.
3. Confirm Terraform, Python 3 with PyYAML, OpenSSH (`ssh` and `ssh-keygen`), and Git or a ZIP
   checkout are available.
4. Never print or commit `settings.yaml`, Terraform state, OCI keys, Telegram tokens, or browser
   profiles.

The OCI CLI profile supplies the tenancy OCID. `tenancy_ocid` is not required in
`settings.yaml`; it is only an optional override. The VM does not need Terraform or the OCI CLI.

## 2. Prepare settings

If `settings.yaml` does not exist, create it from the example:

```bash
cp settings.yaml.example settings.yaml
```

Set only the deployment choices that are needed, especially:

- `region` and `oci_profile`
- `ssh_ingress_cidr` (prefer the user's public IP with `/32`, never leave `0.0.0.0/0` unless explicitly requested)
- VM size and `instance_name`
- optional `availability_domain` or `fault_domain`
- `enable_provisioning: true` for a new deployment
- optional Telegram tokens and numeric `allowed_users`

Leave `ssh_public_key` empty to let the script create an Ed25519 key. The private key stays on
the workstation. Do not put OCI private-key contents, passwords, or tokens in this file.

## 3. Run the local orchestrator

Run exactly one script, selected by the workstation operating system. Do not run the VM bootstrap
script on the workstation.

Linux/macOS:

```bash
./setup.sh
```

Windows PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
```

The script checks OCI authentication, derives the tenancy from the selected OCI profile, creates
temporary Terraform variables, initializes and validates Terraform, shows a plan, and applies it.
Review the plan before approving any resource creation. Do not use `-auto-approve` unless the user
has explicitly authorized unattended provisioning.

A successful provisioning run prints the VM public IP, an SSH command, and (after cloud-init)
the VNC password requested by the user. Terraform resources are billable; do not repeat or store
that password unnecessarily.

## 4. Verify the VM

Use the printed key and IP. On Windows, use the printed Windows key path.

```bash
ssh -i ~/.ssh/oci-agent-vm_ed25519 ubuntu@PUBLIC_IP
```

Then run inside the VM:

```bash
cloud-init status --wait
systemctl is-active agent-vnc agent-novnc agent-chrome
ss -ltn | grep -E ':(5901|6080|9222)'
```

The listeners must remain loopback-only. Do not add ports 5901, 6080, or 9222 to the OCI
security list. If SSH is not ready, retry after cloud-init starts and inspect
`/var/log/cloud-init-output.log`; do not claim setup succeeded merely because Terraform applied.

## 5. Complete interactive services

Tailscale requires user authentication and must not be faked by an agent:

```bash
sudo tailscale up
sudo tailscale serve --bg 6080
sudo tailscale serve status
```

Open the displayed tailnet HTTPS URL to access noVNC. The setup script prints the VNC password
once after cloud-init; it can also be read from `~/.config/remote-desktop/vnc-password.txt` over
SSH. Treat it as a secret and do not commit or share it.

Configure the browser agent against the existing Chrome instance:

```bash
hermes setup
hermes config set browser.engine chrome
hermes config set browser.cdp_url http://127.0.0.1:9222
```

The VM also installs the Codex CLI. Run its provider authentication interactively:

```bash
codex login
```

Run `hermes gateway` and `cc-connect` in separate sessions only when their integrations are
configured. Provider authentication is also an interactive user step.

## 6. Telegram fallback

The local setup scripts transfer valid Telegram settings after cloud-init. If that step fails,
configure them inside the VM with the installed helper. Use stdin prompts so tokens do not appear
in shell history, process arguments, Terraform, user-data, or logs:

```bash
python3 - <<'PY'
import getpass, json, subprocess

payload = {
    "hermes_bot_token": getpass.getpass("Hermes bot token (blank to skip): "),
    "cc_connect_bot_token": getpass.getpass("cc-connect bot token (blank to skip): "),
    "allowed_users": [
        x.strip()
        for x in input("Allowed numeric Telegram user IDs (comma-separated): ").split(",")
        if x.strip()
    ],
}
subprocess.run(
    ["python3", "/usr/local/sbin/configure-agent-telegram.py"],
    input=json.dumps(payload),
    text=True,
    check=True,
)
PY
```

## Completion checklist

Report setup as complete only when:

- Terraform apply completed without errors and the expected VM IP was printed.
- SSH works with the generated key.
- `cloud-init status --wait` succeeds.
- `agent-vnc`, `agent-novnc`, and `agent-chrome` are active.
- Tailscale/noVNC and any agent authentication steps, including `codex login` when requested, are completed by the user.
- No secrets were printed, committed, or added to OCI user-data.

For teardown, show the user the destroy plan and run `terraform -chdir=terraform destroy` only after
explicit confirmation.
