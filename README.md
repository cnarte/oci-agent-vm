# Personal Browser + Hermes Agent VM on OCI

This repo creates a fresh ARM64 Ubuntu VM for a personal browser agent and Hermes Agent.
Terraform provisions the OCI network and VM; cloud-init installs the complete software stack.
It does **not** modify this account unless you run it with this account's OCI profile.

## Prerequisites

- [Create an Oracle Cloud account](https://www.oracle.com/cloud/free/)
- [Install the OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)
- [Configure the OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliconfigure.htm)
- [Install Terraform](https://developer.hashicorp.com/terraform/install) (version 1.6 or newer)
- [Install Git](https://git-scm.com/downloads)
- Python 3 and PyYAML

## Two execution contexts

There are deliberately two separate contexts:

- **Local workstation:** run only the root `./setup.sh`. It uses your OCI CLI credentials,
  generates the SSH key, and runs Terraform.
- **Provisioned VM:** `bootstrap/cloud-init.yaml` is uploaded as OCI user-data and runs inside
  the VM. It installs the browser/agent stack. Commands in `bootstrap/SETUP.md` are VM-only.

Do not run cloud-init or VM setup commands on the local workstation.

## One-file setup path

### Linux/macOS workstation

1. Install and authenticate the OCI CLI locally (`oci setup config`).
2. Install Terraform >= 1.6.
3. Install Python 3 and PyYAML (`python3 -m pip install --user pyyaml`).
4. Clone this repo.
5. Copy `settings.yaml.example` to `settings.yaml` and edit the tenancy/compartment OCID, region, and VM size.
6. Set `ssh_ingress_cidr` in `settings.yaml` to your public IP with `/32` when possible.
   The example uses `0.0.0.0/0` only as a compatibility default; narrowing it is strongly recommended.
7. Create an SSH key, or let the setup script create one:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/oci-agent-vm_ed25519
   ```
   Keep the private key safe. Only the `.pub` key is installed on the VM. If you skip this step,
   `setup.sh` generates the key automatically.
Leave `ssh_public_key` empty to use the generated key, or paste the contents of your `.pub` file.
8. Run:

```bash
./setup.sh
```

### Windows workstation

Use PowerShell (not the VM bootstrap script). Install the [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm),
[Terraform](https://developer.hashicorp.com/terraform/install),
[Python](https://www.python.org/downloads/windows/), and Windows OpenSSH. Then:

```powershell
oci setup config
python -m pip install --user pyyaml
Copy-Item settings.yaml.example settings.yaml
notepad settings.yaml
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
```

`setup.ps1` generates the SSH key with Windows OpenSSH and performs the same local Terraform
workflow as `setup.sh`. `bootstrap/cloud-init.yaml` still runs only inside the Linux VM.

The script generates the SSH key when needed, converts the YAML to a temporary ignored Terraform
variable file, runs `init`, `validate`, `plan`, and `apply`, then removes the generated file. Review
the plan before confirming `apply`; keep the generated private key safe.

## Manual VM alternative

If you do not want Terraform to create the VM, create an Ubuntu 22.04 ARM64 instance manually
in the OCI console. Allow SSH only from your workstation IP, then copy this repository to the VM:

```bash
scp -i ~/.ssh/oci-agent-vm_ed25519 -r bootstrap ubuntu@<PUBLIC_IP>:/home/ubuntu/
ssh -i ~/.ssh/oci-agent-vm_ed25519 ubuntu@<PUBLIC_IP>
sudo bash bootstrap/setup-vm.sh
```

`bootstrap/setup-vm.sh` is VM-only. It installs the same desktop, Chrome, agent, and browser
stack as cloud-init and creates persistent services. Finish with:

```bash
sudo tailscale up
tailscale serve --bg 6080
```

## What it creates and installs

Terraform creates a VCN, internet gateway, route table, public subnet, and ARM64
`VM.Standard.A1.Flex` instance. Cloud-init installs:

- Bash, XFCE, TigerVNC, noVNC, and websockify
- official Google Chrome for Linux ARM64
- persistent Chrome profile and loopback CDP on port 9222
- uv, Agent Reach, pi, and cc-connect
- Tailscale (authentication remains an explicit manual step)

After first boot:

```bash
sudo tailscale up
cp ~/.hermes/.env.example ~/.hermes/.env
$EDITOR ~/.hermes/.env                 # add TELEGRAM_BOT_TOKEN if desired
hermes config set browser.engine chrome
hermes config set browser.cdp_url http://127.0.0.1:9222
```

Use Tailscale Serve to publish noVNC to the tailnet only; never expose VNC or CDP directly
through OCI security rules. Telegram tokens, Tailscale auth keys, OCI keys, SSH private keys,
and Chrome profiles are intentionally not stored in this repository.

## Read-only discovery

To inspect an existing account without creating resources, set `enable_provisioning: false`
in `settings.yaml` and provide existing `vcn_id`, `subnet_id`, and `instance_id` values in a
local generated variable file, or run Terraform with those variables explicitly.
