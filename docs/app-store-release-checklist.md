# App Store 公開チェックリスト

作成日: 2026-06-26

凡例: 😀 は AI だけでは自動化しにくく、人の判断、実機・目視確認、アカウント操作、法務/審査回答が必要になりやすいタスク。

## 前提

- Apple Developer Program 登録済み
- iOS のみ公開
- 外部 TestFlight ベータは挟まない
- 価格は無料
- 公開地域は日本のみ
- 対応言語は日本語のみ
- 対象アプリ: `Vid`
- Bundle ID: `com.d0ne1s.vid`
- Target: iPhone only / iOS 17.0+
- 現在のアプリバージョン: `1.0.0` / build `1`

## 全体見積もり

外部 TestFlight を挟まない場合、実作業は 1〜2 日程度。Apple 審査待ちは通常 1〜2 日を見込む。

| フェーズ | 目安 | 主な作業 |
| --- | ---: | --- |
| リリース前の実装・品質確認 | 半日〜1.5日 | 署名、権限文言、実機QA、クラッシュ確認 |
| App Store Connect 準備 | 2〜6時間 | アプリ情報、プライバシー、スクリーンショット、価格/地域 |
| アーカイブ・アップロード | 30分〜2時間 | Release archive 作成、App Store Connect 反映待ち |
| App Review 提出 | 30分〜1時間 | 審査情報、輸出コンプライアンス、提出 |
| Apple 審査待ち | 1〜2日目安 | リジェクト時は修正・再提出 |

## 1. 公開方針を決める

- [x] 😀 App Store 上の正式アプリ名を決める
  - App Store 正式名: `Vid - 動画プレイヤー`
  - ホーム画面の表示名は `Vid` のままにする
  - `Vid` 単体は日本 App Store に `vID` が存在するため、名前予約で弾かれる可能性がある: https://apps.apple.com/jp/app/vid/id1537652843
- [x] 😀 価格を決める
  - 無料
  - 税務/銀行情報は基本不要
- [x] 😀 公開地域を決める
  - 日本のみ
- [x] 😀 対応言語を決める
  - 日本語のみ
  - App Store メタデータ、スクリーンショット、サポートページ、Privacy Policy も日本語で揃える
- [x] 😀 サポート窓口を決める
  - サポートメール: `nyshk97+vid@gmail.com`
- [x] 😀 Privacy Policy を置く URL を決める
  - iOS アプリは App Store Connect で Privacy Policy URL が必須
  - Privacy Policy URL: https://github.com/nyshk97/video-player/blob/main/PRIVACY_POLICY.md
  - Support URL: https://github.com/nyshk97/video-player/blob/main/SUPPORT.md

## 2. コード・プロジェクト設定をリリース向けに整える

- [x] 😀 `project.yml` のバージョンを公開版にする
  - `MARKETING_VERSION`: 初回公開なら `1.0.0` にするか、ベータ感を残して `0.1.0` のまま出すか決める
  - `CURRENT_PROJECT_VERSION`: App Store Connect に上げるたびに増やす
  - 初回公開版として `MARKETING_VERSION: "1.0.0"` / `CURRENT_PROJECT_VERSION: "1"` に設定
- [ ] 😀 `PRODUCT_BUNDLE_IDENTIFIER` が Apple Developer の App ID と一致していることを確認する
  - 現在: `com.d0ne1s.vid`
  - ローカル `project.yml` の値は確認済み。Apple Developer / App Store Connect 側の App ID 作成時に一致確認する
- [x] `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` を実態に合わせる
  - 現在は「保存されている動画を一覧・再生するため」
  - このアプリは削除・トリミング保存も行うため、審査向けには例のように広げる

```yaml
INFOPLIST_KEY_NSPhotoLibraryUsageDescription: "保存されている動画の一覧表示、再生、削除、トリミング保存のために写真ライブラリへのアクセス許可が必要です。"
```

- [x] 😀 アプリアイコンを最終確認する
  - `Vid/Resources/Assets.xcassets/AppIcon.appiconset/`
  - iOS のホーム画面で小サイズでも識別できるか確認する
  - 配色は緑背景 + 黄色の再生マーク
  - 1024x1024 / RGB / alpha なしを確認済み
  - App Store validation の透明アイコン回避のため、透明ピクセルを含む tinted 変種は外した
- [x] 起動画面が自動生成で問題ないか確認する
  - 現在: `INFOPLIST_KEY_UILaunchScreen_Generation: YES`
  - `xcodebuild -showBuildSettings` で `INFOPLIST_KEY_UILaunchScreen_Generation = YES` を確認済み
- [x] 😀 iPad 非対応でよいか最終確認する
  - 現在: `TARGETED_DEVICE_FAMILY: "1"`
  - 方針: iPad は非対応のまま

## 3. Release ビルドを作る前のローカル確認

`VERIFY.md` のうち、公開前に最低限必要な範囲だけ確認する。

- [x] XcodeGen 再生成

```sh
mise run gen
```

- [x] Simulator ビルド

```sh
mise run build
```

- [x] Simulator 起動確認

```sh
mise run boot
mise run run
```

- [x] 😀 サンプル動画を入れて一覧・再生を確認する
  - QA 用 Simulator に単色動画 3 本を投入し、一覧表示は確認済み
  - 再生確認は手動操作で確認済み
- [x] 😀 写真権限の初回許可、拒否時の表示、設定遷移を確認する
  - 初回写真権限プロンプトと用途文言は確認済み
  - 拒否時の表示、設定遷移は手動操作で確認済み
- [x] 😀 動画が 0 件の状態を確認する
  - QA 用の新規 Simulator で `動画がありません` 表示を確認済み
- [x] 😀 複数動画で左右スワイプ移動を確認する
  - 手動操作で確認済み
- [x] 😀 再生、一時停止、シーク、倍速、長押し 2x、巻き戻しを確認する
  - 手動操作で確認済み
- [x] 😀 削除操作を確認する
  - 手動操作で確認済み
- [x] 😀 トリミング保存を確認する
  - 手動操作で確認済み
- [x] 😀 実機で縦向きロック ON/OFF の向き切り替えを確認する
  - 手動操作で確認済み
- [x] 😀 実機で大量動画ライブラリの初期表示速度を確認する
  - 手動操作で確認済み
- [x] 😀 実機でメモリ落ちや極端な発熱がないか確認する
  - 手動操作で確認済み

## 4. App Store Connect にアプリを作成する

App Store Connect の `My Apps` で新規アプリを作成する。

- [ ] 😀 Platform: iOS
- [ ] 😀 Name: 決定したアプリ名
  - `Vid - 動画プレイヤー`
- [ ] 😀 Primary Language: Japanese
- [ ] 😀 Bundle ID: `com.d0ne1s.vid`
- [ ] 😀 SKU: 任意の内部管理ID
  - `vid-ios`
- [ ] 😀 User Access: 必要なら Full Access
  - 基本は Full Access で作成する

## 5. App Store メタデータを用意する

初回提出に必要な日本語テキストを用意する。

- [ ] Subtitle
- [ ] Description
- [ ] Keywords
- [ ] Promotional Text
- [x] Support URL
  - https://github.com/nyshk97/video-player/blob/main/SUPPORT.md
- [ ] Marketing URL
  - 任意。なければ空でよい
- [ ] 😀 Copyright
- [ ] 😀 Category
  - 候補: `Photo & Video`
- [ ] 😀 Age Rating
  - ユーザー生成動画を扱うが、アプリ自体は成人向けコンテンツを提供しない想定で回答する
- [ ] 😀 Review Notes
  - ログイン不要
  - 写真ライブラリ権限が必要
  - 審査用に、端末またはシミュレータの写真ライブラリへ動画を追加して確認してほしい旨を書く

審査メモ例:

```text
このアプリは、ユーザーの写真ライブラリに保存されている動画を再生・編集するローカルアプリです。
ログインは不要です。
確認時は写真ライブラリへのアクセスを許可し、写真ライブラリ内の動画を使用してください。
主な機能は、動画一覧、再生、シーク、再生速度変更、スワイプでの動画移動、削除、トリミング保存です。
```

## 6. スクリーンショットを作る

iPhone only なので、iPhone 用スクリーンショットを用意する。App Store Connect には各ローカライズごとに最大 10 枚まで載せられる。

最低限の構成:

- [ ] 😀 ライブラリ一覧
- [ ] 😀 再生画面
- [ ] 😀 コントロール表示中の再生画面
- [ ] 😀 倍速メニュー
- [ ] 😀 トリミング画面

推奨:

- 6.9 インチ iPhone 系のスクリーンショットを優先して作る
- 実機または Simulator のステータスバー、動画サムネイル、権限状態が自然に見えるようにする
- 個人の写真・動画が写らないよう、サンプル動画だけで撮影する

Simulator でのスクリーンショット保存:

```sh
mise run shot
```

## 7. App Privacy を入力する

このアプリは現状、外部通信やサードパーティ SDK が見当たらない。実装がこのままなら App Store Connect の App Privacy は次の方針で入力する。

- [ ] 😀 Privacy Policy URL を入力する
- [ ] 😀 Data Collection は「データを収集しない」を選ぶ
- [ ] 😀 Tracking は行わない
- [ ] 😀 サードパーティ SDK を追加した場合は、SDK の収集データも含めて回答を見直す

注意:

- 写真ライブラリ内の動画へアクセスすることと、開発者がデータを収集することは別
- 端末内だけで処理し、外部送信・分析・広告・クラッシュ収集をしないなら「収集なし」の可能性が高い
- 今後クラッシュレポート、分析、広告、問い合わせフォーム連携などを入れた場合は再判定する

## 8. Pricing and Availability を設定する

- [ ] 😀 価格を Free に設定する
- [ ] 😀 Availability を日本のみに設定する
- [ ] 😀 iPhone apps on Mac / Apple Vision Pro での利用可否を確認する
  - iOS only のつもりでも、Apple Silicon Mac 等への配布設定が表示される場合がある
  - 操作性を確認していないなら、最初は iPhone/iOS に絞る

## 9. 輸出コンプライアンスを確認する

- [ ] 暗号化の利用有無を確認する
  - このアプリの現状では独自暗号化・ネットワーク暗号化の実装は見当たらない
  - OS 標準機能以外で暗号化を使っていない前提なら、その旨で回答する
- [ ] 😀 App Store Connect の Export Compliance 質問に回答する

## 10. Release Archive を作成・アップロードする

Release archive の前に、作業ツリーが意図した状態か確認する。

```sh
git status --short
```

Archive 作成:

```sh
xcodebuild \
  -project Vid.xcodeproj \
  -scheme Vid \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Vid.xcarchive \
  archive
```

アップロードは Xcode Organizer から行うのが一番手戻りが少ない。

1. Xcode で `Vid.xcodeproj` を開く
2. Product > Archive
3. Organizer で作成された archive を選ぶ
4. Distribute App
5. App Store Connect
6. Upload
7. Signing は Apple Distribution / Automatic signing を使う

アップロード後:

- [ ] 😀 App Store Connect の Build に反映されるまで待つ
- [ ] 😀 Processing が完了したら、対象バージョンに build を紐付ける
- [ ] 😀 `CURRENT_PROJECT_VERSION` が過去 build より大きいことを確認する

## 11. App Review に提出する

- [ ] 😀 App Information がすべて埋まっている
- [ ] 😀 Pricing and Availability が設定済み
- [ ] 😀 App Privacy が公開済み
- [ ] 😀 Age Rating が設定済み
- [ ] 😀 Screenshot が登録済み
- [ ] 😀 Build が選択済み
- [ ] 😀 Export Compliance に回答済み
- [ ] 😀 Review Contact Information が最新
- [ ] 😀 Review Notes に写真ライブラリ権限と確認手順を書いた
- [ ] 😀 Submit for Review を実行する

## 12. リジェクト時の対応

リジェクトされたら、まず Resolution Center の文面を保存して原因を分類する。

よくありそうな論点:

- 写真ライブラリ権限の用途説明が不足している
- 削除・編集機能がユーザーにとって破壊的なので確認 UI が不十分
- スクリーンショットや説明文が実機能と一致していない
- アプリ名・メタデータが一般的すぎる、または誤解を招く
- 審査担当が写真ライブラリに動画を用意できず主要機能を確認できない

対応方針:

- [ ] 😀 指摘をそのまま docs に転記する
- [ ] コード修正が必要なら修正する
- [ ] 😀 メタデータ修正で済むなら App Store Connect だけ直す
- [ ] Build を再提出する場合は `CURRENT_PROJECT_VERSION` を増やす
- [ ] 😀 Resolution Center 返信には、修正点と確認手順を短く書く

## 13. 公開後に確認する

- [ ] App Store ページが表示される
- [ ] 😀 自分の端末で App Store からインストールできる
- [ ] 😀 初回起動、写真権限、一覧表示、再生、削除、トリミング保存が動く
- [ ] 😀 App Store Connect の Crashes / Feedback / Ratings and Reviews を確認する
- [ ] 😀 問い合わせ導線が機能している

公開直後の初回アップデート候補:

- [ ] 😀 App Store レビューやクラッシュを見て優先度を決める
- [ ] 😀 日本語レビューや問い合わせを見て説明文・スクリーンショットを改善する
- [ ] 😀 サポートページと Privacy Policy を必要に応じて更新する

## 参考リンク

- [App Store Connect Help](https://developer.apple.com/help/app-store-connect/)
- [App Store Connect](https://developer.apple.com/app-store-connect/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [App Review](https://developer.apple.com/distribute/app-review/)
- [Creating Your Product Page](https://developer.apple.com/app-store/product-page/)
