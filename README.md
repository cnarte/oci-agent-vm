# OCI Agent VM

Terraform inventory and bootstrap artifacts for an OCI ARM64 Ubuntu agent VM.

## Safety model

This is a reusable tutorial: by default it creates a complete, separate OCI VM/network in the
account selected by the user's OCI profile. It does not target or modify the author's account.
Set `enable_provisioning = false` for read-only discovery. Never commit credentials, cookies,
private keys, or browser profiles.

## Discovered baseline

- Region: `ap-mumbai-1`
- Availability domain: `AP-MUMBAI-1-AD-1`
- Shape: `VM.Standard.A1.Flex`
- Existing VCN CIDR: `10.0.0.0/16`
- Existing agent subnet CIDR: `10.0.1.0/24`
- OS: Ubuntu 22.04 ARM64

## Usage

Requires Terraform and the OCI CLI config profile. No API keys are committed.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Set tenancy_ocid and ssh_public_key for your own OCI account.
terraform init
terraform fmt
terraform plan
terraform apply
```

The default creates a new VCN, subnet, public-IP VM, and internet gateway. To inspect an existing
account without changes, set `enable_provisioning = false` and provide the existing resource IDs.

## Bootstrap and Telegram setup

See [`bootstrap/SETUP.md`](bootstrap/SETUP.md) for the complete post-provisioning walkthrough.
The Telegram template is [`bootstrap/telegram.env.example`](bootstrap/telegram.env.example): copy it
to `~/.hermes/.env` and replace the BotFather token and allowed Telegram user ID placeholders.

The cloud-init module installs and configures, for each fresh VM:

- zsh (with the user's existing Oh My Zsh setup instructions)
- uv-managed Python tools
- pi and cc-connect
- official Google Chrome ARM64
- persistent Chrome profile with local CDP
- XFCE + TigerVNC + noVNC behind Tailscale Serve

No credentials, cookies, SSH private keys, or Chrome profiles belong in this repository.
