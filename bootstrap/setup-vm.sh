#!/usr/bin/env bash
# VM ONLY: run after SSHing into an Ubuntu ARM64 VM.
# The root setup.sh is for the local workstation and must not be run here.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo bash bootstrap/setup-vm.sh" >&2
  exit 1
fi

TARGET_USER=${TARGET_USER:-ubuntu}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
INSTALL_GIT=${INSTALL_GIT:-true}
export DEBIAN_FRONTEND=noninteractive

apt-get update
packages=(ca-certificates curl wget jq openssl dbus-x11 xfce4 tigervnc-standalone-server novnc websockify)
if [ "$INSTALL_GIT" = "true" ]; then packages+=(git); fi
apt-get install -y "${packages[@]}"

# Codex CLI and the current Hermes tooling require a modern Node.js runtime.
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME"
chmod 750 "$TARGET_HOME"
cat > /etc/profile.d/agent-local-bin.sh <<EOF
export PATH=$TARGET_HOME/.local/bin:$TARGET_HOME/.hermes/node/bin:\$PATH
EOF
chmod 0644 /etc/profile.d/agent-local-bin.sh
install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 700 \
  "$TARGET_HOME/.vnc" "$TARGET_HOME/.config/remote-desktop" \
  "$TARGET_HOME/.config/chrome-agent-profile" "$TARGET_HOME/.config/autostart" \
  "$TARGET_HOME/.config/xfce4/xfconf/xfce-perchannel-xml" \
  "$TARGET_HOME/.hermes" "$TARGET_HOME/.local"
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.vnc" "$TARGET_HOME/.config" "$TARGET_HOME/.hermes" "$TARGET_HOME/.local"
cat > "$TARGET_HOME/.config/autostart/xfce4-screensaver.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=XFCE Screensaver
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/autostart/xfce4-screensaver.desktop"
chmod 0644 "$TARGET_HOME/.config/autostart/xfce4-screensaver.desktop"
cat > "$TARGET_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-screensaver" version="1.0">
  <property name="saver" type="empty">
    <property name="enabled" type="bool" value="false"/>
  </property>
  <property name="lock" type="empty">
    <property name="enabled" type="bool" value="false"/>
  </property>
</channel>
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml"
chmod 0644 "$TARGET_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml"
if [ -f "$SCRIPT_DIR/configure-telegram.py" ]; then
  install -o root -g root -m 0755 "$SCRIPT_DIR/configure-telegram.py" /usr/local/sbin/configure-agent-telegram.py
fi

# Official Google Chrome ARM64 package.
curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb -o /tmp/google-chrome.deb
apt-get install -y /tmp/google-chrome.deb
rm -f /tmp/google-chrome.deb

# Install user tools as ubuntu, not as root.
runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" bash -lc \
  'curl -LsSf https://astral.sh/uv/install.sh | sh'
runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" bash -lc \
  'export PATH="$HOME/.local/bin:$PATH"; uv tool install yt-dlp; uv tool install "agent-reach[all] @ https://github.com/Panniantong/agent-reach/archive/main.zip"'
runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" bash -lc \
  'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive'
runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" bash -lc \
  'export PATH="$HOME/.local/bin:$HOME/.hermes/node/bin:$PATH"; npm config set prefix "$HOME/.local"; npm install -g @earendil-works/pi-coding-agent @openai/codex cc-connect agent-browser'
curl -fsSL https://tailscale.com/install.sh | sh

cat > "$TARGET_HOME/.vnc/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
xrdb "$HOME/.Xresources" 2>/dev/null || true
exec dbus-launch --exit-with-session startxfce4
EOF
cat > "$TARGET_HOME/.config/remote-desktop/start-chrome.sh" <<'EOF'
#!/bin/sh
export DISPLAY=:1
export XAUTHORITY="$HOME/.Xauthority"
exec /usr/bin/google-chrome --display=:1 \
  --remote-debugging-address=127.0.0.1 --remote-debugging-port=9222 \
  --password-store=basic --user-data-dir="$HOME/.config/chrome-agent-profile" \
  --no-first-run --no-default-browser-check about:blank
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.vnc/xstartup" "$TARGET_HOME/.config/remote-desktop/start-chrome.sh"
chmod 700 "$TARGET_HOME/.vnc/xstartup" "$TARGET_HOME/.config/remote-desktop/start-chrome.sh"

if [ ! -f "$TARGET_HOME/.vnc/passwd" ]; then
  pw=$(openssl rand -hex 8)
  printf '%s' "$pw" | vncpasswd -f > "$TARGET_HOME/.vnc/passwd"
  printf '%s\n' "$pw" > "$TARGET_HOME/.config/remote-desktop/vnc-password.txt"
  chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.vnc/passwd" "$TARGET_HOME/.config/remote-desktop/vnc-password.txt"
  chmod 600 "$TARGET_HOME/.vnc/passwd" "$TARGET_HOME/.config/remote-desktop/vnc-password.txt"
fi

cat > /etc/systemd/system/agent-vnc.service <<EOF
[Unit]
Description=Private VNC desktop for the agent VM
After=network.target

[Service]
Type=forking
User=$TARGET_USER
Environment=HOME=$TARGET_HOME
ExecStart=/usr/bin/vncserver :1 -localhost yes -geometry 1440x900 -depth 24
ExecStop=/usr/sbin/runuser -u $TARGET_USER -- env HOME=$TARGET_HOME /usr/bin/vncserver -kill :1
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/agent-novnc.service <<EOF
[Unit]
Description=Loopback-only noVNC bridge
After=agent-vnc.service
Requires=agent-vnc.service

[Service]
ExecStart=/usr/bin/websockify --web=/usr/share/novnc --heartbeat=30 127.0.0.1:6080 127.0.0.1:5901
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/agent-chrome.service <<EOF
[Unit]
Description=Persistent Google Chrome for the agent
After=agent-vnc.service
Requires=agent-vnc.service

[Service]
User=$TARGET_USER
Environment=HOME=$TARGET_HOME
Environment=DISPLAY=:1
Environment=XAUTHORITY=$TARGET_HOME/.Xauthority
ExecStart=$TARGET_HOME/.config/remote-desktop/start-chrome.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now agent-vnc.service agent-novnc.service agent-chrome.service

if [ ! -f "$TARGET_HOME/.hermes/.env.example" ]; then
  cat > "$TARGET_HOME/.hermes/.env.example" <<'EOF'
# Copy to ~/.hermes/.env and replace placeholders.
TELEGRAM_BOT_TOKEN=1234567890:REPLACE_WITH_BOTFATHER_TOKEN
TELEGRAM_ALLOWED_USERS=REPLACE_WITH_TELEGRAM_USER_ID
EOF
  chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.hermes/.env.example"
  chmod 600 "$TARGET_HOME/.hermes/.env.example"
fi

cat <<EOF
VM setup complete.
Chrome profile: $TARGET_HOME/.config/chrome-agent-profile
VNC password:   $TARGET_HOME/.config/remote-desktop/vnc-password.txt
Next: sudo tailscale up
Then: sudo tailscale serve --bg 6080
EOF
