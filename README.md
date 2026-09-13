# Personal Browser + Hermes Agent VM on OCI

This repo creates a fresh ARM64 Ubuntu VM for a personal browser agent and Hermes Agent.
Terraform provisions the OCI network and VM; cloud-init installs the complete software stack.
It does **not** modify this account unless you run it with this account's OCI profile.

## One-file setup path

1. Install and authenticate the OCI CLI locally (`oci setup config`).
2. Install Terraform >= 1.6.
3. Clone this repo.
4. Copy `settings.yaml.example` to `settings.yaml` and edit the tenancy/compartment OCID, region, and VM size.
   Leave `ssh_public_key` empty to have the setup script generate a new Ed25519 key at the configured path.
5. Run:

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
