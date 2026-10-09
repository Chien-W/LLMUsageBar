#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="LLMUsageBar"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "🚀 开始构建 macOS 原生菜单栏应用: $APP_NAME..."

# 清理旧构建目录
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 获取 macOS SDK 路径
SDK_PATH="$(xcrun --show-sdk-path)"

# 收集所有 Swift 源文件
SWIFT_FILES=$(find "$SCRIPT_DIR/LLMUsageBar" -name "*.swift" -type f | sort)

echo "📦 正在编译 Swift 源文件..."
swiftc \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macos14.0 \
    -O \
    -framework SwiftUI \
    -framework AppKit \
    -framework Foundation \
    -framework Combine \
    $SWIFT_FILES \
    -o "$MACOS_DIR/$APP_NAME"

echo "📝 生成应用 Info.plist..."
cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>LLMUsageBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.ai.llmusagebar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AI 用量监控</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ 构建完成！应用生成在: $APP_BUNDLE"
echo "👉 运行命令: open \"$APP_BUNDLE\""
