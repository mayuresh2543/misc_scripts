#!/bin/bash

set -euo pipefail

# 📁 Log all output to terminal + log file
LOG_FILE="$HOME/fedora-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

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
# 🧩 Enable Third-Party Repositories
# ─────────────────────────────────────────────
enable_third_party_repos() {
  log "Enabling third-party repositories..."

  sudo dnf install -y fedora-workstation-repositories

  sudo dnf install -y \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

  info "Third-party repos and RPM Fusion enabled."
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
    GIT_NAME=$input_name
    GIT_EMAIL=$input_email
    info "Git configured."
  else
    info "Git already configured."
  fi
}

# ─────────────────────────────────────────────
# 📦 Enable Flatpak & Install Chrome + Extensions
# ─────────────────────────────────────────────
install_flatpak_and_chrome() {
  log "Setting up Flatpak and installing Chrome..."
  sudo dnf install -y flatpak
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak install -y flathub com.google.Chrome
  flatpak install -y flathub org.gnome.Extensions
  info "Chrome and GNOME Extensions installed."
}

# ─────────────────────────────────────────────
# 🗑️ Remove Firefox (Optional)
# ─────────────────────────────────────────────
remove_firefox() {
  log "Removing Firefox (if installed)..."
  sudo dnf remove -y firefox || warn "Firefox not installed."
  info "Firefox cleanup done."
}

# ─────────────────────────────────────────────
# 🧹 Remove GNOME Bloat Apps + LibreOffice
# ─────────────────────────────────────────────
debloat_gnome() {
  log "Removing GNOME bloat apps..."

  LIBRE_PKGS=$(rpm -qa | grep libreoffice || true)
  if [[ -n "$LIBRE_PKGS" ]]; then
    sudo dnf remove -y $LIBRE_PKGS
    info "Removed LibreOffice packages."
  else
    info "No LibreOffice packages found."
  fi

  local bloat_apps=(
    gnome-boxes cheese yelp totem rhythmbox
    simple-scan gnome-contacts gnome-maps
    gnome-weather gnome-characters
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
# 💠 Install and Enable Blur My Shell Extension
# ─────────────────────────────────────────────
install_blur_my_shell() {
  log "Installing 'Blur My Shell' GNOME extension..."

  TEMP_DIR=$(mktemp -d)
  git clone --depth=1 https://github.com/aunetx/blur-my-shell "$TEMP_DIR/blur-my-shell"
  cd "$TEMP_DIR/blur-my-shell"
  make install
  cd ~
  rm -rf "$TEMP_DIR"

  USER_NAME=$(logname)
  EXT_UUID="blur-my-shell@aunetx"
  sudo -u "$USER_NAME" gnome-extensions enable "$EXT_UUID" || warn "Could not enable Blur My Shell extension."

  info "'Blur My Shell' extension installed and enabled."
}

# ─────────────────────────────────────────────
# 🔒 Setup Firewall, Preload, DNS
# ─────────────────────────────────────────────
system_tweaks() {
  log "Installing preload and enabling service..."
  sudo dnf install -y preload
  sudo systemctl enable --now preload

  log "Enabling DNS caching with systemd-resolved..."
  sudo systemctl enable --now systemd-resolved

  log "Installing and configuring firewall (ufw)..."
  sudo dnf install -y ufw
  sudo systemctl enable --now ufw
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow ssh
  sudo ufw enable

  info "System performance and network optimizations applied."
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

  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-from 20.0
  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-to 20.0
  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 4000

  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.desktop.peripherals.touchpad click-method 'areas'
  sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"

  info "GNOME settings applied."
}

# ─────────────────────────────────────────────
# 🧾 Final Summary
# ─────────────────────────────────────────────
summary() {
  log "🎉 Fedora setup complete."

  echo -e "\n\033[1;35m📝 Summary of changes:\033[0m"
  echo -e "  \033[1;32m- 🔄  System updated and DNF optimized\033[0m"
  echo -e "  \033[1;32m- 🧩  Third-party repositories and RPM Fusion enabled\033[0m"
  echo -e "  \033[1;32m- 🔧  Git installed and configured:\033[0m"
  echo -e "      name : $GIT_NAME"
  echo -e "      email: $GIT_EMAIL"
  echo -e "  \033[1;32m- 🌐  Flatpak enabled, Chrome and GNOME Extensions installed\033[0m"
  echo -e "  \033[1;32m- 💠  Blur My Shell extension installed and enabled\033[0m"
  echo -e "  \033[1;31m- 🗑️   Firefox removed (if present)\033[0m"
  echo -e "  \033[1;31m- 🧹  GNOME apps and LibreOffice debloated\033[0m"
  echo -e "  \033[1;34m- 🎨  GNOME settings:\033[0m"
  echo -e "      • Dark mode enabled"
  echo -e "      • Night light 20:00 → 20:00 @ 4000K"
  echo -e "      • Touchpad right-click set to 'areas'"
  echo -e "      • Title bar buttons: minimize, maximize, close"
  echo -e "  \033[1;36m- 🚀  Preload, DNS caching, and UFW firewall configured\033[0m"
  echo
  echo -e "\033[1;36m📁 Log saved to: $LOG_FILE\033[0m"
}

# ─────────────────────────────────────────────
# 🚀 Run All Steps
# ─────────────────────────────────────────────
main() {
  optimize_dnf
  upgrade_system
  enable_third_party_repos
  setup_git
  install_flatpak_and_chrome
  remove_firefox
  debloat_gnome
  install_blur_my_shell
  apply_gnome_settings
  system_tweaks
  summary
}

main "$@"
