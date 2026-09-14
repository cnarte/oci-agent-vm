# Personal Browser + Hermes Agent VM on OCI

This repo creates a fresh ARM64 Ubuntu VM for a personal browser agent and Hermes Agent.
Terraform provisions the OCI network and VM; cloud-init installs the complete software stack.
It does **not** modify this account unless you run it with this account's OCI profile.

## Two execution contexts

There are deliberately two separate contexts:

- **Local workstation:** run only the root `./setup.sh`. It uses your OCI CLI credentials,
  generates the SSH key, and runs Terraform.
- **Provisioned VM:** `bootstrap/cloud-init.yaml` is uploaded as OCI user-data and runs inside
  the VM. It installs the browser/agent stack. Commands in `bootstrap/SETUP.md` are VM-only.

Do not run cloud-init or VM setup commands on the local workstation.

## One-file setup path

1. Install and authenticate the OCI CLI locally (`oci setup config`).
2. Install Terraform >= 1.6.
3. Clone this repo.
4. Set `ssh_ingress_cidr` in `settings.yaml` to your public IP with `/32` when possible.
   The example uses `0.0.0.0/0` only as a compatibility default; narrowing it is strongly recommended.
5. Create an SSH key, or let the setup script create one:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/oci-agent-vm_ed25519
   ```
   Keep the private key safe. Only the `.pub` key is installed on the VM. If you skip this step,
   `setup.sh` generates the key automatically.
6. Copy `settings.yaml.example` to `settings.yaml` and edit the tenancy/compartment OCID, region, and VM size.
   Leave `ssh_public_key` empty to use the generated key, or paste the contents of your `.pub` file.
7. Run:

```bash
./setup.sh
```

The script generates the SSH key when needed, converts the YAML to a temporary ignored Terraform
variable file, runs `init`, `validate`, `plan`, and `apply`, then removes the generated file. Review
the plan before confirming `apply`; keep the generated private key safe.

## What it creates and installs

Terraform creates a VCN, internet gateway, route table, public subnet, and ARM64
`VM.Standard.A1.Flex` instance. Cloud-init installs:

- zsh, XFCE, TigerVNC, noVNC, and websockify
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
