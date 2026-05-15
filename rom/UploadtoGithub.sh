#!/bin/bash

# Force GitHub CLI into strict non-interactive mode to prevent freezing
export GH_PROMPT_DISABLED=1
export GH_NO_UPDATE_NOTIFIER=1

echo "=========================================="
echo "Local Folder to GitHub Release Uploader"
echo "=========================================="
echo ""

# 1. Check for GitHub CLI
if ! command -v gh &> /dev/null; then
    echo "[X] GitHub CLI 'gh' is missing!"
    echo "Install it via your package manager (e.g., 'sudo apt install gh') and run 'gh auth login'."
    exit 1
fi

# 2. Get the folder path
echo "[Tip] You can just drag and drop your folder directly into this terminal!"
read -p "[+] Enter the path to the folder containing your files: " LOCAL_FOLDER

# Strip trailing spaces and hidden quotation marks if the user dragged and dropped
LOCAL_FOLDER=$(echo "$LOCAL_FOLDER" | sed -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//' | xargs)

# Expand tilde (~) to full home directory path if used
LOCAL_FOLDER="${LOCAL_FOLDER/#\~/$HOME}"

# Verify the folder actually exists
if [ ! -d "$LOCAL_FOLDER" ]; then
    echo "[X] Error: Cannot find that directory. Did you type the path correctly?"
    exit 1
fi

# 3. Gather Release Info
read -p "[+] Enter GitHub Repo (e.g., Mayuresh2543/stone_releases): " GH_REPO
read -p "[+] Enter Release Tag (e.g., v1.0-LineageOS): " REL_TAG
read -p "[+] Enter Release Title (e.g., LineageOS 23.2): " REL_TITLE

echo ""
echo "=========================================="
echo "[*] Uploading to GitHub Releases..."
echo "=========================================="

# Move into the user's folder
cd "$LOCAL_FOLDER" || exit 1

# Upload everything inside the folder to GitHub (Added < /dev/null to prevent the spinner freeze)
if gh release create "$REL_TAG" * --repo "$GH_REPO" --title "$REL_TITLE" --notes "Uploaded from local Linux machine." < /dev/null; then
    echo ""
    echo "[+] Successfully published to GitHub!"
else
    echo ""
    echo "[X] Failed to upload to GitHub. Check your repo name, tag, and permissions."
    exit 1
fi

echo "[+] Done!"
