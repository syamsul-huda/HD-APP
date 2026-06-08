#!/bin/bash
# Quick start: setup project + jalankan di web browser
# Jalankan: bash quick_start.sh
set -e

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR"

# 1. Check Flutter
if ! command -v flutter &>/dev/null; then
    echo "Flutter belum siap. Tunggu instalasi selesai lalu coba lagi."
    exit 1
fi
echo "Flutter: $(flutter --version 2>&1 | head -1)"

# 2. Jika belum ada platform directories, jalankan flutter create
if [ ! -d "web" ] || [ ! -d "android" ]; then
    echo ""
    echo "Membuat Flutter project (pertama kali)..."
    flutter create --project-name video_downloader --org com.videosaver \
        --platforms android,ios,web . 2>&1 | grep -v "^$"
fi

# 3. Copy platform config files untuk Android
if [ -d "android" ]; then
    mkdir -p android/app/src/main/res/xml

    # provider_paths.xml
    cp android_ios_config/provider_paths.xml android/app/src/main/res/xml/provider_paths.xml 2>/dev/null || true
    # network_security_config.xml
    cp android_ios_config/network_security_config.xml android/app/src/main/res/xml/network_security_config.xml 2>/dev/null || true

    MANIFEST="android/app/src/main/AndroidManifest.xml"

    # Tambah izin storage jika belum ada
    if ! grep -q "WRITE_EXTERNAL_STORAGE" "$MANIFEST" 2>/dev/null; then
        sed -i '' 's|<application|<uses-permission android:name="android.permission.INTERNET" />\
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />\
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />\
\
    <application|' "$MANIFEST" 2>/dev/null || true
    fi

    # Enable cleartext HTTP
    if ! grep -q "usesCleartextTraffic" "$MANIFEST" 2>/dev/null; then
        sed -i '' 's|android:label="video_downloader"|android:label="VideoSaver"\
        android:usesCleartextTraffic="true"\
        android:requestLegacyExternalStorage="true"\
        android:networkSecurityConfig="@xml/network_security_config"|' "$MANIFEST" 2>/dev/null || true
    fi

    # Tambah FileProvider
    if ! grep -q "FileProvider" "$MANIFEST" 2>/dev/null; then
        sed -i '' 's|</application>|        <provider android:name="androidx.core.content.FileProvider" android:authorities="${applicationId}.fileProvider" android:exported="false" android:grantUriPermissions="true"><meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/provider_paths" /></provider>\
    </application>|' "$MANIFEST" 2>/dev/null || true
    fi

    echo "[OK] Android configured"
fi

# 4. flutter pub get
echo ""
echo "Installing packages..."
flutter pub get

# 5. Cek Chrome / browser
BROWSER_FOUND=false
for b in "Google Chrome" "Chromium" "Firefox"; do
    if open -Ra "$b" 2>/dev/null; then
        BROWSER_FOUND=true
        break
    fi
done

echo ""
echo "========================================"
echo "  SETUP SELESAI - Menjalankan app..."
echo "========================================"
echo ""
echo "Backend harus sudah jalan di:"
echo "  http://localhost:8000"
echo ""
echo "App akan buka di: http://localhost:3000"
echo ""

# 6. Jalankan di web
flutter run -d web-server --web-port 3000 --web-hostname localhost
