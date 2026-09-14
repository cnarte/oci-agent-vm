# VM-only setup walkthrough

This document is for commands run **inside the provisioned VM** over SSH. Do not run these
commands on the local workstation. The local entrypoint is the repository root `./setup.sh`.
Terraform uploads `cloud-init.yaml`, which runs automatically inside the VM.

## 1. Runtime

Cloud-init installs Bash and curl plus the desktop/browser dependencies. Git is optional at the
base layer, and the official Hermes installer may install it for its managed checkout. No shell
startup file needs to be modified; use `~/.bashrc` only for optional interactive aliases or PATH
additions.

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

## 2. Agent tools

The bootstrap installs Hermes Agent with its official installer, plus pi, cc-connect, and
Agent Reach. If a manual re-run is needed, use `bootstrap/setup-vm.sh` as root.

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

## 3. Telegram

The local setup scripts can transfer populated Telegram settings once over SSH after cloud-init.
For a manual VM setup, configure the installed helper or edit the agent configuration directly:

Use an interactive prompt so tokens are not placed in shell arguments or history:

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

The helper expects `hermes_bot_token`, `cc_connect_bot_token`, and a non-empty numeric
`allowed_users` array as JSON. Create bot tokens with Telegram `@BotFather`. Do not put tokens in
Terraform, cloud-init, Git, or chat logs.

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
