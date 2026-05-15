@echo off
setlocal enabledelayedexpansion

:: Force GitHub CLI into strict non-interactive mode to prevent freezing
set GH_PROMPT_DISABLED=1
set GH_NO_UPDATE_NOTIFIER=1

echo ==========================================
echo Local Folder to GitHub Release Uploader
echo ==========================================
echo.

:: 1. Check for GitHub CLI
where gh >nul 2>nul
if %errorlevel% neq 0 (
    echo [X] GitHub CLI 'gh' is missing!
    echo Install it with 'winget install GitHub.cli' and run 'gh auth login'.
    pause
    exit /b
)

:: 2. Get the folder path
echo [Tip] You can just drag and drop your folder directly into this window!
set /p LOCAL_FOLDER="[+] Enter the path to the folder containing your 5 files: "

:: Strip hidden quotation marks if the user dragged and dropped the folder
set LOCAL_FOLDER=!LOCAL_FOLDER:"=!

:: Verify the folder actually exists
if not exist "!LOCAL_FOLDER!\" (
    echo [X] Error: Cannot find that folder. Did you type the path correctly?
    pause
    exit /b
)

:: 3. Gather Release Info
set /p GH_REPO="[+] Enter GitHub Repo (e.g., Mayuresh2543/stone_releases): "
set /p REL_TAG="[+] Enter Release Tag (e.g., v1.0-LineageOS): "
set /p REL_TITLE="[+] Enter Release Title (e.g., LineageOS 23.2): "

echo.
echo ==========================================
echo [*] Uploading to GitHub Releases...
echo ==========================================

:: Move into the user's folder
cd /d "!LOCAL_FOLDER!"

:: Upload everything inside the folder to GitHub (Added <nul to prevent the spinner freeze)
gh release create "%REL_TAG%" * --repo "%GH_REPO%" --title "%REL_TITLE%" --notes "Uploaded from local machine." <nul

if %errorlevel% neq 0 (
    echo.
    echo [X] Failed to upload to GitHub. Check your repo name and permissions.
) else (
    echo.
    echo [+] Successfully published to GitHub!
)

echo [+] Done!
pause
