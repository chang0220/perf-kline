#!/bin/zsh
# 编译并打包成 dist/性能行情.app（本机自签名，不上架）。
# 用法：scripts/build-app.sh [--install]   加 --install 会再复制到 ~/code/_交付/perf-kline/
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=0.1.0
swift build -c release
APP="dist/性能行情.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PerfKline "$APP/Contents/MacOS/PerfKline"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>PerfKline</string>
  <key>CFBundleIdentifier</key><string>local.perfkline</string>
  <key>CFBundleName</key><string>性能行情</string>
  <key>CFBundleDisplayName</key><string>性能行情</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "已打包：$APP"
if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/code/_交付/perf-kline"
  mkdir -p "$DEST"
  rm -rf "$DEST/性能行情.app"
  cp -R "$APP" "$DEST/"
  echo "已复制到：$DEST/性能行情.app"
fi
