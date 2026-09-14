# Personal Browser Agent VM with Harness setup

Provision a personal Linux browser-agent workstation on Oracle Cloud Infrastructure (OCI).
Terraform creates the network and ARM64 VM; cloud-init installs the desktop, Google Chrome,
Hermes Agent, pi, cc-connect, Agent Reach, VNC/noVNC, and Tailscale.

> **Safety:** This repository creates billable cloud resources. Read the plan before approving
> `terraform apply`. Never commit `settings.yaml`, Terraform state, Telegram tokens, SSH private
> keys, Tailscale keys, or browser profiles.

## Table of contents

- [What you get](#what-you-get)
- [Prerequisites](#prerequisites)
- [Recommended path: one YAML file](#recommended-path-one-yaml-file)
  - [Linux and macOS](#linux-and-macos)
  - [Windows](#windows)
- [After provisioning](#after-provisioning)
- [Manual VM path](#manual-vm-path)
- [Configuration reference](#configuration-reference)
- [Validation and cleanup](#validation-and-cleanup)
- [Security notes](#security-notes)
- [Troubleshooting](#troubleshooting)

## What you get

### OCI resources

- VCN (`10.0.0.0/16`)
- Public subnet (`10.0.1.0/24`)
- Internet gateway and route table
- Dedicated security list
- ARM64 `VM.Standard.A1.Flex` instance
- Public IP for initial SSH access

### VM software

- Ubuntu ARM64
- Bash and optional Git (the Hermes installer may install Git for its managed checkout)
- XFCE desktop
- TigerVNC + noVNC through loopback-only listeners
- Official Google Chrome for Linux ARM64
- Persistent Chrome profile at `~/.config/chrome-agent-profile`
- Chrome DevTools Protocol on `127.0.0.1:9222`
- uv, pi, Hermes Agent, cc-connect, and Agent Reach
- Tailscale

VNC, noVNC, and CDP are not opened in OCI security rules. Remote desktop access should use
Tailscale Serve or an SSH tunnel.

## Prerequisites

### Account and cloud access

1. [Create an Oracle Cloud account](https://www.oracle.com/cloud/free/).
2. Install the [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm).
3. Configure it with [`oci setup config`](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliconfigure.htm).
4. Verify the selected profile:

   ```bash
   oci iam region-subscription list
   ```

### Local tools

- [Terraform >= 1.6](https://developer.hashicorp.com/terraform/install)
- [Git](https://git-scm.com/downloads), or a ZIP download instead (the VM's base Git package is optional)
- Python 3 and PyYAML
- OpenSSH client and `ssh-keygen`
- `unzip` when using a ZIP download

### Telegram credentials (optional)

Telegram setup is optional. Use separate bots for Hermes and cc-connect so they do not compete
for the same update stream.

#### Create the bots

For each agent:

1. Open Telegram and message [`@BotFather`](https://t.me/BotFather).
2. Send `/newbot`.
3. Choose a display name and a username ending in `bot`.
4. Copy the token into the matching field in `settings.yaml`.

#### Find allowed users

1. Message [`@userinfobot`](https://t.me/userinfobot).
2. Send `/start`.
3. Copy your numeric user ID into `allowed_users`:

```yaml
telegram:
  hermes_bot_token: ""
  cc_connect_bot_token: ""
  allowed_users:
    - 123456789
```

If a token is empty, that agent's Telegram integration is skipped. If a token is present but
`allowed_users` is empty, do not enable that integration; add at least one numeric ID first.
Never commit the populated `settings.yaml`.

When using `setup.sh` or `setup.ps1`, non-empty tokens with a valid allowlist are transferred
once over the SSH connection after cloud-init completes. They are excluded from Terraform
variables and OCI user-data. The VM helper writes Hermes' `.env` and creates a minimal
cc-connect `config.toml`; existing cc-connect configuration is left untouched.

Terraform and OCI CLI run on the **local workstation**. The VM does not need Terraform or the
OCI CLI.

## Recommended path: one YAML file

Fork this repository first, then use your fork so your settings and future changes remain yours.

### Linux and macOS

```bash
git clone https://github.com/YOUR_USERNAME/oci-agent-vm.git
cd oci-agent-vm
python3 -m pip install --user pyyaml
cp settings.yaml.example settings.yaml
```

If Git is unavailable:

```bash
curl -L https://github.com/YOUR_USERNAME/oci-agent-vm/archive/refs/heads/main.zip -o agent-vm.zip
unzip agent-vm.zip
cd oci-agent-vm-main
python3 -m pip install --user pyyaml
cp settings.yaml.example settings.yaml
```

Edit `settings.yaml`:

```yaml
region: ap-mumbai-1
oci_profile: DEFAULT
tenancy_ocid: ocid1.tenancy.oc1..YOUR_TENANCY
compartment_ocid: ""
ssh_public_key: ""
ssh_private_key_path: ~/.ssh/oci-agent-vm_ed25519
ssh_ingress_cidr: 203.0.113.10/32
instance_name: personal-agent
instance_ocpus: 1
instance_memory_gb: 6
install_git: true
enable_provisioning: true

telegram:
  hermes_bot_token: ""
  cc_connect_bot_token: ""
  allowed_users: []
```

Leave `ssh_public_key` empty to let the script generate an Ed25519 key. The private key remains
on your workstation; only its public half is sent to OCI.

Run the local orchestrator:

```bash
./setup.sh
```

It checks prerequisites, creates the temporary Terraform variables file, initializes and validates
Terraform, shows the plan, and asks Terraform to apply it. After a successful apply it prints the
VM public IP and SSH command. If Telegram values are
configured, it also waits for cloud-init and performs the protected post-boot SSH configuration.
The temporary variables file is deleted when the script exits.

### Windows

Use PowerShell on the local workstation. Do **not** run the VM bootstrap script locally.

Install:

- [OCI CLI for Windows](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)
- [Terraform for Windows](https://developer.hashicorp.com/terraform/install)
- [Python for Windows](https://www.python.org/downloads/windows/)
- Windows OpenSSH client

Then:

```powershell
oci setup config
python -m pip install --user pyyaml
Invoke-WebRequest https://github.com/YOUR_USERNAME/oci-agent-vm/archive/refs/heads/main.zip -OutFile agent-vm.zip
Expand-Archive agent-vm.zip -DestinationPath .
Set-Location .\oci-agent-vm-main
Copy-Item settings.yaml.example settings.yaml
notepad settings.yaml
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
```

`setup.ps1` performs the same local workflow as `setup.sh` and generates the SSH key with
Windows OpenSSH. No Linux commands are run on Windows.

## After provisioning

SSH into the VM using the generated key and the public IP printed by OCI:

```bash
ssh -i ~/.ssh/oci-agent-vm_ed25519 ubuntu@PUBLIC_IP
```

Cloud-init runs automatically. Check it with:

```bash
cloud-init status --wait
systemctl status agent-vnc agent-novnc agent-chrome
```

Authenticate Tailscale:

```bash
sudo tailscale up
```

Follow the displayed authentication URL, then publish noVNC to your tailnet only:

```bash
sudo tailscale serve --bg 6080
sudo tailscale serve status
```

Open the generated HTTPS tailnet URL in your local browser. The VNC password is stored at:

```bash
cat ~/.config/remote-desktop/vnc-password.txt
```

Log into websites through the visible Chrome window. Credentials and cookies remain in the VM's
persistent Chrome profile.

Configure Hermes to attach to that exact Chrome instance. On first use, also complete its
provider setup and authentication:

```bash
hermes setup
hermes config set browser.engine chrome
hermes config set browser.cdp_url http://127.0.0.1:9222
hermes gateway                 # start Hermes Telegram/messaging gateway when configured
cc-connect                    # start cc-connect separately when configured
```

Run the two gateway commands in separate terminal sessions if you configure both bots.

## Manual VM path

Terraform is optional. To create only the VM manually:

1. Create an Ubuntu 22.04 ARM64 OCI instance.
2. Add your SSH public key in the OCI console.
3. Allow TCP/22 only from your workstation IP.
4. SSH into the VM.
5. Download and run the VM-only installer—no Git is required:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/oci-agent-vm/main/bootstrap/setup-vm.sh \
  -o /tmp/setup-vm.sh
chmod +x /tmp/setup-vm.sh
sudo INSTALL_GIT=false bash /tmp/setup-vm.sh
```

This skips the installer's base Git package. The official Hermes installer can still install Git because its managed checkout uses Git.

Or copy the `bootstrap` directory from a ZIP and run:

```bash
sudo INSTALL_GIT=false bash bootstrap/setup-vm.sh
```

When the full `bootstrap` directory is copied, the Telegram helper is installed at
`/usr/local/sbin/configure-agent-telegram.py`. To configure it without putting tokens in shell
arguments or history:

```bash
python3 - <<'PY'
import getpass, json, subprocess

payload = {
    "hermes_bot_token": getpass.getpass("Hermes bot token (blank to skip): "),
    "cc_connect_bot_token": getpass.getpass("cc-connect bot token (blank to skip): "),
    "allowed_users": [x.strip() for x in input("Allowed numeric Telegram user IDs (comma-separated): ").split(",") if x.strip()],
}
subprocess.run(["python3", "/usr/local/sbin/configure-agent-telegram.py"],
               input=json.dumps(payload), text=True, check=True)
PY
```

The direct one-file download cannot transfer local `settings.yaml` secrets.

The root `setup.sh` and `setup.ps1` are local-workstation scripts. The `bootstrap` scripts are
VM scripts and must not be run on Windows, macOS, or your Linux workstation.

## Configuration reference

| Setting | Purpose |
|---|---|
| `region` | OCI region |
| `oci_profile` | Profile in `~/.oci/config` or the Windows OCI config |
| `tenancy_ocid` | Your OCI tenancy |
| `compartment_ocid` | Target compartment; empty uses the tenancy |
| `ssh_ingress_cidr` | CIDR allowed to SSH; use your IP with `/32` |
| `ssh_public_key` | Optional existing public key |
| `ssh_private_key_path` | Local key path generated by setup |
| `availability_domain` | Optional AD; blank selects the first AD in the selected region |
| `instance_ocpus` / `instance_memory_gb` | ARM VM size |
| `install_git` | Install the base Git package; Hermes may install Git independently |
| `enable_provisioning` | `true` creates resources; `false` enables discovery mode |
| `telegram.*` | Optional post-provisioning Telegram configuration |

## Validation and cleanup

Before publishing changes:

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
bash -n setup.sh bootstrap/setup-vm.sh
```

To remove resources created by Terraform:

```bash
terraform -chdir=terraform destroy
```

Review the destroy plan carefully. Manually created OCI resources are not managed by this
repository.

## Security notes

- Keep `settings.yaml` and Terraform state private.
- Use a narrow `ssh_ingress_cidr`; do not leave `0.0.0.0/0` unless necessary.
- Never expose ports 5901, 6080, or 9222 publicly.
- Use Tailscale Serve, not Tailscale Funnel, for noVNC.
- Use separate Telegram bots and a non-empty allowlist.
- Review third-party installer/version changes before production use.
- Use a remote encrypted Terraform backend for team usage.

## Troubleshooting

### Terraform cannot authenticate

Run `oci iam region-subscription list` using the same profile named in `settings.yaml` and verify
that the profile's region and tenancy are correct.

### SSH says `Permission denied (publickey)`

Confirm the public key in `settings.yaml` matches the private key used with `ssh -i`, and check
that `ssh_ingress_cidr` includes your current public IP.

### Cloud-init failed

Inspect:

```bash
sudo cloud-init status --long
sudo tail -200 /var/log/cloud-init-output.log
```

### noVNC loads but the desktop is unavailable

Check the loopback services on the VM:

```bash
ss -ltnp | grep -E ':(5901|6080|9222)'
systemctl status agent-vnc agent-novnc agent-chrome
```
