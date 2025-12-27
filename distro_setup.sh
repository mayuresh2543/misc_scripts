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

detect_de() {
  if [[ "${XDG_CURRENT_DESKTOP-}" =~ "GNOME" ]]; then
    DE="gnome"
  elif [[ "${XDG_CURRENT_DESKTOP-}" =~ "KDE" ]]; then
    DE="kde"
  else
    DE="other"
  fi
}

# ─────────────────────────────────────────────
# ⚙️ Optimize Package Manager
# ─────────────────────────────────────────────
optimize_package_manager() {
  case "$DISTRO" in
    fedora)
      log "Optimizing DNF configuration..."
      # Check if already exists to avoid duplicates
      if ! grep -q "max_parallel_downloads" /etc/dnf/dnf.conf; then
        echo "max_parallel_downloads=10" | sudo tee -a /etc/dnf/dnf.conf
      fi
      # Deltarpm is deprecated in newer Fedora/DNF5, only add if DNF4
      if rpm -q dnf | grep -qE "dnf-4" && ! grep -q "deltarpm" /etc/dnf/dnf.conf; then
         echo "deltarpm=true" | sudo tee -a /etc/dnf/dnf.conf
      fi
      ;;
    arch | manjaro | cachyos)
      log "Optimizing Pacman configuration..."
      # Enable Parallel Downloads and Color
      sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
      sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
      # Add ILoveCandy if not present
      if ! grep -q "ILoveCandy" /etc/pacman.conf; then
          sudo sed -i '/Color/a ILoveCandy' /etc/pacman.conf
      fi
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
    arch | manjaro | cachyos)
      # Arch keyring update is critical before system upgrade
      sudo pacman -Sy --noconfirm archlinux-keyring
      sudo pacman -Su --noconfirm
      ;;
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
      sudo dnf install -y git git-lfs repo pahole libxcrypt-compat openssl openssl-devel make
      ;;
    arch | manjaro | cachyos)
      sudo pacman -S --noconfirm git git-lfs repo pahole openssl make base-devel
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

  # Force input from TTY to handle pipe execution
  if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" ]]; then
    read -rp "👤 Enter Git user.name: " input_name < /dev/tty
    read -rp "📧 Enter Git user.email: " input_email < /dev/tty
    git config --global user.name "$input_name"
    git config --global user.email "$input_email"
    GIT_NAME=$input_name
    GIT_EMAIL=$input_email
  fi

  if [[ -z "$GIT_GERRIT" ]]; then
    read -rp "🔑 Enter your LineageOS Gerrit username: " input_gerrit < /dev/tty
    git config --global review.review.lineageos.org.username "$input_gerrit"
    GIT_GERRIT=$input_gerrit
  fi

  info "Git configured."
}

# ─────────────────────────────────────────────
# 💻 Install VS Code (Fedora & Arch)
# ─────────────────────────────────────────────
install_vscode() {
  log "Installing Visual Studio Code..."
  case "$DISTRO" in
    fedora)
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
        sudo dnf install -y code
        info "Visual Studio Code installed."
        ;;
    arch | manjaro | cachyos)
        # Installs 'Code - OSS' from official repos
        sudo pacman -S --noconfirm code
        info "Visual Studio Code (OSS) installed."
        ;;
    *)
        warn "VS Code install not configured for $DISTRO in this script."
        ;;
  esac
}

# ─────────────────────────────────────────────
# 📦 Enable Flatpak & Install Chrome + Extensions
# ─────────────────────────────────────────────
install_flatpak_apps() {
  log "Installing Flatpak and apps..."
  case "$DISTRO" in
    fedora) sudo dnf install -y flatpak ;;
    arch | manjaro | cachyos) sudo pacman -S --noconfirm flatpak ;;
    ubuntu | debian) sudo apt install -y flatpak ;;
    opensuse*) sudo zypper install -y flatpak ;;
  esac

  sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak install -y flathub com.google.Chrome

  if [[ "$DE" == "gnome" ]]; then
    flatpak install -y flathub org.gnome.Extensions
  fi

  info "Flatpak apps installed."
}

# ─────────────────────────────────────────────
# 🗑️ Remove Firefox (Optional)
# ─────────────────────────────────────────────
remove_firefox() {
  log "Removing Firefox..."
  case "$DISTRO" in
    fedora) sudo dnf remove -y firefox || true ;;
    arch | manjaro | cachyos) sudo pacman -Rns --noconfirm firefox || true ;;
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

  case "$DISTRO" in
      fedora)
          LIBRE_PKGS=$(rpm -qa | grep libreoffice || true)
          [[ -n "$LIBRE_PKGS" ]] && sudo dnf remove -y $LIBRE_PKGS
          local bloat_apps=(gnome-boxes cheese yelp totem rhythmbox simple-scan gnome-contacts gnome-maps gnome-weather gnome-characters)
          for pkg in "${bloat_apps[@]}"; do
             rpm -q "$pkg" &>/dev/null && sudo dnf remove -y "$pkg"
          done
          ;;
      arch | manjaro | cachyos)
          # Arch specific package names
          sudo pacman -Rns --noconfirm libreoffice-fresh libreoffice-still || true
          local bloat_apps=(gnome-boxes cheese yelp totem rhythmbox simple-scan gnome-contacts gnome-maps gnome-weather gnome-characters epiphany gnome-tour)
          for pkg in "${bloat_apps[@]}"; do
             if pacman -Qi "$pkg" &>/dev/null; then
                 sudo pacman -Rns --noconfirm "$pkg"
             fi
          done
          ;;
  esac

  info "GNOME apps debloated."
}

# ─────────────────────────────────────────────
# 💠 Install and Enable Blur My Shell Extension
# ─────────────────────────────────────────────
install_blur_my_shell() {
  log "Installing 'Blur My Shell' GNOME extension..."

  # Ensure build deps
  if [[ "$DISTRO" == "arch" || "$DISTRO" == "manjaro" ]]; then
      sudo pacman -S --noconfirm git make gettext glib2 npm
  elif [[ "$DISTRO" == "fedora" ]]; then
      sudo dnf install -y git make gettext glib2-devel npm
  fi

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
# 🐲 KDE Plasma Settings
# ─────────────────────────────────────────────
apply_kde_settings() {
  log "Applying KDE Plasma preferences..."
  USER_NAME=$(logname)

  # Dark Mode
  if command -v plasma-apply-lookandfeel &>/dev/null; then
      sudo -u "$USER_NAME" plasma-apply-lookandfeel -a org.kde.breezedark.desktop 2>/dev/null
  elif command -v lookandfeeltool &>/dev/null; then
      sudo -u "$USER_NAME" lookandfeeltool -a org.kde.breezedark.desktop 2>/dev/null
  fi

  # Config Tool
  if command -v kwriteconfig6 &>/dev/null; then
      KWRITE="kwriteconfig6"
  else
      KWRITE="kwriteconfig5"
  fi

  if command -v $KWRITE &>/dev/null; then
      # Scaling 125%
      sudo -u "$USER_NAME" $KWRITE --file kdeglobals --group KScreen --key ScaleFactor 1.25 2>/dev/null

      # Night Light: Always On, 4000K
      sudo -u "$USER_NAME" $KWRITE --file kwinrc --group NightColor --key Active true 2>/dev/null
      sudo -u "$USER_NAME" $KWRITE --file kwinrc --group NightColor --key Mode Constant 2>/dev/null
      sudo -u "$USER_NAME" $KWRITE --file kwinrc --group NightColor --key NightTemperature 4000 2>/dev/null
  fi

  info "KDE settings applied."
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
# ⚙️ Cachy Kernel (Fedora & Arch)
# ─────────────────────────────────────────────
install_cachy_kernel() {
  if [[ "$DISTRO" == "fedora" ]]; then
      log "Installing CachyOS LTO kernel for Fedora..."
      sudo dnf copr enable -y bieszczaders/kernel-cachyos-lto
      sudo dnf install -y kernel-cachyos-lto kernel-cachyos-lto-devel-matched
      sudo setsebool -P domain_kernel_load_modules on
      sudo dnf copr enable -y bieszczaders/kernel-cachyos-addons
      sudo dnf install -y cachyos-settings --allowerasing
      sudo dracut -f
      info "CachyOS kernel installed (Fedora)."

  elif [[ "$DISTRO" == "arch" ]]; then
      log "Installing CachyOS kernel for Arch..."
      # 1. Receive keys
      sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
      sudo pacman-key --lsign-key F3B607488DB35A47

      # 2. Add repo to pacman.conf if not exists
      if ! grep -q "cachyos-v3" /etc/pacman.conf; then
          # Basic repo addition (assuming x86-64-v3 or higher support)
          echo -e "\n[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist" | sudo tee -a /etc/pacman.conf
      fi

      # 3. Install keyring and mirrorlist
      sudo pacman -U --noconfirm 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' \
                                 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-18-1-any.pkg.tar.zst'

      # 4. Update and install kernel
      sudo pacman -Sy --noconfirm
      sudo pacman -S --noconfirm linux-cachyos linux-cachyos-headers
      info "CachyOS kernel installed (Arch)."
  fi
}

# ─────────────────────────────────────────────
# 🧠 ZRAM Tweaks (Fedora & Arch)
# ─────────────────────────────────────────────
configure_zram() {
  log "Configuring ZRAM..."

  # Arch needs package installed first
  if [[ "$DISTRO" == "arch" || "$DISTRO" == "manjaro" ]]; then
      sudo pacman -S --noconfirm zram-generator
  fi

  ZRAM_CONF="/usr/lib/systemd/zram-generator.conf"
  # Fallback to /etc if /usr/lib is managed strictly
  if [[ ! -d "/usr/lib/systemd" ]]; then ZRAM_CONF="/etc/systemd/zram-generator.conf"; fi

  read -rp $'\n💬 Enter ZRAM multiplier (e.g., 3.3 for ram*3.3) [default: 3.3]: ' zram_multiplier < /dev/tty
  zram_multiplier=${zram_multiplier:-3.3}

  # Create config if it doesn't exist
  if [[ ! -f "$ZRAM_CONF" ]]; then
      sudo mkdir -p "$(dirname "$ZRAM_CONF")"
      sudo touch "$ZRAM_CONF"
      echo "[zram0]" | sudo tee "$ZRAM_CONF"
      echo "zram-size = ram*${zram_multiplier}" | sudo tee -a "$ZRAM_CONF"
      echo "compression-algorithm = zstd" | sudo tee -a "$ZRAM_CONF"
  else
      # Update existing
      sudo sed -i "s/^zram-size *=.*/zram-size = ram*${zram_multiplier}/" "$ZRAM_CONF"
  fi

  # Reload systemd
  sudo systemctl daemon-reload
  sudo systemctl start systemd-zram-setup@zram0.service

  info "ZRAM configured to ram*${zram_multiplier}"
}

# ─────────────────────────────────────────────
# 🛡 Optional: Legacy Crypto Policies (Fedora Only)
# ─────────────────────────────────────────────
set_legacy_crypto_policy() {
  [[ "$DISTRO" != "fedora" ]] && return
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

  if [[ "$DISTRO" == "fedora" || "$DISTRO" == "arch" ]]; then
     echo -e "  \033[1;32m- 💻  Visual Studio Code installed\033[0m"
  fi

  echo -e "  \033[1;32m- 🌐  Flatpak apps installed (Chrome, Extensions)\033[0m"

  if [[ "$DE" == "gnome" ]]; then
      echo -e "  \033[1;32m- 💠  'Blur My Shell' extension installed and enabled\033[0m"
      echo -e "  \033[1;31m- 🗑️   Firefox removed (if present)\033[0m"
      echo -e "  \033[1;31m- 🧹  GNOME apps and LibreOffice debloated\033[0m"
      echo -e "  \033[1;34m- 🎨  GNOME settings applied (Dark mode, Night light, etc.)\033[0m"
  elif [[ "$DE" == "kde" ]]; then
      echo -e "  \033[1;31m- 🗑️   Firefox removed (if present)\033[0m"
      echo -e "  \033[1;34m- 🐲  KDE settings applied (Dark mode, Scaling, Night Light)\033[0m"
  fi

  echo -e "  \033[1;34m- 🔒  Firewall configured and enabled\033[0m"

  if [[ "$CACHY_KERNEL_APPLIED" == true ]]; then
    echo -e "  \033[1;35m- ⚙️   CachyOS kernel installed\033[0m"
  fi
  if [[ "$ZRAM_CONFIGURED" == true ]]; then
    echo -e "  \033[1;35m- 🧠  ZRAM configured\033[0m"
  fi
  if [[ "$LEGACY_CRYPTO_SET" == true ]]; then
    echo -e "  \033[1;35m- 🛡   Legacy crypto policy applied\033[0m"
  fi

  echo -e "\n\033[1;36m📁 Log saved to: $LOG_FILE\033[0m"
}

# ─────────────────────────────────────────────
# 🚪 Logout Prompt (Safe Version)
# ─────────────────────────────────────────────
ask_to_logout() {
  # Only needed for KDE scaling changes
  [[ "$DE" != "kde" ]] && return

  USER_NAME=$(logname)
  echo -e "\n\033[1;33m⚠️  Some changes (like scaling and UI themes) require a logout to fully apply.\033[0m"
  read -rp "💬 Do you want to log out now? [y/N]: " choice < /dev/tty
  if [[ "${choice,,}" == "y" ]]; then
      log "Attempting graceful logout..."
      if command -v qdbus6 &>/dev/null; then
          sudo -u "$USER_NAME" qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null
      elif command -v qdbus-qt6 &>/dev/null; then
          sudo -u "$USER_NAME" qdbus-qt6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null
      elif command -v qdbus &>/dev/null; then
          if ! sudo -u "$USER_NAME" qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null; then
               sudo -u "$USER_NAME" qdbus org.kde.ksmserver /KSMServer logout 0 0 0 2>/dev/null
          fi
      elif command -v dbus-send &>/dev/null; then
          if ! sudo -u "$USER_NAME" dbus-send --session --dest=org.kde.Shutdown --type=method_call /Shutdown org.kde.Shutdown.logout 2>/dev/null; then
               sudo -u "$USER_NAME" dbus-send --session --dest=org.kde.ksmserver --type=method_call /KSMServer org.kde.KSMServerInterface.logout int32:0 int32:0 int32:0 2>/dev/null
          fi
      else
          warn "Could not find KDE logout tool. Please log out manually."
      fi
  else
      log "Please remember to log out manually for all changes to take effect."
  fi
}

# ─────────────────────────────────────────────
# 🚀 Run Everything
# ─────────────────────────────────────────────
main() {
  detect_distro
  detect_de
  optimize_package_manager
  upgrade_system
  enable_third_party_repos
  setup_git
  install_vscode
  install_flatpak_apps
  remove_firefox

  if [[ "$DE" == "gnome" ]]; then
    debloat_gnome
    install_blur_my_shell
    apply_gnome_settings
  elif [[ "$DE" == "kde" ]]; then
    apply_kde_settings
  fi

  setup_firewall

  CACHY_KERNEL_APPLIED=false
  ZRAM_CONFIGURED=false
  LEGACY_CRYPTO_SET=false

  # FEDORA Specific Questions
  if [[ "$DISTRO" == "fedora" ]]; then
    read -rp $'\n💬 Do you want to install the CachyOS kernel? [y/N]: ' install_kernel < /dev/tty
    if [[ "${install_kernel,,}" == "y" ]]; then
      install_cachy_kernel
      CACHY_KERNEL_APPLIED=true
    fi

    read -rp $'\n💬 Do you want to configure ZRAM? [y/N]: ' configure_zram_choice < /dev/tty
    if [[ "${configure_zram_choice,,}" == "y" ]]; then
      configure_zram
      ZRAM_CONFIGURED=true
    fi

    read -rp $'\n💬 Do you want to set legacy crypto policies? (Not recommended) [y/N]: ' crypto_legacy < /dev/tty
    if [[ "${crypto_legacy,,}" == "y" ]]; then
      set_legacy_crypto_policy
      LEGACY_CRYPTO_SET=true
    fi

  # ARCH Specific Questions
  elif [[ "$DISTRO" == "arch" ]]; then
    read -rp $'\n💬 Do you want to install the CachyOS kernel? [y/N]: ' install_kernel < /dev/tty
    if [[ "${install_kernel,,}" == "y" ]]; then
      install_cachy_kernel
      CACHY_KERNEL_APPLIED=true
    fi

    read -rp $'\n💬 Do you want to configure ZRAM? [y/N]: ' configure_zram_choice < /dev/tty
    if [[ "${configure_zram_choice,,}" == "y" ]]; then
      configure_zram
      ZRAM_CONFIGURED=true
    fi
  fi

  summary
  ask_to_logout
}

main "$@"
