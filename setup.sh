#!/bin/bash
# ============================================================
# VideoSaver Flutter App - Setup Script
# Jalankan script ini setelah install Flutter SDK
# ============================================================
set -e

APP_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== VideoSaver Flutter Setup ==="
echo ""

# 1. Check Flutter
if ! command -v flutter &>/dev/null; then
    echo "ERROR: Flutter tidak ditemukan!"
    echo ""
    echo "Install Flutter terlebih dahulu:"
    echo "  https://docs.flutter.dev/get-started/install"
    echo ""
    echo "Setelah install, jalankan script ini lagi."
    exit 1
fi

echo "Flutter: $(flutter --version 2>&1 | head -1)"
echo ""

# 2. Backup source files
TEMP_DIR=$(mktemp -d)
echo "Backup source files ke $TEMP_DIR..."
cp -r "$APP_DIR/lib" "$TEMP_DIR/"
cp "$APP_DIR/pubspec.yaml" "$TEMP_DIR/"

# 3. Create Flutter project (hanya jika belum ada)
if [ ! -f "$APP_DIR/android/app/build.gradle" ]; then
    echo "Membuat Flutter project..."
    # Simpan files kita ke temp
    cd "$(dirname "$APP_DIR")"
    FOLDER_NAME="$(basename "$APP_DIR")"

    # Rename folder kita sementara
    mv "$APP_DIR" "${APP_DIR}_backup"

    # Create fresh Flutter project
    flutter create --org com.example --project-name video_downloader "$APP_DIR"

    # Copy source files kita ke project baru
    cp -r "${APP_DIR}_backup/lib/." "$APP_DIR/lib/"
    cp "${APP_DIR}_backup/pubspec.yaml" "$APP_DIR/pubspec.yaml"
    cp -r "${APP_DIR}_backup/android_ios_config" "$APP_DIR/"
    cp "${APP_DIR}_backup/setup.sh" "$APP_DIR/"

    # Hapus backup
    rm -rf "${APP_DIR}_backup"
else
    echo "Flutter project sudah ada, skip flutter create"
fi

cd "$APP_DIR"

# 4. Copy platform config files
echo ""
echo "Mengkonfigurasi platform..."

# Android: manifest
mkdir -p android/app/src/main/res/xml
cp android_ios_config/provider_paths.xml android/app/src/main/res/xml/provider_paths.xml
cp android_ios_config/network_security_config.xml android/app/src/main/res/xml/network_security_config.xml
echo "  [OK] Android XML resources"

# Patch AndroidManifest.xml - add permissions & FileProvider
MANIFEST="android/app/src/main/AndroidManifest.xml"
if ! grep -q "WRITE_EXTERNAL_STORAGE" "$MANIFEST"; then
    # Add permissions before <application
    sed -i '' 's|<application|<uses-permission android:name="android.permission.INTERNET" />\
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />\
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />\
\
    <application|' "$MANIFEST"
    echo "  [OK] Android permissions"
fi

if ! grep -q "usesCleartextTraffic" "$MANIFEST"; then
    sed -i '' 's|android:label="video_downloader"|android:label="VideoSaver"\
        android:usesCleartextTraffic="true"\
        android:requestLegacyExternalStorage="true"\
        android:networkSecurityConfig="@xml/network_security_config"|' "$MANIFEST"
    echo "  [OK] Android cleartext traffic"
fi

if ! grep -q "FileProvider" "$MANIFEST"; then
    sed -i '' 's|</application>|        <provider\
            android:name="androidx.core.content.FileProvider"\
            android:authorities="${applicationId}.fileProvider"\
            android:exported="false"\
            android:grantUriPermissions="true">\
            <meta-data\
                android:name="android.support.FILE_PROVIDER_PATHS"\
                android:resource="@xml/provider_paths" />\
        </provider>\
    </application>|' "$MANIFEST"
    echo "  [OK] Android FileProvider"
fi

# iOS: Info.plist additions
IOS_PLIST="ios/Runner/Info.plist"
if ! grep -q "NSPhotoLibraryUsageDescription" "$IOS_PLIST" 2>/dev/null; then
    if [ -f "$IOS_PLIST" ]; then
        sed -i '' 's|<dict>|<dict>\
\t<key>NSPhotoLibraryUsageDescription</key>\
\t<string>VideoSaver perlu akses untuk menyimpan video yang diunduh</string>\
\t<key>NSPhotoLibraryAddUsageDescription</key>\
\t<string>VideoSaver perlu akses untuk menyimpan video ke galeri</string>\
\t<key>NSAppTransportSecurity</key>\
\t<dict>\
\t\t<key>NSAllowsArbitraryLoads</key>\
\t\t<false/>\
\t\t<key>NSExceptionDomains</key>\
\t\t<dict>\
\t\t\t<key>localhost</key>\
\t\t\t<dict>\
\t\t\t\t<key>NSExceptionAllowsInsecureHTTPLoads</key>\
\t\t\t\t<true/>\
\t\t\t</dict>\
\t\t</dict>\
\t</dict>|1' "$IOS_PLIST"
        echo "  [OK] iOS Info.plist"
    fi
fi

# 5. flutter pub get
echo ""
echo "Installing packages..."
flutter pub get

echo ""
echo "====================================="
echo "SETUP SELESAI!"
echo "====================================="
echo ""
echo "Langkah selanjutnya:"
echo ""
echo "1. Jalankan backend terlebih dahulu:"
echo "   cd ../video_downloader_backend && ./start.sh"
echo ""
echo "2. Jalankan app di emulator/device:"
echo "   flutter run"
echo ""
echo "3. Di Settings app, atur URL backend:"
echo "   - Android Emulator: http://10.0.2.2:8000"
echo "   - HP Fisik: http://<IP-Komputer>:8000"
echo "   - iOS Simulator: http://localhost:8000"
echo ""
