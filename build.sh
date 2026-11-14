#!/bin/bash
# 7记账 · 手动构建脚本（无需 Xcode，使用 iOS SDK + clang/swiftc）
set -euo pipefail

SDK="${SDK:-/tmp/sdkbuild/sdk/iPhoneOS27.2.sdk}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP_NAME="Seven7"
DISPLAY_NAME="7记账"
BUNDLE_ID="com.seven.bookkeeping"
WIDGET_ID="com.seven.bookkeeping.widgets"
DEPLOY="26.0"

SWIFT_FLAGS=(-target arm64-apple-ios$DEPLOY -sdk "$SDK" -swift-version 5 -O -whole-module-optimization
             -Xfrontend -disable-availability-checking
             -F "$SDK/System/Library/Frameworks" -L "$SDK/usr/lib/swift" -I "$SDK/usr/include")

echo "==> 清理"
rm -rf "$BUILD"
mkdir -p "$BUILD/Payload"
APP="$BUILD/Payload/Seven7.app"
mkdir -p "$APP"

SOURCES_APP=$(find "$ROOT/Sources" -name "*.swift" -not -path "*/Widget/*" | tr '\n' ' ')
SOURCES_WIDGET=$(find "$ROOT/Sources/Widget" -name "*.swift" | tr '\n' ' ')
ATTR_FILE="$ROOT/Sources/LiveActivity/BookkeepingAttributes.swift"

echo "==> 编译主程序"
# shellcheck disable=SC2086
swiftc "${SWIFT_FLAGS[@]}" $SOURCES_APP -o "$APP/$APP_NAME" 2>&1 | sed 's/^/   /'
echo "   ok: $(du -h "$APP/$APP_NAME" | cut -f1)"

echo "==> 编译灵动岛扩展"
mkdir -p "$APP/PlugIns/SevenWidgets.appex"
# shellcheck disable=SC2086
swiftc "${SWIFT_FLAGS[@]}" $SOURCES_WIDGET "$ATTR_FILE" \
  -o "$APP/PlugIns/SevenWidgets.appex/SevenWidgets" \
  -Xlinker -e -Xlinker _NSExtensionMain 2>&1 | sed 's/^/   /'
echo "   ok: $(du -h "$APP/PlugIns/SevenWidgets.appex/SevenWidgets" | cut -f1)"

echo "==> 生成图标"
python3 "$ROOT/tools/make_icon.py" "$ROOT/build/icons"
ICON_DIR="$ROOT/build/icons"
ic() { cp "$ICON_DIR/$1" "$APP/$2"; }
ic icon-120.png "AppIcon60x60@2x.png"
ic icon-180.png "AppIcon60x60@3x.png"
ic icon-80.png  "AppIcon40x40@2x.png"
ic icon-120.png "AppIcon40x40@3x.png"
ic icon-58.png  "AppIcon29x29@2x.png"
ic icon-87.png  "AppIcon29x29@3x.png"
ic icon-1024.png "AppIcon1024.png"

echo "==> 写入 Info.plist"
cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>zh-Hant</string><string>en</string></array>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>$DEPLOY</string>
  <key>LSMinimumSystemVersion</key><string>$DEPLOY</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>DTPlatformName</key><string>iphoneos</string>
  <key>DTPlatformVersion</key><string>27.2</string>
  <key>DTSDKName</key><string>iphoneos27.2</string>
  <key>DTXcode</key><string>2700</string>
  <key>DTXcodeBuild</key><string>27A100</string>
  <key>DTCompiler</key><string>com.apple.compilers.llvm.clang.1_0</string>
  <key>BuildMachineOSBuild</key><string>26B131</string>
  <key>CFBundleSignature</key><string>????</string>
  <key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>
  <key>UILaunchScreen</key><dict/>
  <key>UISupportedInterfaceOrientations</key>
  <array><string>UIInterfaceOrientationPortrait</string></array>
  <key>UIApplicationSceneManifest</key>
  <dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
  <key>NSSupportsLiveActivities</key><true/>
  <key>NSSupportsLiveActivitiesFrequentUpdates</key><true/>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
  <key>NSPhotoLibraryUsageDescription</key><string>选择账单截图，自动识别金额与商户</string>
  <key>UIStatusBarStyle</key><string>UIStatusBarStyleDefault</string>
  <key>CFBundleIcons</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconFiles</key><array><string>AppIcon60x60</string></array>
      <key>CFBundleIconName</key><string>AppIcon</string>
    </dict>
  </dict>
  <key>CFBundleIcons~ipad</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict><key>CFBundleIconFiles</key><array><string>AppIcon60x60</string></array></dict>
  </dict>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
      <key>CFBundleURLSchemes</key><array><string>seven7</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "==> 写入扩展 Info.plist"
cat > "$APP/PlugIns/SevenWidgets.appex/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleDisplayName</key><string>SevenWidgets</string>
  <key>CFBundleExecutable</key><string>SevenWidgets</string>
  <key>CFBundleIdentifier</key><string>$WIDGET_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>SevenWidgets</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>1.1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>MinimumOSVersion</key><string>$DEPLOY</string>
  <key>LSMinimumSystemVersion</key><string>$DEPLOY</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>DTPlatformName</key><string>iphoneos</string>
  <key>DTPlatformVersion</key><string>27.2</string>
  <key>DTSDKName</key><string>iphoneos27.2</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
  </dict>
</dict>
</plist>
PLIST

echo "==> 清除扩展属性"
xattr -cr "$BUILD/Payload" 2>/dev/null || true

echo "==> 生成 App Intents 元数据（快捷指令动作库索引）"
python3 "$ROOT/tools/make_appintents_metadata.py" "$APP"

echo "==> 写入本地化名称（桌面显示中文）"
mkdir -p "$APP/zh-Hans.lproj" "$APP/zh-Hant.lproj" "$APP/en.lproj"
cat > "$APP/zh-Hans.lproj/InfoPlist.strings" <<'LOC'
"CFBundleDisplayName" = "7记账";
"CFBundleName" = "7记账";
LOC
cat > "$APP/zh-Hant.lproj/InfoPlist.strings" <<'LOC'
"CFBundleDisplayName" = "7記賬";
"CFBundleName" = "7記賬";
LOC
cat > "$APP/en.lproj/InfoPlist.strings" <<'LOC'
"CFBundleDisplayName" = "7 Bookkeeping";
"CFBundleName" = "7 Bookkeeping";
LOC

WIDGET_APPEX="$APP/PlugIns/SevenWidgets.appex"
mkdir -p "$WIDGET_APPEX/zh-Hans.lproj"
cat > "$WIDGET_APPEX/zh-Hans.lproj/InfoPlist.strings" <<'LOC'
"CFBundleDisplayName" = "7记账 灵动岛";
LOC

echo "==> 内置 ad-hoc 签名"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$APP/PlugIns/SevenWidgets.appex" 2>&1 | sed 's/^/   /'
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$APP" 2>&1 | sed 's/^/   /'
xattr -cr "$BUILD/Payload" 2>/dev/null || true
if codesign -v "$APP" 2>/dev/null && codesign -v "$APP/PlugIns/SevenWidgets.appex" 2>/dev/null; then
  echo "   签名校验通过（主程序 + 扩展）"
else
  echo "   ⚠️ 签名校验失败"
fi

echo "==> 打包 ipa"
cd "$BUILD"
rm -f 7jizhang.ipa
zip -qrX 7jizhang.ipa Payload
cd "$ROOT"
cp "$BUILD/7jizhang.ipa" "$ROOT/7记账.ipa"
echo ""
echo "✅ 完成: $ROOT/7记账.ipa  ($(du -h "$ROOT/7记账.ipa" | cut -f1))"
