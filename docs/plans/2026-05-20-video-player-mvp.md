# 動画プレイヤーアプリ MVP 実装

## 概要・やりたいこと

iPhone の写真アプリに保存されている動画を、YouTube ライクな操作感で快適に再生するための個人用 iOS アプリ。標準写真アプリの動画プレイヤーが使いにくい問題を解消することが目的。

将来的に動画編集機能（カット・トリミング・書き出し）を追加する前提で、MVP では閲覧・再生・基本ジェスチャー操作までを実装する。

仕様書: 会話履歴の「動画プレイヤーアプリ 仕様書 (MVP)」を参照。

## 前提・わかっていること

### 技術スタック
- 言語: Swift 5.10+
- UI: SwiftUI メイン (`AVPlayer` のみ `UIViewRepresentable` でラップ)
- 動画再生: AVFoundation / AVKit
- フォトライブラリ: PhotoKit (`PHAsset`, `PHCachingImageManager`)
- アーキテクチャ: MVVM (`@Observable` を使う)
- 外部ライブラリ: なし

### プロジェクト構成
- XcodeGen を使う (`project.yml` を source-of-truth、`.xcodeproj` は生成物で gitignore)
- ビルド・実行は CLI で完結させる方針 (`xcodebuild` / `xcrun simctl`)
- ディレクトリ構成は仕様書セクション 11 に従う

### 動作確認方針
- 開発中はシミュレータで確認（写真アプリにサンプル動画を流し込む）
- 最終確認のみ実機（本人の iPhone）を想定。実機転送は手動で行う

### スコープ
- MVP の受け入れ基準（仕様書セクション 12）をすべて満たすこと
- Phase 2 以降の機能（編集・PiP・AirPlay 等）は実装しない
- 横画面対応は MVP では縦のみで OK（仕様書許容範囲）
- iPad 対応は将来検討（MVP は iPhone のみ）

### 制約
- iOS 17 以降 / iOS 18 最適化
- `NSPhotoLibraryUsageDescription` を `.readWrite` で要求
- 拡張性: 将来の編集機能のため `AVAsset` / `PHAsset` 抽象を保つ（URL 直渡しを避ける）

## 実装計画

### 事前準備 [人間👨‍💻]
- [ ] Xcode が最新（少なくとも iOS 17 SDK 含む）であることを確認する
- [ ] XcodeGen がインストール済みか確認（`mise where xcodegen` または `which xcodegen`）。なければ Brewfile 経由で入れる
- [ ] シミュレータの「写真」アプリにテスト用動画を 5〜10 本流し込む（後述の手順は Phase 1 完了時に提供する）

### Phase 1: プロジェクトのセットアップ [AI🤖]
- [x] `project.yml` を作成（target = `VideoPlayer`、platform = iOS 17.0、bundle id 仮置き、SwiftUI App ライフサイクル）
- [x] ディレクトリ構成を仕様書セクション 11 に従って作成
- [x] `Info.plist` 相当の設定を `project.yml` の `infoPlist` セクションに記載（`NSPhotoLibraryUsageDescription` 等）
- [x] `App/VideoPlayerApp.swift` を仮実装（ContentView に「Hello」程度）
- [x] `.gitignore` を作成（`.xcodeproj/`、`DerivedData/`、`.build/`、`*.xcuserdata` 等）
- [x] `xcodegen generate` でプロジェクト生成 → `xcodebuild` で空ビルドが通ることを確認
- [x] `.mise.toml` に `build` / `run` / `gen` などのタスクをまとめる（description は日本語）

### Phase 1 後の確認 [人間👨‍💻]
- [x] 空アプリがシミュレータで起動することを確認する → スクリーンショット撮影済み

### Phase 2: 動画一覧画面（コア機能） [AI🤖]
- [x] `Core/VideoAsset.swift`: `PHAsset` をラップした struct（id, duration, creationDate, asset 参照）
- [x] `Core/TimeFormatter.swift`: 秒 → `mm:ss` / `h:mm:ss` 変換ユーティリティ
- [x] `Core/PhotoLibraryService.swift`: 権限要求、`PHAsset.fetchAssets(with: .video)`、`PHCachingImageManager` 管理
- [x] `Features/Library/VideoLibraryViewModel.swift`: `@Observable` で `videos`、`authorizationStatus`、`load()`
- [x] `Features/Library/VideoThumbnailCell.swift`: サムネイル + 右下に長さラベル
- [x] `Features/Library/VideoLibraryView.swift`: `LazyVGrid` 5列、間隔 2pt、正方形セル
- [x] 空状態 / 権限拒否時のプレースホルダ表示
- [~] `PHCachingImageManager.startCachingImages` / `stopCaching` をスクロール状態に応じて呼ぶ（service には用意済み、ViewModel からの呼び出しは Phase 5 で）
- [x] ビルドが通り、シミュレータで動画一覧がスクロール可能であることを確認

### Phase 2 後の確認 [人間👨‍💻]
- [x] シミュレータの写真アプリに動画があるとき、一覧グリッドに正しく表示されるか目視確認（ffmpeg 生成のサンプル動画5本でグリッドが表示された）
- [ ] スクロールがカクつかないか確認（60fps 目安）→ Phase 5 でキャッシュ実装後に確認

### Phase 3: 動画再生画面（基本機能） [AI🤖]
- [x] `Features/Player/AVPlayerViewRepresentable.swift`: `AVPlayer` + `AVPlayerLayer` を SwiftUI に統合
- [x] `Features/Player/VideoPlayerViewModel.swift`: `@Observable` で player 管理、`addPeriodicTimeObserver`、deinit 処理
- [x] `Features/Player/VideoPlayerView.swift`: 黒背景、動画中央配置、ステータスバー非表示
- [x] 一覧 → 再生の遷移（`fullScreenCover` を採用）
- [x] 自動再生、終了時の一時停止
- [x] 音声ピッチ維持（`audioTimePitchAlgorithm = .spectral`）

### Phase 4: コントロール UI とジェスチャー [AI🤖]
- [x] `Features/Player/PlayerControlsOverlay.swift`:
  - 上部バー（× ボタン、再生速度メニュー）
  - 中央の再生/一時停止ボタン
  - 下部バー（現在時刻、シークバー、残り時間）
- [x] シングルタップでオーバーレイ表示トグル、3 秒で自動消去
- [x] `Features/Player/PlayerGestureLayer.swift`: 画面左右半分で `TapGesture(count:)` を分けて判定
- [x] 画面右半分ダブルタップ: 10 秒進む + 視覚フィードバック (`SeekFeedbackView`)
- [x] 画面左半分ダブルタップ: 10 秒戻る + 視覚フィードバック
- [x] シークバードラッグ: リアルタイム反映、`onEditingChanged` で表示制御
- [x] 再生速度切替（0.75 / 1.0 / 1.5 / 2.0x の 4 段階）、現在の速度を上部バーに表示

### Phase 5: 仕上げ・エラーハンドリング [AI🤖]
- [x] iCloud 上の未ダウンロード動画への対応（`PHImageRequestOptions` / `PHVideoRequestOptions.isNetworkAccessAllowed = true` 設定済み）
- [x] 動画読み込み失敗時のエラー表示と戻る導線 (`VideoPlayerView.errorOverlay`)
- [~] パフォーマンス計測（実機 + 大量動画があるとき確認。MVP では未実施）
- [x] `VERIFY.md` を作成し、動作確認手順を記録する
- [x] アプリ名を「Vid」に変更、bundle id を `com.d0ne1s.vid` に変更
- [x] 実機ビルド準備: `CODE_SIGN_STYLE: Automatic` を設定、Personal Team での署名手順を VERIFY.md に記載
- [x] 初回 git コミット

### 動作確認 [人間👨‍💻]
- [x] シミュレータでの一通りの動作確認 (一覧 / 再生 / ジェスチャー / 速度切替)
- [x] 実機 (iPhone Air iOS 26.4.2) での動作確認
- [ ] 仕様書セクション 12 の受け入れ基準 12 項目を一つずつチェック
  - [ ] 起動時のフォトライブラリ権限ダイアログ
  - [ ] 5 列グリッド、新しい順
  - [ ] セルに長さ表示
  - [ ] セルタップで再生画面、自動再生
  - [ ] シングルタップでコントロール表示/非表示、3 秒で消える
  - [ ] 右半分ダブルタップで 10 秒進む（視覚フィードバック）
  - [ ] 左半分ダブルタップで 10 秒戻る（視覚フィードバック）
  - [ ] シークバーで任意位置移動
  - [ ] 現在時刻と総時間の正確表示
  - [ ] 6 段階の速度切替
  - [ ] 速度変更時の音声ピッチ維持
  - [ ] 閉じるボタンで一覧へ戻る
  - [ ] 一覧スクロール 60fps

## ログ

### 試したこと・わかったこと
- **Xcode 26.5 + iOS 26.4 simulator runtime のミスマッチ**: Xcode 26.5 の SDK は iOS 26.5 だが、`xcrun simctl runtime list` で利用可能なのは iOS 26.4 のみ。`-destination 'platform=iOS Simulator,name=iPhone 17'` だと "iOS 26.5 is not installed" で destination が見つからない。
  - **回避策**: ビルド時は `-destination 'generic/platform=iOS Simulator'` を使う。インストール・起動は `xcrun simctl install booted` / `launch booted` で対応。これで Xcode 26.5 SDK でビルドしたバイナリを iOS 26.4 シミュレータで動かせる。
- **XcodeGen の scheme 生成**: `schemes:` セクションを明示的に書かないと `.xcscheme` ファイルが生成されず、xcodebuild が「Supported platforms ... is empty」エラーになる。`project.yml` で schemes を明示することで shared scheme として書き出される。
- **LazyVGrid のセル高さ問題**: `LazyVGrid` の cell に `.frame(height:)` や `.aspectRatio(1, .fit)` を掛けても期待通り square にならないケースがある。`Color` のような intrinsic size のないビューが ZStack の背景にあると、ZStack の自然な高さが label のサイズに引っ張られて潰れる。**回避策**: `Color.foo.aspectRatio(1, contentMode: .fill).overlay { ... }` のように、サイズを持つ base view から始めて overlay で上に重ねる構成にする。
- **シミュレータへのサンプル動画投入**: `ffmpeg -f lavfi -i "color=c=red:s=480x270:d=5"` で単色動画を生成、`xcrun simctl addmedia booted <file...>` で複数同時投入できる。

### 方針変更
- **再生速度オプションを 6 段階 → 4 段階に変更** (2026-05-20): ユーザー確認で `0.75 / 1.0 / 1.5 / 2.0x` の 4 種類に絞った。仕様書記載の `0.5x` と `1.25x` は削除。理由: 本人が使わないため。
- **アプリ名を VideoPlayer → Vid に変更** (2026-05-20): bundle id も `com.d0ne1s.VideoPlayer` → `com.d0ne1s.vid` に。理由: 短くて簡潔な名前にしたいというユーザー要望。フォルダ・型 (`VideoPlayerApp` → `VidApp`) も含めてフルリネーム済み。
