#!/bin/bash

set -euo pipefail
trap 'echo "❌ Error on line $LINENO. Exiting."' ERR

GREEN="\033[0;32m"
NC="\033[0m"

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

configure_dnf() {
    log "Configuring DNF optimizations..."
    sudo cp /etc/dnf/dnf.conf /etc/dnf/dnf.conf.bak

    sudo sed -i '/^deltarpm/d' /etc/dnf/dnf.conf
    sudo sed -i '/^max_parallel_downloads/d' /etc/dnf/dnf.conf

    echo "deltarpm=true" | sudo tee -a /etc/dnf/dnf.conf
    echo "max_parallel_downloads=10" | sudo tee -a /etc/dnf/dnf.conf
}

upgrade_system() {
    log "Installing available system updates..."
    sudo dnf upgrade -y
}

install_git() {
    log "Installing Git..."
    sudo dnf install -y git
}

configure_git() {
    log "Configuring Git user info..."
    read -rp "Enter your Git email: " git_email
    read -rp "Enter your Git name: " git_name

    if [[ -z "$git_email" || -z "$git_name" ]]; then
        echo "❌ Git email or name cannot be empty. Aborting Git config."
        return
    fi

    git config --global user.email "$git_email"
    git config --global user.name "$git_name"
}

enable_flatpak() {
    log "Enabling Flatpak support..."
    sudo dnf install -y flatpak
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}

install_chrome_flatpak() {
    log "Installing Google Chrome via Flatpak..."
    flatpak install -y flathub com.google.Chrome
}

remove_firefox() {
    log "Removing Firefox if installed..."
    if rpm -q firefox &>/dev/null; then
        sudo dnf remove -y firefox
    else
        echo "Firefox not installed, skipping."
    fi
}

remove_gnome_bloat() {
    log "Removing GNOME bloatware..."
    BLOAT_PACKAGES=(
        cheese
        gnome-contacts
        gnome-maps
        gnome-weather
        gnome-tour
        gnome-clocks
        gnome-calendar
        yelp
        totem
        rhythmbox
        simple-scan
        evince
        gnome-characters
        gnome-font-viewer
    )

    for pkg in "${BLOAT_PACKAGES[@]}"; do
        if rpm -q "$pkg" &>/dev/null; then
            echo "Removing $pkg..."
            sudo dnf remove -y "$pkg"
        else
            echo "$pkg already removed, skipping."
        fi
    done

    log "Removing LibreOffice apps..."
    libre_pkgs=$(rpm -qa | grep ^libreoffice || true)
    if [[ -n "$libre_pkgs" ]]; then
        sudo dnf remove -y libreoffice*
    else
        echo "LibreOffice not installed, skipping."
    fi
}

apply_gnome_settings() {
    log "Applying GNOME UI preferences (dark mode, night light)..."

    USER_NAME="$(logname)"
    DBUS_ADDRESS="/run/user/$(id -u "$USER_NAME")/bus"

    if [[ ! -e "$DBUS_ADDRESS" ]]; then
        echo "❌ Could not access DBus session for user $USER_NAME. Skipping GNOME settings."
        return
    fi

    export DBUS_SESSION_BUS_ADDRESS="unix:path=$DBUS_ADDRESS"

    # Enable dark mode
    sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

    # Enable night light from 20:00 to 20:00 (always on)
    sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
        gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true

    sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
        gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-automatic false

    sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
        gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-from 20.0

    sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
        gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-to 20.0

    log "✅ GNOME settings updated. You can manually enable 125% scaling in Settings → Display."
}

main() {
    configure_dnf
    upgrade_system
    install_git
    configure_git
    enable_flatpak
    install_chrome_flatpak
    remove_firefox
    remove_gnome_bloat
    apply_gnome_settings
    log "🎉 All tasks completed successfully!"
}

main
