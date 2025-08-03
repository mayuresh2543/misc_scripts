#!/bin/bash

set -euo pipefail

# 📁 Log all output to terminal + log file
LOG_FILE="$(pwd)/distro-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ─────────────────────────────────────────────
# 🔧 Utilities
# ─────────────────────────────────────────────
log()  { echo -e "\n\033[1;36m🔧 $1\033[0m"; }
info() { echo -e "\033[1;32m✅ $1\033[0m"; }
warn() { echo -e "\033[1;33m⚠️  $1\033[0m"; }

detect_distro() {
  source /etc/os-release
  DISTRO=$ID
}

# ─────────────────────────────────────────────
# ⚙️ Optimize Package Manager
# ─────────────────────────────────────────────
optimize_package_manager() {
  case "$DISTRO" in
    fedora)
      log "Optimizing DNF configuration..."
      sudo tee -a /etc/dnf/dnf.conf >/dev/null <<EOF
deltarpm=true
max_parallel_downloads=10
EOF
      ;;
    arch | manjaro)
      log "Optimizing Pacman configuration..."
      sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
      ;;
    ubuntu | debian)
      log "Optimizing APT configuration..."
      echo 'Acquire::Queue-Mode "access";' | sudo tee /etc/apt/apt.conf.d/99parallel
      ;;
    opensuse*)
      log "Optimizing Zypper configuration..."
      sudo sed -i 's/^# *parallel-downloads *=.*/parallel-downloads=10/' /etc/zypp/zypp.conf
      ;;
    *) warn "Package manager optimization not supported for $DISTRO." ;;
  esac
  info "Package manager settings applied."
}

# ─────────────────────────────────────────────
# ⬆️ Upgrade Packages
# ─────────────────────────────────────────────
upgrade_system() {
  log "Upgrading system packages..."
  case "$DISTRO" in
    fedora) sudo dnf upgrade --refresh -y ;;
    arch | manjaro) sudo pacman -Syu --noconfirm ;;
    ubuntu | debian) sudo apt update && sudo apt upgrade -y ;;
    opensuse*) sudo zypper refresh && sudo zypper update -y ;;
    *) warn "System upgrade not supported for $DISTRO." ;;
  esac
  info "System upgraded."
}

# ─────────────────────────────────────────────
# 🧩 Enable Third-Party Repositories
# ─────────────────────────────────────────────
enable_third_party_repos() {
  [[ "$DISTRO" != "fedora" ]] && return

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
  log "Installing Git and dev tools..."
  case "$DISTRO" in
    fedora)
      sudo dnf install -y git git-lfs repo pahole libxcrypt-compat openssl openssl-devel kernel-devel make
      ;;
    arch | manjaro)
      sudo pacman -S --noconfirm git git-lfs repo pahole openssl make
      ;;
    ubuntu | debian)
      sudo apt install -y git git-lfs repo pahole libssl-dev make
      ;;
    opensuse*)
      sudo zypper install -y git git-lfs repo pahole libopenssl-devel make
      ;;
  esac

  log "Checking Git global config..."
  GIT_NAME=$(git config --global user.name || echo "")
  GIT_EMAIL=$(git config --global user.email || echo "")
  GIT_GERRIT=$(git config --global review.review.lineageos.org.username || echo "")

  if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" ]]; then
    read -rp "👤 Enter Git user.name: " input_name
    read -rp "📧 Enter Git user.email: " input_email
    git config --global user.name "$input_name"
    git config --global user.email "$input_email"
    GIT_NAME=$input_name
    GIT_EMAIL=$input_email
  fi

  if [[ -z "$GIT_GERRIT" ]]; then
    read -rp "🔑 Enter your LineageOS Gerrit username: " input_gerrit
    git config --global review.review.lineageos.org.username "$input_gerrit"
  fi

  info "Git configured."
}

# ─────────────────────────────────────────────
# 📦 Enable Flatpak & Install Chrome + Extensions
# ─────────────────────────────────────────────
install_flatpak_apps() {
  log "Installing Flatpak and apps..."
  case "$DISTRO" in
    fedora) sudo dnf install -y flatpak ;;
    arch | manjaro) sudo pacman -S --noconfirm flatpak ;;
    ubuntu | debian) sudo apt install -y flatpak ;;
    opensuse*) sudo zypper install -y flatpak ;;
  esac

  sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak install -y flathub com.google.Chrome org.gnome.Extensions
  info "Flatpak apps installed."
}

# ─────────────────────────────────────────────
# 🗑️ Remove Firefox (Optional)
# ─────────────────────────────────────────────
remove_firefox() {
  log "Removing Firefox..."
  case "$DISTRO" in
    fedora) sudo dnf remove -y firefox || true ;;
    arch | manjaro) sudo pacman -Rns --noconfirm firefox || true ;;
    ubuntu | debian) sudo apt remove -y firefox || true ;;
    opensuse*) sudo zypper rm -y firefox || true ;;
  esac
  info "Firefox removed."
}

# ─────────────────────────────────────────────
# 🧹 Remove GNOME Bloat Apps + LibreOffice
# ─────────────────────────────────────────────
debloat_gnome() {
  log "Removing GNOME bloat apps..."

  LIBRE_PKGS=$(rpm -qa | grep libreoffice || true)
  [[ -n "$LIBRE_PKGS" ]] && sudo dnf remove -y $LIBRE_PKGS

  local bloat_apps=(
    gnome-boxes cheese yelp totem rhythmbox simple-scan
    gnome-contacts gnome-maps gnome-weather gnome-characters
  )

  for pkg in "${bloat_apps[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
      sudo dnf remove -y "$pkg"
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
# 🎨 GNOME User Settings + Shortcuts
# ─────────────────────────────────────────────
apply_gnome_settings() {
  log "Applying GNOME UI preferences..."
  USER_NAME=$(logname)

  # Dark Mode, Night Light, Touchpad, Buttons
  sudo -u "$USER_NAME" gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
  sudo -u "$USER_NAME" gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-from 20.0
  sudo -u "$USER_NAME" gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-to 20.0
  sudo -u "$USER_NAME" gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 4000
  sudo -u "$USER_NAME" gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  sudo -u "$USER_NAME" gsettings set org.gnome.desktop.peripherals.touchpad click-method 'areas'
  sudo -u "$USER_NAME" gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"

  # Super+E → Nautilus
  sudo -u "$USER_NAME" gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
    "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']"

  sudo -u "$USER_NAME" gsettings set \
    org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ \
    name 'Open Files'
  sudo -u "$USER_NAME" gsettings set \
    org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ \
    command 'nautilus'
  sudo -u "$USER_NAME" gsettings set \
    org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ \
    binding '<Super>e'

  info "GNOME settings applied."
}

# ─────────────────────────────────────────────
# 🔒 Setup Firewall
# ─────────────────────────────────────────────
setup_firewall() {
  log "Setting up firewall..."
  if command -v firewall-cmd &>/dev/null; then
    sudo systemctl enable --now firewalld
    sudo firewall-cmd --set-default-zone=public
    sudo firewall-cmd --reload
    info "Firewall configured."
  else
    warn "firewalld not installed or not supported."
  fi
}

# ─────────────────────────────────────────────
# 🧪 Optional: Dev Setup (Fedora Only)
# ─────────────────────────────────────────────
custom_kernel_and_zram() {
  log "Applying Fedora development tweaks (CachyOS kernel, ZRAM)..."

  sudo dnf copr enable -y bieszczaders/kernel-cachyos-lto
  sudo dnf install -y kernel-cachyos-lto kernel-cachyos-lto-devel-matched

  sudo setsebool -P domain_kernel_load_modules on

  sudo dnf copr enable -y bieszczaders/kernel-cachyos-addons
  sudo dnf install -y cachyos-settings --allowerasing
  sudo dracut -f

  ZRAM_CONF="/usr/lib/systemd/zram-generator.conf"
  if [[ -f "$ZRAM_CONF" ]]; then
    sudo sed -i 's/^zram-size *=.*/zram-size = ram*3.3/' "$ZRAM_CONF"
    info "ZRAM config updated to use ram*3.3"
  else
    warn "ZRAM config not found."
  fi
}

# ─────────────────────────────────────────────
# 🛡 Optional: Legacy Crypto Policies (Fedora Only)
# ─────────────────────────────────────────────
set_legacy_crypto_policy() {
  log "Configuring legacy crypto policies..."

  sudo update-crypto-policies --set LEGACY
  info "Crypto policies set to LEGACY."
}

# ─────────────────────────────────────────────
# 🧾 Final Summary
# ─────────────────────────────────────────────
summary() {
  log "🎉 Setup complete."

  echo -e "\n\033[1;35m📝 Summary of changes:\033[0m"
  echo -e "  \033[1;32m- 🔄  System updated and package manager optimized\033[0m"
  echo -e "  \033[1;32m- 🧩  Third-party repositories (if supported) enabled\033[0m"
  echo -e "  \033[1;32m- 🔧  Git installed and configured:\033[0m"
  echo -e "        • name : $GIT_NAME"
  echo -e "        • email: $GIT_EMAIL"
  echo -e "        • Gerrit: $GIT_GERRIT"
  echo -e "  \033[1;32m- 🌐  Flatpak apps installed (Chrome, Extensions)\033[0m"
  echo -e "  \033[1;32m- 💠  'Blur My Shell' extension installed and enabled\033[0m"
  echo -e "  \033[1;31m- 🗑️   Firefox removed (if present)\033[0m"
  echo -e "  \033[1;31m- 🧹  GNOME apps and LibreOffice debloated\033[0m"
  echo -e "  \033[1;34m- 🎨  GNOME settings:\033[0m"
  echo -e "        • Dark mode enabled"
  echo -e "        • Night light 20:00 → 20:00 @ 4000K"
  echo -e "        • Touchpad right-click set to 'areas'"
  echo -e "        • Title bar buttons: minimize, maximize, close"
  echo -e "        • Custom shortcut: Super+E → Files"
  echo -e "  \033[1;34m- 🔒  Firewall configured and enabled\033[0m"

  if [[ "$DISTRO" == "fedora" && "${dev_setup,,}" == "y" ]]; then
    echo -e "  \033[1;35m- ⚙️  Fedora dev setup applied:\033[0m"
    echo -e "        • CachyOS LTO kernel and matching headers installed"
    echo -e "        • SELinux: domain_kernel_load_modules enabled"
    echo -e "        • CachyOS performance tweaks installed"
    echo -e "        • ZRAM size configured to ram*3.3"
  fi

  if [[ "$DISTRO" == "fedora" && "${crypto_legacy,,}" == "y" ]]; then
    echo -e "  \033[1;35m- 🔐  Crypto policy set to LEGACY\033[0m"
  fi

  echo -e "\n\033[1;36m📁 Log saved to: $LOG_FILE\033[0m"
}

# ─────────────────────────────────────────────
# 🚀 Run Everything
# ─────────────────────────────────────────────
main() {
  detect_distro
  optimize_package_manager
  upgrade_system
  enable_third_party_repos
  setup_git
  install_flatpak_apps
  remove_firefox
  debloat_gnome
  install_blur_my_shell
  apply_gnome_settings
  setup_firewall

  if [[ "$DISTRO" == "fedora" ]]; then
    read -rp $'\n💬 Do you want to set up your distro for development tasks?\n(This includes CachyOS kernel, ZRAM tweaks, SELinux module loading, etc.) [y/N]: ' dev_setup
    if [[ "${dev_setup,,}" == "y" ]]; then
      custom_kernel_and_zram
    fi

    read -rp $'\n💬 Do you want to set legacy crypto policies? (Not recommended, reverts crypto to older settings) [y/N]: ' crypto_legacy
    if [[ "${crypto_legacy,,}" == "y" ]]; then
      set_legacy_crypto_policy
    fi
  fi

  summary
}

main "$@"
