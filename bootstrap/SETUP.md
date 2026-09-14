# VM-only setup walkthrough

This document is for commands run **inside the provisioned VM** over SSH. Do not run these
commands on the local workstation. The local entrypoint is the repository root `./setup.sh`.
Terraform uploads `cloud-init.yaml`, which runs automatically inside the VM.

## 1. Shell and runtime

```bash
sudo apt-get update
sudo apt-get install -y zsh git curl jq nodejs npm
chsh -s /usr/bin/zsh "$USER"
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Log out/in once so the new zsh login shell is active.

## 2. Agent tools

```bash
export PATH="$HOME/.local/bin:$PATH"
npm install -g @earendil-works/pi-coding-agent cc-connect agent-browser
uv tool install 'agent-reach[all] @ https://github.com/Panniantong/agent-reach/archive/main.zip'
```

Verify:

```bash
pi --version
cc-connect --version
agent-browser --version
agent-reach --version
```

## 3. Telegram placeholders

```bash
mkdir -p ~/.hermes
cp telegram.env.example ~/.hermes/.env
chmod 600 ~/.hermes/.env
$EDITOR ~/.hermes/.env
```

Create the bot token with Telegram `@BotFather`. Restrict access with
`TELEGRAM_ALLOWED_USERS` using numeric Telegram user IDs. Do not put tokens in Terraform,
cloud-init, Git, or chat logs.

## 4. Chrome/CDP

Use the persistent profile created by the image/bootstrap:

```text
/home/ubuntu/.config/chrome-agent-profile
```

Start Chrome with CDP on loopback only (`127.0.0.1:9222`) and configure Hermes:

```bash
hermes config set browser.engine chrome
hermes config set browser.cdp_url http://127.0.0.1:9222
```

Never expose port 9222 publicly; use Tailscale/SSH for remote access.
