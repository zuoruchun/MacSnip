#!/usr/bin/env bash
set -e

# 设置命令行开发工具目录（避免没有同意 Xcode 协议时报错）
if [ -d "/Library/Developer/CommandLineTools" ]; then
    export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Terminating any running MacSnip instances..."
killall MacSnip 2>/dev/null || true

echo "==> Building MacSnip release binary..."
cd "${ROOT_DIR}"
swift build -c release

BIN_PATH="${ROOT_DIR}/.build/release/MacSnip"
APP_BUNDLE="${ROOT_DIR}/build/MacSnip.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_SRC="${SCRIPT_DIR}/AppIcon.icns"

echo "==> Packaging into ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/MacSnip"
chmod +x "${MACOS_DIR}/MacSnip"

# 复制图标
if [ -f "${ICON_SRC}" ]; then
    cp "${ICON_SRC}" "${RESOURCES_DIR}/AppIcon.icns"
    echo "==> Icon copied."
fi

cat > "${CONTENTS_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>MacSnip</string>
    <key>CFBundleIdentifier</key>
    <string>com.macsnip.app</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacSnip</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>MacSnip 需要屏幕录制权限以捕获当前屏幕上的窗口与内容。</string>
</dict>
</plist>
EOF

echo "==> Applying Ad-Hoc code signature with explicit bundle identifier..."
codesign --force --deep --sign - -i com.macsnip.app "${APP_BUNDLE}"

echo "==> MacSnip.app successfully built and signed at: ${APP_BUNDLE}"

# 打包 ZIP 发布包
ZIP_PATH="${ROOT_DIR}/build/MacSnip-v1.1.0-macOS-arm64.zip"
echo "==> Creating release zip at ${ZIP_PATH}..."
rm -f "${ZIP_PATH}"
(cd "${ROOT_DIR}/build" && zip -r -q -y "MacSnip-v1.1.0-macOS-arm64.zip" "MacSnip.app")
echo "==> Release zip created: ${ZIP_PATH}"

# 安装到 /Applications
echo "==> Installing to /Applications..."
rm -rf "/Applications/MacSnip.app"
cp -R "${APP_BUNDLE}" "/Applications/MacSnip.app"
echo "==> MacSnip.app installed to /Applications successfully!"
