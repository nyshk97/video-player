#!/usr/bin/env bash
# Vid を実機（ペアリング済みの iPhone）に Release で入れて起動する。
# 一度 USB でペアリングした端末なら、同じ Wi-Fi にいて端末のロックが外れていれば USB は要らない。
# 引数: 入れる端末（名前・種類・UDID のどれかの一部。all で全部）。ペアリング済みの iPhone が 1 台なら省略できる
# 写し元: nyshk97/todo-app の scripts/install-ios-device.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

WANT="${1:-}"
NAME=Vid
BUNDLE_ID=com.d0ne1s.vid
# 自作アプリ共通の Team（station・kypr・mobile-ide と同じ）
TEAM="${VID_DEVELOPMENT_TEAM:-VYDUR99LAM}"

LIST=$(mktemp)
xcrun devicectl list devices --json-output "$LIST" >/dev/null
# 1 行 1 台で「UDID<TAB>種類 名前」。開発の準備前（デベロッパモードが出る前）の端末は reality が空なので、simulated 以外を実機とみなす
DEVICES=$(WANT="$WANT" LIST="$LIST" python3 -c "
import json, os, sys
want = os.environ['WANT'].lower()
d = json.load(open(os.environ['LIST']))['result']['devices']
# iPhone だけ（ペアした Apple Watch も同じ一覧に出る）
p = [x for x in d if x['connectionProperties'].get('pairingState') == 'paired' and x['hardwareProperties'].get('reality') != 'simulated'
     and x['hardwareProperties'].get('platform') == 'iOS']
def label(x): return f\"{x['hardwareProperties'].get('deviceType', '?')} {x['deviceProperties'].get('name', '?')}\"
if want and want != 'all':
    p = [x for x in p if want in x['hardwareProperties']['udid'].lower() or want in label(x).lower()]
else:
    # 名指ししないときは、いま届かない端末（電源オフ・別のネットワーク等で tunnelState が unavailable）を外す
    p = [x for x in p if x['connectionProperties'].get('tunnelState') != 'unavailable']
if not want and len(p) > 1:
    print('ペアリング済みの実機が複数ある。入れる端末を引数で指定する（all / 名前・UDID の一部）:', file=sys.stderr)
    for x in p: print(f\"  {label(x)}  {x['hardwareProperties']['udid']}\", file=sys.stderr)
    sys.exit(2)
for x in p: print(f\"{x['hardwareProperties']['udid']}\t{label(x)}\")")
rm -f "$LIST"
[ -n "$DEVICES" ] || { echo "ペアリング済みの実機が見つからない${WANT:+（指定: ${WANT}）}"; exit 1; }

xcodegen generate >/dev/null
BUILD_DIR="$REPO_ROOT/build"
mkdir -p "$BUILD_DIR"
while IFS=$'\t' read -r DEVICE LABEL; do
  echo "== ${LABEL}（${DEVICE}）"
  # 初めての端末は -allowProvisioningDeviceRegistration で Team に登録し、プロファイルに入れる
  # ロック中だと「The developer disk image could not be mounted」→ destination のタイムアウトで落ちる
  xcodebuild -project "${NAME}.xcodeproj" -scheme "$NAME" -configuration Release -destination "id=${DEVICE}" \
    -derivedDataPath "$BUILD_DIR/dd-device" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM" build >"$BUILD_DIR/device.log" 2>&1 \
    || { grep -E 'error:' "$BUILD_DIR/device.log" | head -20; echo "ビルドできない（端末のロックが外れているか確認。全文: build/device.log）"; exit 1; }
  APP="$BUILD_DIR/dd-device/Build/Products/Release-iphoneos/${NAME}.app"
  xcrun devicectl device install app --device "$DEVICE" "$APP"
  xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$BUNDLE_ID"
done <<< "$DEVICES"
