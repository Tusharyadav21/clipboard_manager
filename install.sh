#!/bin/bash
set -e

# Configuration
REPO="Tusharyadav21/clipboard_manager"
APP_NAME="clipboard manager"
INSTALL_DIR="/Applications"

echo "📥 Fetching latest release from GitHub..."
# Fetch the latest release DMG URL from GitHub API
RELEASE_URL=$(curl -s https://api.github.com/repos/${REPO}/releases/latest | grep "browser_download_url.*dmg" | cut -d '"' -f 4)

if [ -z "$RELEASE_URL" ]; then
    echo "❌ Error: Could not find the latest release DMG on GitHub."
    exit 1
fi

TEMP_DMG="/tmp/clipboard_manager_latest.dmg"
echo "📥 Downloading application..."
curl -L -o "${TEMP_DMG}" "${RELEASE_URL}"

echo "💿 Mounting installer disk image..."
MOUNT_POINT=$(hdiutil attach "${TEMP_DMG}" -nobrowse | grep "/Volumes/" | awk -F '\t' '{print $NF}')

echo "🚚 Copying to Applications..."
# Remove old version if it exists
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "${MOUNT_POINT}/${APP_NAME}.app" "${INSTALL_DIR}/"

echo "🧹 Unmounting and cleaning up..."
hdiutil detach "${MOUNT_POINT}"
rm -f "${TEMP_DMG}"

echo "🛡️ Safely removing macOS quarantine flag..."
xattr -cr "${INSTALL_DIR}/${APP_NAME}.app"

echo "🎉 Installation successful! You can now launch '${APP_NAME}' from Applications or Spotlight."
