#!/bin/bash

set -euo pipefail

# ─────────────────────────────────────────────
# 🔧 Utilities
# ─────────────────────────────────────────────
log()  { echo -e "\n\033[1;36m🔧 $1\033[0m"; }
info() { echo -e "\033[1;32m✅ $1\033[0m"; }
warn() { echo -e "\033[1;33m⚠️  $1\033[0m"; }

# ─────────────────────────────────────────────
# ⚙️ Optimize DNF Configuration
# ─────────────────────────────────────────────
optimize_dnf() {
  log "Optimizing DNF configuration..."
  sudo tee -a /etc/dnf/dnf.conf >/dev/null <<EOF
deltarpm=true
max_parallel_downloads=10
EOF
  info "DNF settings applied."
}

# ─────────────────────────────────────────────
# ⬆️ Upgrade Packages
# ─────────────────────────────────────────────
upgrade_system() {
  log "Upgrading system packages..."
  sudo dnf upgrade --refresh -y
  info "System upgraded."
}

# ─────────────────────────────────────────────
# 🧰 Install & Configure Git
# ─────────────────────────────────────────────
setup_git() {
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
}

# ─────────────────────────────────────────────
# 📦 Enable Flatpak & Install Chrome
# ─────────────────────────────────────────────
install_flatpak_and_chrome() {
  log "Setting up Flatpak and installing Chrome..."
  sudo dnf install -y flatpak
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak install -y flathub com.google.Chrome
  info "Chrome installed."
}

# ─────────────────────────────────────────────
# 🗑 Remove Firefox (Optional)
# ─────────────────────────────────────────────
remove_firefox() {
  log "Removing Firefox (if installed)..."
  sudo dnf remove -y firefox || warn "Firefox not installed."
  info "Firefox cleanup done."
}

# ─────────────────────────────────────────────
# 🧹 Remove GNOME Bloat Apps
# ─────────────────────────────────────────────
debloat_gnome() {
  log "Removing GNOME bloat apps..."
  local bloat_apps=(
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

  for pkg in "${bloat_apps[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
      sudo dnf remove -y "$pkg"
      info "Removed: $pkg"
    else
      warn "Not installed: $pkg"
    fi
  done
  info "GNOME apps debloated."
}

# ─────────────────────────────────────────────
# 🎨 GNOME User Settings
# ─────────────────────────────────────────────
apply_gnome_settings() {
  log "Applying GNOME UI preferences..."
  USER_NAME=$(logname)
  USER_ENV=$(sudo -u "$USER_NAME" bash -c 'echo $DBUS_SESSION_BUS_ADDRESS')

  if [[ -z "$USER_ENV" ]]; then
    warn "Could not detect user DBus session. Skipping GNOME settings."
    return
  fi

  export DBUS_SESSION_BUS_ADDRESS="$USER_ENV"

  # 🌙 Enable Night Light and schedule
  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-from 20.0
  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-to 20.0
  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 4000

  # 🕶️ Dark mode
  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

  # 🖱️ Enable trackpad right-click (areas)
  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.desktop.peripherals.touchpad click-method 'areas'

  # 🔇 Disable Bluetooth
  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.system.rfkill bluetooth 'true'

  info "GNOME settings applied."
}

# ─────────────────────────────────────────────
# 🧾 Final Summary
# ─────────────────────────────────────────────
summary() {
  log "🎉 Fedora setup complete."

  echo -e "\n\033[1;35m📝 Summary of changes:\033[0m"
  echo " - 🔄 System updated and DNF optimized"
  echo " - 🔧 Git installed and configured"
  echo " - 🌐 Flatpak enabled and Chrome installed"
  echo " - 🗑️ Firefox removed (if present)"
  echo " - 🚫 GNOME bloat apps removed"
  echo " - 🌙 Night Light enabled (4000K, 20:00–20:00)"
  echo " - 🕶️ Dark mode enabled"
  echo " - 🖱️ Trackpad right-click set to 'areas'"
  echo " - 🔇 Bluetooth disabled (like GNOME GUI toggle)"

  echo -e "\n\033[1;34m💡 Tip: Restart your session or reboot to ensure all changes take full effect.\033[0m\n"
}

# ─────────────────────────────────────────────
# 🚀 Run Everything
# ─────────────────────────────────────────────
optimize_dnf
upgrade_system
setup_git
install_flatpak_and_chrome
remove_firefox
debloat_gnome
apply_gnome_settings
summary
