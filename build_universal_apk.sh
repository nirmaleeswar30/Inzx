#!/bin/bash
# Build Universal APK from AAB using bundletool
# Usage: ./build_universal_apk.sh

set -e

# Configuration
BUNDLETOOL_DIR="$HOME/tools"
BUNDLETOOL_PATH="$BUNDLETOOL_DIR/bundletool.jar"
AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
APKS_PATH="build/app/outputs/bundle/release/app-release.apks"
OUTPUT_DIR="build/app/outputs/bundle/release/apks"

# Debug keystore (default Android debug signing)
KEYSTORE_PATH="$HOME/.config/.android/debug.keystore"
KEY_ALIAS="androiddebugkey"
KEYSTORE_PASSWORD="android"
KEY_PASSWORD="android"

echo -e "\033[1;36m=== Universal APK Builder ===\033[0m\n"

# Check Java
echo -e "\033[1;33mChecking Java...\033[0m"
if ! command -v java &> /dev/null; then
    echo -e "  \033[1;31mERROR: Java not found in PATH. Please install Java JDK.\033[0m"
    exit 1
fi
JAVA_VERSION=$(java -version 2>&1 | head -n 1)
echo -e "  \033[1;32mFound: $JAVA_VERSION\033[0m"

# Check bundletool
echo -e "\033[1;33mChecking bundletool...\033[0m"
if [ -f "$BUNDLETOOL_PATH" ]; then
    echo -e "  \033[1;32mFound: $BUNDLETOOL_PATH\033[0m"
else
    echo -e "  \033[1;33mBundletool not found. Downloading...\033[0m"
    mkdir -p "$BUNDLETOOL_DIR"
    curl -L -o "$BUNDLETOOL_PATH" "https://github.com/google/bundletool/releases/download/1.17.2/bundletool-all-1.17.2.jar"
    echo -e "  \033[1;32mDownloaded to: $BUNDLETOOL_PATH\033[0m"
fi

# Check AAB file
echo -e "\033[1;33mChecking AAB file...\033[0m"
if [ -f "$AAB_PATH" ]; then
    AAB_SIZE=$(du -m "$AAB_PATH" | cut -f1)
    echo -e "  \033[1;32mFound: $AAB_PATH (${AAB_SIZE} MB)\033[0m"
else
    echo -e "  \033[1;31mERROR: AAB not found at $AAB_PATH\033[0m"
    echo -e "  \033[1;31mRun 'shorebird release android' first.\033[0m"
    exit 1
fi

# Check keystore
echo -e "\033[1;33mChecking keystore...\033[0m"
if [ -f "$KEYSTORE_PATH" ]; then
    echo -e "  \033[1;32mFound: $KEYSTORE_PATH\033[0m"
else
    echo -e "  \033[1;33mDebug keystore not found at $KEYSTORE_PATH. Generating one...\033[0m"
    mkdir -p "$(dirname "$KEYSTORE_PATH")"
    keytool -genkey -v -keystore "$KEYSTORE_PATH" -storepass "$KEYSTORE_PASSWORD" -alias "$KEY_ALIAS" -keypass "$KEY_PASSWORD" -keyalg RSA -keysize 2048 -validity 10000 -dname "C=US, O=Android, CN=Android Debug"
    
    if [ -f "$KEYSTORE_PATH" ]; then
        echo -e "  \033[1;32mGenerated: $KEYSTORE_PATH\033[0m"
    else
        echo -e "  \033[1;31mERROR: Failed to generate debug keystore.\033[0m"
        exit 1
    fi
fi

# Build APK set
echo ""
echo -e "\033[1;33mBuilding APK set (universal mode)...\033[0m"
java -jar "$BUNDLETOOL_PATH" build-apks \
    --bundle="$AAB_PATH" \
    --output="$APKS_PATH" \
    --mode=universal \
    --ks="$KEYSTORE_PATH" \
    --ks-key-alias="$KEY_ALIAS" \
    --ks-pass="pass:$KEYSTORE_PASSWORD" \
    --key-pass="pass:$KEY_PASSWORD" \
    --overwrite

echo -e "  \033[1;32mAPK set created: $APKS_PATH\033[0m"

# Extract universal APK
echo ""
echo -e "\033[1;33mExtracting universal APK...\033[0m"

# Remove existing output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# .apks is a ZIP file, extract it using unzip
unzip -q "$APKS_PATH" -d "$OUTPUT_DIR"

UNIVERSAL_APK="$OUTPUT_DIR/universal.apk"
if [ -f "$UNIVERSAL_APK" ]; then
    APK_SIZE=$(du -m "$UNIVERSAL_APK" | cut -f1)
    echo -e "  \033[1;32mExtracted: $UNIVERSAL_APK (${APK_SIZE} MB)\033[0m"
else
    echo -e "  \033[1;31mERROR: universal.apk not found in extracted files\033[0m"
    exit 1
fi

# Done
echo ""
echo -e "\033[1;32m=== SUCCESS ===\033[0m"
echo -e "\033[1;36mUniversal APK: $UNIVERSAL_APK\033[0m"
echo -e "\033[1;36mSize: ${APK_SIZE} MB\033[0m"
echo ""
echo "Upload this file to GitHub Releases for Shorebird patch distribution."
