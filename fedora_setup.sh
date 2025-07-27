#!/bin/bash

set -euo pipefail

# ─────────────────────────────────────────────
# 🧩 Logging Helpers
# ─────────────────────────────────────────────
log()  { echo -e "\n\033[1;36m🔧 $1\033[0m"; }
info() { echo -e "\033[1;32m✅ $1\033[0m"; }
warn() { echo -e "\033[1;33m⚠️  $1\033[0m"; }

# ─────────────────────────────────────────────
# ⚙️ Improve DNF Configuration
# ─────────────────────────────────────────────
log "Optimizing DNF configuration..."
sudo tee -a /etc/dnf/dnf.conf >/dev/null <<EOF
deltarpm=true
max_parallel_downloads=10
EOF
info "DNF settings applied."

# ─────────────────────────────────────────────
# ⬆️ Upgrade All Packages
# ─────────────────────────────────────────────
log "Upgrading system packages..."
sudo dnf upgrade --refresh -y
info "System upgraded."

# ─────────────────────────────────────────────
# 🧰 Git Installation & Config
# ─────────────────────────────────────────────
log "Installing Git (if not present)..."
sudo dnf install -y git

log "Checking Git global config..."
GIT_NAME=$(git config --global user.name || echo "")
GIT_EMAIL=$(git config --global user.email || echo "")

if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" ]]; then
  read -rp "👤 Enter Git user.name: " input_name
  read -rp "📧 Enter Git user.email: " input_email
  git config --global user.name "$input_name"
  git config --global user.email "$input_email"
  info "Git configured."
else
  info "Git already configured: $GIT_NAME <$GIT_EMAIL>"
fi

# ─────────────────────────────────────────────
# 📦 Enable Flatpak & Install Chrome
# ─────────────────────────────────────────────
log "Installing Flatpak..."
sudo dnf install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
info "Flatpak ready."

log "Installing Chrome via Flatpak..."
flatpak install -y flathub com.google.Chrome
info "Chrome installed."

# ─────────────────────────────────────────────
# 🗑 Remove Firefox (if installed)
# ─────────────────────────────────────────────
log "Removing Firefox if installed..."
sudo dnf remove -y firefox || warn "Firefox not found."
info "Firefox cleanup done."

# ─────────────────────────────────────────────
# 🧹 Remove GNOME Bloat
# ─────────────────────────────────────────────
log "Removing pre-installed GNOME apps..."
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
info "GNOME apps debloated."

# ─────────────────────────────────────────────
# 🎨 GNOME Settings (No dbus-launch)
# ─────────────────────────────────────────────
log "Applying GNOME UI preferences..."

# Reuse current user and their session D-Bus
USER_NAME=$(logname)
USER_ENV=$(sudo -u "$USER_NAME" bash -c 'echo $DBUS_SESSION_BUS_ADDRESS')

if [[ -z "$USER_ENV" ]]; then
  warn "Could not detect user DBus session. Skipping GNOME settings."
else
  export DBUS_SESSION_BUS_ADDRESS="$USER_ENV"

  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true

  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-from 20.0

  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-to 20.0

  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.desktop.peripherals.touchpad click-method 'areas'

  info "GNOME settings applied."
fi

# ─────────────────────────────────────────────
# ✅ Done
# ─────────────────────────────────────────────
log "🎉 Fedora setup complete."
echo -e "💡 Tip: Restart your session or reboot to ensure all changes apply.\n"
