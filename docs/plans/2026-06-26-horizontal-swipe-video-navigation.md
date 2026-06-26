# 左右スワイプで前後の動画へ移動

## 概要・やりたいこと

動画再生画面で、再生中または一時停止中に左右へスワイプしたとき、ライブラリ内の前後の動画へ移動できるようにする。

プレイヤーが縦向きで表示されている場合は縦向きのまま、横向きで表示されている場合は横向きのまま、同じ全画面プレイヤー内で次の動画へ切り替える。閉じる・編集へ進むなど、一覧や別画面へ遷移する経路では既存通り portrait へ戻す。

## 前提・わかっていること

- 現在の `VideoLibraryView` は `selectedVideo: VideoAsset?` だけを `VideoPlayerView(video:)` に渡しており、プレイヤーは前後の動画や一覧の並び順を知らない。
- `PhotoLibraryService.fetchVideos()` は `creationDate` 昇順で動画を取得している。古い動画が配列の前、新しい動画が配列の後になる。
- `VideoPlayerViewModel.video` は `let` で、`setUp()` も初期動画を1回読み込む前提になっている。
- プレイヤー表示開始時は `VideoPlayerView.task` で `orientationManager.enterPlayer()` が呼ばれ、portrait 初期化される。
- スワイプ時に `fullScreenCover(item:)` の item identity を更新すると `VideoPlayerView` が再生成され、`enterPlayer()` が再実行されて portrait に戻るリスクがある。presentation identity と現在動画は分けて管理する。
- 向き切り替えは `OrientationManager` が `allowedMask` / `requestedLock` / `actualInterfaceOrientation` を管理し、`requestGeometryUpdate` で画面全体の向きを変える方式になっている。
- 横向き中に閉じる・編集へ入る場合は `requestPortraitBeforeTransition()` を待ってから遷移する既存設計がある。
- 既存ジェスチャーは `PlayerGestureLayer` の UIKit recognizer に集約されている。シングルタップ、ダブルタップ、左右長押し、親 `VideoPlayerView` の下スワイプ dismiss が共存している。
- `AVPlayerLayer.videoGravity` は `.resizeAspect` なので、動画自体が縦向きでも横向きでも、現在の画面向きに合わせて自然に収まる見込み。
- この環境では `xcode-select` が Command Line Tools を向いており、`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 指定で Xcode は使える。ただし Simulator runtime が 0 件のため、現状の `mise run build` は Asset Catalog の `No available simulator runtimes for platform iphonesimulator` で失敗する。

## 仕様決定・実装方針

- 左スワイプ（指を左へ払う / `translation.width < 0`）で配列の次へ移動する。
  - 現在の配列順は古い → 新しいなので、左スワイプは「より新しい動画」。
- 右スワイプ（指を右へ払う / `translation.width > 0`）で配列の前へ移動する。
  - 現在の配列順では、右スワイプは「より古い動画」。
- 先頭・末尾ではループしない。
  - 移動できない場合は動画を切り替えず、軽い端フィードバックだけ返す。
- 切り替え演出は最小実装から始める。
  - スワイプ完了後に動画を差し替え、ドラッグ追従の横スライド演出は必要になったら追加する。
- 編集・削除は常に「スワイプ後の現在動画」を対象にする。
  - `VideoPlayerViewModel.video` を更新可能にしたあと、`VideoEditorView(video:)` と `deleteVideo()` が現在動画を参照していることを確認する。

## 実装計画

### 事前準備 [人間👨‍💻]

- [x] 左右スワイプの方向対応を決める。
- [x] 先頭・末尾でループするか、端で止めるかを決める。
- [ ] 実機または Simulator で動画を複数本再生できる状態にしておく。

### Phase 1: プレイヤーへ一覧コンテキストを渡す [AI🤖]

- [x] `VideoLibraryView` の presentation state は、現在動画そのものではなく stable な `PlayerSession: Identifiable` として持つ。
- [x] `PlayerSession` には session 固有 id、初期動画 id、初期 index を持たせ、`fullScreenCover(item:)` の identity はスワイプ中に変えない。
- [x] プレイヤー内の現在動画は `currentVideoID` / `currentIndex` として `PlayerSession` とは別に管理する。
- [x] `fullScreenCover` には現在の `videos` 配列、初期 index、初期動画 id を渡す。スワイプ時は親の presentation item を更新せず、プレイヤー内 state だけを更新する。
- [x] 親から渡された `videos` が更新されたら、`VideoPlayerView` 内で `currentVideoID` を基準に `currentIndex` を再同期する。ただし `PlayerSession.id` は維持し、cover の再生成を避ける。
- [x] `videos` 更新時は `videos.map(\.id)` のような stable な id 配列を `onChange` 対象にし、`VideoAsset` / `PHAsset` 全体の比較に依存しない。
- [x] 現在動画が削除・権限変更などで一覧から消えた場合は、横向き中なら portrait settle を待ってプレイヤーを閉じる。
- [x] 現在動画以外が削除・追加された場合は、現在動画を維持したまま前後移動先だけ再計算する。

### Phase 2: 動画差し替え可能な ViewModel にする [AI🤖]

- [x] `VideoPlayerViewModel.video` を現在動画として更新可能にし、初期読み込み成功後とスワイプ先読み込み成功後だけ更新する。
- [x] `setUp()` を初期化専用から、任意の `VideoAsset` を読み込める `load(video:autoPlay:)` 系の API に分ける。
- [x] 動画切り替え前に `pause()`、一時早送り・巻き戻し状態、overlay hide task、seek feedback を整理する。
- [x] 古い `timeObserver`、`endObserver`、`rateObservation` を解除してから新しい `AVPlayerItem` を入れる。
- [x] `PHImageManager.requestAVAsset` の `PHImageRequestID` を保持し、次の load 開始時と `deinit` で `PHImageManager.default().cancelImageRequest(...)` を呼ぶ。
- [x] `PHImageManager.requestAVAsset` の async wrapper は、キャンセル時も continuation が必ず resume される形にする。cancel 後に callback が遅れて届く可能性は generation token で無視する。
- [x] `PHImageManager.requestAVAsset` の非同期結果が前後しないよう、request cancellation に加えて generation token などで最新リクエストだけを反映する。
- [x] スワイプ先の `AVAsset` 取得に成功するまでは、`video` と `player.currentItem` を旧動画のまま維持する。
- [x] 切り替え直前に再生中だった場合は新しい動画も `playImmediately(atRate: playbackRate)` で再生し、一時停止中だった場合は停止したまま先頭に置く。
- [x] スワイプ先の読み込み失敗時は旧動画を維持し、切り替え前に再生中だった場合は可能なら旧動画の再生状態へ戻す。
- [x] 初期動画の読み込み失敗は既存の error overlay を使う。スワイプ先の読み込み失敗は旧動画を維持し、短い失敗表示だけを出して controls / gesture / 向き切り替えを残す。
- [x] スワイプ先の読み込み中は `isLoadingNextVideo` のような状態を持ち、連続入力を抑制するか、最新リクエストだけに集約する。

### Phase 3: 左右スワイプジェスチャーを追加する [AI🤖]

- [x] `PlayerGestureLayer` に horizontal pan recognizer を追加する。
- [x] pan recognizer は `gestureRecognizerShouldBegin` 相当で方向判定し、横方向優勢の場合だけ開始する。
- [x] 縦方向優勢の場合は horizontal 側で state を変更せず、親 `VideoPlayerView` の下スワイプ dismiss に任せる。
- [x] horizontal pan の方向判定は左右どちらの `PlayerGestureLayer` から始まっても同じにし、`isRightSide` は double tap / long press の左右判定にだけ使う。
- [x] 動画読み込み中、orientation request pending 中、close / editor 遷移準備中は horizontal pan を開始しない。
- [x] 横方向の移動量・速度が閾値を超えた場合だけ前後動画へ移動する。
- [x] 下スワイプ dismiss と競合しないよう、縦方向優勢のドラッグは既存 dismiss 側に任せる。
- [x] horizontal pan が開始したら `endTemporaryLongPressPlayback()` を呼び、長押し早送り・巻き戻しが残らないようにする。
- [x] ダブルタップ seek、長押し早送り・巻き戻し、シングルタップ overlay と誤爆しないよう delegate 条件を調整する。pan 中は tap 系を発火させない。
- [x] スワイプ開始時に一時長押し再生状態が残っていた場合は確実に解除する。
- [x] 端の動画で移動できない場合のフィードバックを必要最小限で入れる。

### Phase 4: 向きと遷移の維持を確認する [AI🤖]

- [x] 前後動画への切り替えでは `orientationManager.enterPlayer()` や `requestPortraitBeforeTransition()` を呼ばない。
- [x] スワイプ時に `fullScreenCover(item:)` の item identity が変わらず、`VideoPlayerView` が再生成されないことを確認する。
- [ ] portrait 中にスワイプしても portrait のまま差し替わることを確認する。
- [ ] landscape 中にスワイプしても landscape のまま差し替わることを確認する。
- [ ] 切り替え後も右下の向き切り替えボタンが現在の `actualInterfaceOrientation` に基づいて表示されることを確認する。
- [ ] 横向き中の閉じる、編集、削除後 close、現在動画が外部削除された場合の close は既存通り portrait settle を待ってから遷移することを確認する。
- [x] スワイプ後に編集へ入った場合、編集画面に渡る動画がスワイプ後の現在動画であることを確認する。
- [x] スワイプ後に削除した場合、削除対象がスワイプ後の現在動画であることを確認する。

### Phase 5: 表示・操作感を調整する [AI🤖]

- [ ] 最小実装で操作感が十分か確認する。
- [x] 必要ならドラッグ中の横方向 offset とスナップバック / 切り替えアニメーションを追加する。
- [ ] 縦動画・横動画の両方で、切り替え直後の黒背景、ローディング、controls overlay の見え方を確認する。
- [ ] 連続スワイプ中に古い動画や古い observer が残らないことを確認する。
- [x] スワイプ先読み込み失敗時に旧動画・旧向き・既存 controls が維持されることを確認する。

### Phase 6: ビルドと確認 [AI🤖]

- [x] ~~XcodeGen 設定を変更した場合は `mise run gen` を実行する。~~
- [x] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer mise run build` でビルドを確認する。
- [x] Simulator runtime が無い環境で同じ失敗が出る場合は、失敗理由が runtime / Asset Catalog 由来であることを記録する。
- [ ] 可能なら Simulator または実機で、動画を複数本入れた状態で前後移動を確認する。
- [x] 再利用可能な確認手順を `VERIFY.md` に追記する。

### 動作確認 [人間👨‍💻]

- [ ] 動画再生中に左右スワイプして、前後の動画へ移動できることを確認する。
- [ ] 一時停止中に左右スワイプして、次の動画も停止状態で開くことを確認する。
- [ ] portrait 表示中にスワイプして、portrait のまま動画だけ切り替わることを確認する。
- [ ] landscape 表示中にスワイプして、landscape のまま動画だけ切り替わることを確認する。
- [ ] シングルタップ overlay、左右ダブルタップ seek、左右長押し、下スワイプ dismiss が既存通り動くことを確認する。
- [ ] 先頭・末尾の動画でスワイプしたとき、決めた仕様通りに動くことを確認する。
- [ ] 横向き中に閉じる・編集へ入る・削除後に閉じる操作で、一覧や編集画面が最初から portrait で表示されることを確認する。

## ログ

### 試したこと・わかったこと

- 2026-06-26: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer mise run build` は exit 65。失敗理由は `No available simulator runtimes for platform iphonesimulator. SimServiceContext supportedRuntimes=[]` で、既知の Simulator runtime / Asset Catalog 由来。
- 2026-06-26: 左右スワイプ実装後も同じ build を2回実行。SwiftDriver は走り、失敗は `CompileAssetCatalogVariant` の `No available simulator runtimes for platform iphonesimulator. SimServiceContext supportedRuntimes=[]` に限定された。
- 2026-06-26: review 指摘対応。`UIPanGestureRecognizer.translation(in:)` は `CGPoint` なので `x/y` 参照に修正し、delegate の `return true` 漏れも修正。スワイプ遷移 Task を `@State` で保持し、dismiss 開始時と `onDisappear` で Task と `PHImageManager` request を明示キャンセルするようにした。
- 2026-06-26: 追加 review 指摘対応。dismiss gesture の `onEnded` にも縦方向優勢判定を入れ、斜め下の横スワイプで `predictedEndTranslation.height` だけを理由に閉じないようにした。次動画ロード中は gesture recognizer と dismiss gesture を無効化し、hit-test 可能な loading overlay で controls の edit/delete も塞ぐようにした。`swiftc -typecheck` は warning のみで pass。
- 2026-06-26: 実機確認で最小実装の切り替わりが硬いことがわかったため、横 pan の changed/ended/cancelled を SwiftUI 側へ渡し、ドラッグ中の横方向 offset、端の抵抗、閾値未満のスナップバック、確定時の slide-out / slide-in を追加した。実機向け `xcodebuild`、`devicectl install app`、`devicectl process launch` は成功。

### 方針変更

- 2026-06-26: review を反映し、`fullScreenCover` の presentation identity と現在動画を分離する方針に変更した。スワイプ中は stable な `PlayerSession.id` を維持し、プレイヤー内の `currentVideoID` / `currentIndex` だけを更新する。
- 2026-06-26: スワイプ先の読み込み失敗は error screen へ遷移せず、旧動画を維持して短い失敗表示を出す方針に変更した。初期読み込み失敗だけ既存 error overlay を使う。
- 2026-06-26: 連続スワイプ時の負荷と stale result を抑えるため、`PHImageRequestID` の cancellation と generation token の両方を使う方針を追加した。
- 2026-06-26: UIKit pan と SwiftUI dismiss gesture の競合を避けるため、horizontal pan は `shouldBegin` で横優勢のときだけ開始し、loading / orientation pending / transition 準備中は開始しない方針を追加した。
- 2026-06-26: 未決だった操作仕様を、左スワイプで次（より新しい動画）、右スワイプで前（より古い動画）、端ではループせず軽いフィードバックに確定した。
- 2026-06-26: 親の `videos` 更新時は `VideoPlayerView` 内で現在動画 id を基準に index を再同期し、現在動画が消えた場合は portrait settle 後に閉じる方針にした。
- 2026-06-26: スワイプ先の読み込みは `AVAsset` 取得成功まで旧 `video` / `player.currentItem` を維持し、失敗時に旧動画へ戻れる形にした。
- 2026-06-26: XcodeGen 設定は変更していないため `mise run gen` は不要としてスキップした。
