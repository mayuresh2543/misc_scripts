#!/bin/bash

# Exit immediately on error
set -e

echo "[1/8] Configuring DNF optimizations..."
# Backup existing config
sudo cp /etc/dnf/dnf.conf /etc/dnf/dnf.conf.bak

# Remove duplicates
sudo sed -i '/^deltarpm/d' /etc/dnf/dnf.conf
sudo sed -i '/^max_parallel_downloads/d' /etc/dnf/dnf.conf

# Add optimized settings
echo "deltarpm=true" | sudo tee -a /etc/dnf/dnf.conf
echo "max_parallel_downloads=10" | sudo tee -a /etc/dnf/dnf.conf

echo "[2/8] Enabling Fedora test updates..."
sudo dnf config-manager --set-enabled updates-testing

echo "[3/8] Installing available system updates..."
sudo dnf upgrade -y

echo "[4/8] Installing Git..."
sudo dnf install -y git

echo "[5/8] Configuring Git user info..."
read -p "Enter your Git email: " git_email
read -p "Enter your Git name: " git_name
git config --global user.email "$git_email"
git config --global user.name "$git_name"

echo "[6/8] Enabling Flatpak support..."
sudo dnf install -y flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

echo "[7/8] Installing Google Chrome via Flatpak..."
flatpak install -y flathub com.google.Chrome

echo "[7b] Removing Firefox if installed..."
sudo dnf remove -y firefox || echo "Firefox not installed, skipping."

echo "[8/8] Removing GNOME bloatware..."
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
  echo "Removing $pkg..."
  sudo dnf remove -y "$pkg" || echo "$pkg not installed, skipping."
done

echo "✅ All tasks completed!"
