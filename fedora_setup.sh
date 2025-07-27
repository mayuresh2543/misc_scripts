#!/bin/bash

set -euo pipefail

# ─────────────────────────────────────────────────────
# 🎨 Logging functions
# ─────────────────────────────────────────────────────
log() {
  echo -e "\n\033[1;36m🔧 $1\033[0m"
}

info() {
  echo -e "\033[1;32m✅ $1\033[0m"
}

warn() {
  echo -e "\033[1;33m⚠️  $1\033[0m"
}

# ─────────────────────────────────────────────────────
# ⚙️ Improve DNF performance
# ─────────────────────────────────────────────────────
log "Optimizing DNF configuration..."
sudo tee -a /etc/dnf/dnf.conf >/dev/null <<EOF
deltarpm=true
max_parallel_downloads=10
EOF
info "DNF config tuned."

# ─────────────────────────────────────────────────────
# ⬆️ System update
# ─────────────────────────────────────────────────────
log "Refreshing and upgrading packages..."
sudo dnf upgrade --refresh -y
info "System updated."

# ─────────────────────────────────────────────────────
# 🧰 Install and configure Git
# ─────────────────────────────────────────────────────
log "Checking if Git is installed..."
if ! command -v git &>/dev/null; then
  log "Installing Git..."
  sudo dnf install -y git
  info "Git installed."
else
  info "Git already present."
fi

log "Checking Git user config..."
GIT_NAME=$(git config --global user.name || echo "")
GIT_EMAIL=$(git config --global user.email || echo "")

if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" ]]; then
  read -rp "🧑 Enter Git user.name: " input_name
  read -rp "📧 Enter Git user.email: " input_email
  git config --global user.name "$input_name"
  git config --global user.email "$input_email"
  info "Git configured."
else
  info "Git config found:"
  echo "  Name : $GIT_NAME"
  echo "  Email: $GIT_EMAIL"
fi

# ─────────────────────────────────────────────────────
# 📦 Enable Flatpak & install Chrome
# ─────────────────────────────────────────────────────
log "Installing Flatpak & adding Flathub..."
sudo dnf install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
info "Flatpak ready."

log "Installing Chrome via Flatpak..."
flatpak install -y flathub com.google.Chrome
info "Chrome installed."

# ─────────────────────────────────────────────────────
# 🗑 Remove Firefox if installed
# ─────────────────────────────────────────────────────
log "Removing Firefox (if installed)..."
sudo dnf remove -y firefox || warn "Firefox not installed."
info "Firefox removed (or wasn't installed)."

# ─────────────────────────────────────────────────────
# 🧹 Debloat GNOME apps
# ─────────────────────────────────────────────────────
log "Removing GNOME bloat apps..."
GNOME_BLOAT=(
  libreoffice*
  cheese
  yelp
  totem
  rhythmbox
  simple-scan
  gnome-contacts
  gnome-maps
  gnome-weather
  gnome-characters
)

for pkg in "${GNOME_BLOAT[@]}"; do
  if rpm -q "$pkg" &>/dev/null; then
    sudo dnf remove -y "$pkg"
    info "Removed: $pkg"
  else
    warn "Not installed: $pkg"
  fi
done
info "GNOME cleanup done."

# ─────────────────────────────────────────────────────
# 🎨 GNOME Settings (Night Light, Dark Mode, Touchpad)
# ─────────────────────────────────────────────────────
log "Applying GNOME settings..."

USER_NAME=$(logname)
USER_ENV=$(sudo -u "$USER_NAME" dbus-launch echo \$DBUS_SESSION_BUS_ADDRESS)
export DBUS_SESSION_BUS_ADDRESS=$(echo "$USER_ENV" | grep -o 'unix:.*')

# 🌙 Night Light: always on (20:00 to 20:00)
sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true

sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-from 20.0

sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-to 20.0

# 🖤 Enable dark mode
sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# 🖱 Enable touchpad right-click
sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  gsettings set org.gnome.desktop.peripherals.touchpad click-method 'areas'

info "GNOME settings applied."

# ─────────────────────────────────────────────────────
# ✅ Done
# ─────────────────────────────────────────────────────
log "🎉 Fedora setup is complete!"
echo -e "💡 You can reboot to ensure all settings are active.\n"
