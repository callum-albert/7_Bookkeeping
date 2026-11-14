#!/usr/bin/env bash
# 下载 iOS SDK（约 53MB），解压到 tools/sdk/
# 来源：https://github.com/xybp888/iOS-SDKs
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/tools/sdk"
SDK_NAME="iPhoneOS27.2.sdk"
URL="https://github.com/xybp888/iOS-SDKs/releases/download/iOS27.2-SDKs/iPhoneOS27.2.sdk.zip"
TOTAL=55417972
PARTS=16

if [ -d "$DEST/$SDK_NAME" ]; then
  echo "SDK 已存在: $DEST/$SDK_NAME"
  exit 0
fi

mkdir -p "$DEST"
cd "$DEST"

echo "==> 下载 iOS SDK（$PARTS 线程分段，绕过单连接限速）"
CH=$(( (TOTAL + PARTS - 1) / PARTS ))
for i in $(seq 0 $((PARTS-1))); do
  S=$((i*CH)); E=$((S+CH-1)); [ $E -ge $TOTAL ] && E=$((TOTAL-1))
  (
    for attempt in 1 2 3 4 5; do
      have=$(stat -f%z "part.$i" 2>/dev/null || echo 0)
      [ "$have" -ge $((E-S+1)) ] && break
      curl -sL --retry 5 --retry-all-errors --max-time 900 \
        -r $((S+have))-$E -o "part.$i.part" "$URL" || true
      cat "part.$i.part" >> "part.$i" 2>/dev/null || true
      rm -f "part.$i.part"
    done
  ) &
done
wait

cat part.* > sdk.zip
rm -f part.*
unzip -q -o sdk.zip -d .
rm -f sdk.zip

if [ -d "$DEST/$SDK_NAME" ]; then
  echo "==> 完成: $DEST/$SDK_NAME"
else
  echo "❌ 解压失败" >&2
  exit 1
fi

# SDK 只保留 arm64e 的 swiftinterface，镜像一份 arm64 供编译器使用
python3 - "$DEST/$SDK_NAME" <<'PY'
import sys, pathlib
root = pathlib.Path(sys.argv[1])
n = 0
for d in root.rglob("*.swiftmodule"):
    if not d.is_dir(): continue
    src = d / "arm64e-apple-ios.swiftinterface"
    if not src.exists(): continue
    txt = src.read_text(errors="ignore")
    txt = txt.replace("-target-arch-variant arm64e.x1 ", "").replace("arm64e", "arm64")
    (d / "arm64-apple-ios.swiftinterface").write_text(txt)
    n += 1
print(f"swiftinterface 镜像完成: {n} 个模块")
PY

echo "🎉 可以运行 ./build.sh 了"
