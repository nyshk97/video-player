# 動作確認

iOS シミュレータ上で動作確認する手順。

## 環境

- Xcode 26.5 (iOS 26.5 SDK)
- iOS Simulator 26.4 (Xcode 26.5 が想定する 26.5 simulator runtime は未インストール → `-sdk iphonesimulator` 指定で回避)
- bundle id: `com.d0ne1s.vid`
- ターゲット: iPhone (iOS 17.0+)
- 写真ライブラリへの readWrite アクセス必須

## セットアップ

### 1. プロジェクト生成

`project.yml` を編集したら必ず再生成する。

```sh
mise run gen   # = xcodegen generate
```

### 2. シミュレータ起動

```sh
mise run boot
```

### 3. ビルド & インストール & 起動

```sh
mise run run   # build → install → launch
```

### 4. サンプル動画の投入 (シミュレータに動画が無い場合)

```sh
mkdir -p /tmp/vp-samples
for spec in "red:5" "blue:23" "green:72" "orange:145" "purple:8"; do
    color=${spec%:*}; dur=${spec#*:}
    ffmpeg -y -f lavfi -i "color=c=${color}:s=480x270:d=${dur}" \
           -c:v h264 -pix_fmt yuv420p /tmp/vp-samples/${color}.mov 2>&1 | tail -1
done
xcrun simctl addmedia booted /tmp/vp-samples/*.mov
```

## 確認手順

修正内容に応じて該当する項目だけ確認する。

### 一覧画面

- アプリ起動 → 初回は写真アクセス許可ダイアログが出ること
- 「フルアクセスを許可」後、5列グリッドで動画が表示される (新しい順)
- 各セル右下に長さラベル `0:08` / `1:23` / `2:25` 等の表示
- 動画ゼロ件のときは「動画がありません」プレースホルダ
- 権限拒否時は「写真へのアクセスが必要です」+ 設定を開くボタン

### 再生画面 (動画タップで遷移)

確認したい挙動:

- 自動再生開始 (一覧で動画をタップ → 黒背景で全画面表示)
- シングルタップ → コントロールオーバーレイ表示
- 3 秒経過 → オーバーレイが自動で消える
- 中央の ▶/⏸ ボタンで再生/一時停止
- 上部 × ボタンで一覧に戻る

### ジェスチャー

- 画面右半分をダブルタップ → 10秒進む + 「+10秒」フィードバック (右側)
- 画面左半分をダブルタップ → 10秒戻る + 「-10秒」フィードバック (左側)
- ダブルタップ時はオーバーレイ表示状態が変わらないこと

### シークバー

- ドラッグでシーク
- ドラッグ中は時刻ラベルが更新される
- ドラッグ離した位置で再生継続

### 再生速度

- 上部右の速度メニュー (`1x` などのキャプセル) をタップ
- 0.75 / 1 / 1.5 / 2 倍速の選択肢が出る
- 選択するとボタンのラベルが切り替わる
- 速度変更時に音声ピッチが不自然にならない (`audioTimePitchAlgorithm = .spectral`)

### 向き切り替え

シミュレータでは縦向きロックの実機挙動を確認できないため、最終確認は iPhone 実機で行う。

- 動画を開く → 画面タップでコントロールオーバーレイを表示
- 右下の四角い向き切り替えボタンが表示されること
- iPhone の縦向きロック OFF で、右下ボタン → 横向き固定 → もう一度右下ボタン → 縦向き固定になること
- iPhone の縦向きロック ON で、右下ボタン → 横向き固定 → もう一度右下ボタン → 縦向き固定になること
- 横向き中に上部 × ボタンで閉じると、一覧画面が最初から縦向きで表示されること
- 横向き中に編集ボタンを押すと、編集画面が最初から縦向きで表示されること

## スクリーンショット

```sh
mise run shot   # /tmp/vid.png に保存
```

シミュレータ内のタップを CLI から自動化する手段はない (osascript はアクセシビリティ権限が必要)。
タップ後の状態確認はユーザー手動 → AI 側でスクショ確認の流れで行う。

## 実機への転送

1. Xcode で `Vid.xcodeproj` を開く
2. プロジェクト navigator → Vid target → Signing & Capabilities
3. "Automatically manage signing" を ON
4. Team で自分の Personal Team (無料 Apple ID) を選択
5. Bundle ID が他人と衝突して signing 失敗する場合は `project.yml` の `PRODUCT_BUNDLE_IDENTIFIER` をユニークなものに変更 (例: `com.d0ne1s.vid.tsubasa`) → `mise run gen` で再生成
6. iPhone を USB 接続 → Xcode の destination で選択 → ⌘R で実行
7. 初回はデバイス側で「設定 → 一般 → VPN とデバイス管理 → 開発元を信頼」が必要
8. Personal Team でビルドしたアプリは 7 日後に失効する。再起動するなら Xcode から再インストールする

## トラブルシューティング

### `xcodebuild: error: Unable to find a destination matching ...`

Xcode 26.5 が iOS 26.5 simulator runtime を期待するが 26.4 しか入っていないために起こる。
`-destination` を指定せず、`-sdk iphonesimulator` だけで build する (`.mise.toml` の build タスクはそうしてある)。

### シミュレータに動画が表示されない

- 写真アクセス権限を許可したか確認
- `xcrun simctl addmedia booted <file.mov>` で投入する (上記セットアップ参照)
- シミュレータデフォルトの 6 件は静止画なので動画一覧には出ない
