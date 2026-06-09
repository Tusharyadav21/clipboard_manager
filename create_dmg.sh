#!/bin/bash

# ==============================================================================
# DMG Build & Package Script for Clipboard Manager macOS
# ==============================================================================
# This script automates building the Clipboard Manager application in Release
# configuration and packaging it into a distribution DMG file.
#
# Output:
#   - Built application: build/DerivedData/Build/Products/Release/clipboard manager.app
#   - DMG Installer: ./Clipboard\ Manager.dmg
# ==============================================================================

set -euo pipefail

APP_NAME="clipboard manager"
DMG_NAME="Clipboard Manager.dmg"
BUILD_DIR="./build"
DERIVED_DATA_DIR="${BUILD_DIR}/DerivedData"
TEMP_DMG_DIR="${BUILD_DIR}/temp_dmg"

# 1. Set developer directory path for Xcode tools in terminal session
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

echo "--------------------------------------------------"
echo "🚀 Starting Build Process..."
echo "--------------------------------------------------"

# 2. Clean previous build outputs
echo "🧹 Cleaning previous build and packaging folders..."
rm -rf "${BUILD_DIR}"
rm -f "${DMG_NAME}"

# 3. Build the application in Release configuration
echo "🏗️ Building ${APP_NAME} in Release mode..."
xcodebuild -project "${APP_NAME}.xcodeproj" \
           -scheme "${APP_NAME}" \
           -configuration Release \
           -derivedDataPath "${DERIVED_DATA_DIR}" \
           build

# 4. Locate the built .app package
BUILT_APP="${DERIVED_DATA_DIR}/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "${BUILT_APP}" ]; then
    echo "❌ Error: Built application not found at ${BUILT_APP}"
    exit 1
fi

echo "✅ Build completed successfully."

# 5. Package as DMG
echo "--------------------------------------------------"
echo "📦 Packaging distribution DMG..."
echo "--------------------------------------------------"

mkdir -p "${TEMP_DMG_DIR}"

echo "📂 Copying built bundle..."
cp -R "${BUILT_APP}" "${TEMP_DMG_DIR}/"

echo "🔗 Creating symlink to Applications directory..."
ln -s /Applications "${TEMP_DMG_DIR}/Applications"

echo "💿 Creating disk image..."
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${TEMP_DMG_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_NAME}"

# 6. Cleanup temporary DMG packaging folder
echo "🧹 Cleaning up temporary directories..."
rm -rf "${TEMP_DMG_DIR}"

echo "--------------------------------------------------"
echo "🎉 DMG successfully created: ./${DMG_NAME}"
echo "--------------------------------------------------"
