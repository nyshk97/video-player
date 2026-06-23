# 長押し中の2倍速再生対応

## 概要・やりたいこと

YouTube と同じように、動画再生画面を長押ししている間だけ一時的に 2倍速で再生する。

指を離したら、長押し前の再生速度へ戻す。たとえば通常速度を 1.5x に設定していた場合は、長押し中だけ 2.0x、離したら 1.5x に戻る挙動を目標にする。

既存のシングルタップによるコントロール表示切り替え、左右ダブルタップによる10秒シーク、下スワイプによる閉じる操作は維持する。

## 前提・わかっていること

- `VideoPlayerViewModel` は `AVPlayer` と `playbackRate` を管理しており、`setRate(_:)` で通常の再生速度を変更できる。
- `togglePlayPause()` は再生再開時に `player.playImmediately(atRate: playbackRate)` を使っている。
- 再生中の速度変更は `player.rate` の更新で実現できる。
- `PlayerGestureLayer` が画面全体を左右に分け、シングルタップとダブルタップを処理している。
- `VideoPlayerView` には既に下スワイプ dismiss 用の `DragGesture(minimumDistance: 20)` が `simultaneousGesture` として付いている。
- 長押しによる一時2倍速では、通常速度の設定値 `playbackRate` を上書きしない方針にする。
- 長押し開始時に一時速度へ切り替え、終了時またはキャンセル時に確実に元の速度へ戻す必要がある。
- SwiftUI の `LongPressGesture` は「押している間」の終了検知が単体では扱いづらい可能性があるため、必要なら `DragGesture(minimumDistance: 0)` で press down / up 相当を作る。

## 実装計画

### 事前準備 [人間👨‍💻]

- [ ] 実機またはシミュレータで、動画を1本以上再生できる状態にしておく。

### Phase 1: 一時速度変更の状態を ViewModel に追加する [AI🤖]

- [x] `VideoPlayerViewModel` に一時2倍速中かどうかを表す状態を追加する。
- [x] `wasPlayingBeforeTemporaryFastForward` を追加し、長押し開始時点で実際に再生中だったかを保持する。
- [x] 長押し開始時に呼ぶ `beginTemporaryFastForward()` を追加する。
- [x] 長押し開始時は、`isPlaying` だけに依存せず `player.rate != 0` または `player.timeControlStatus != .paused` と動画終了状態を見て、再生中または再生待機中の場合だけ `wasPlayingBeforeTemporaryFastForward = true` にして `player.rate = 2.0` に切り替える。
- [x] 一時2倍速中でも `playbackRate` は通常速度設定として維持し、速度メニューの表示値を壊さない。
- [x] `setRate(_:)` は、一時2倍速中なら `playbackRate` だけ更新し、`player.rate` は 2.0 のまま維持する。
- [x] 長押し終了時に呼ぶ `endTemporaryFastForward()` を追加し、復元時は古い退避速度ではなく常に最新の `playbackRate` へ戻す。
- [x] `endTemporaryFastForward()` は、`wasPlayingBeforeTemporaryFastForward == true`、ユーザー操作で pause されていない、動画終了していない、という条件を満たす場合だけ `player.rate = playbackRate` に戻す。
- [x] 一時2倍速中に一時停止、動画終了、画面終了が起きても不整合が残らないように guard と状態リセットを入れる。
- [x] `togglePlayPause()`、動画終了 observer、`deleteVideo()`、`onDisappear` など停止系の経路で、一時2倍速状態を解除する必要があるか確認し、必要なら明示的にリセットする。

### Phase 2: 長押しジェスチャーを追加する [AI🤖]

- [x] `PlayerGestureLayer` に長押し中だけ ViewModel の一時2倍速開始/終了を呼ぶ仕組みを追加する。
- [x] ~~第一候補は `LongPressGesture(minimumDuration: 0.35, maximumDistance: 18).sequenced(before: DragGesture(minimumDistance: 0))` を `simultaneousGesture` で既存 tap 領域へ追加する。~~
- [x] ~~sequenced gesture の状態遷移は `@GestureState` と `onChange` を優先して監視し、長押し成立時に `beginTemporaryFastForward()` を一度だけ呼び、`onEnded` または gesture state のリセット時に `endTemporaryFastForward()` を呼ぶ。~~
- [x] シングルタップ、ダブルタップ、長押しが同じ透明領域で競合しないよう、UIKit recognizer に集約し、長押しは threshold 成立後だけ速度変更する。
- [x] 下スワイプ dismiss との競合を避けるため、`maximumDistance` を超える移動は長押しを失敗させ、親の `DragGesture(minimumDistance: 20)` に処理を任せる。
- [x] SwiftUI gesture で cancel / 画面外移動 / dismiss 開始時の終了検知が不安定なら、`UIViewRepresentable` で `UILongPressGestureRecognizer` を置くフォールバックへ切り替える。その場合は `minimumPressDuration = 0.35`、`allowableMovement = 18`、`cancelsTouchesInView = false`、delegate で同時認識を許可する。
- [x] 長押し中に指が離れたとき、画面外へ外れたとき、ジェスチャーがキャンセルされたときに一時2倍速を終了できるようにする。
- [x] 画面外へ外れた判定が必要になった場合は、gesture view の bounds と recognizer location を比較し、範囲外に出た時点で `endTemporaryFastForward()` を呼ぶ。
- [x] 長押し成立時に overlay が不用意に表示/非表示されないよう、既存の `toggleOverlay()` との関係を確認する。

### Phase 3: フィードバック表示を検討・実装する [AI🤖]

- [x] YouTube と同様に長押し中の視覚フィードバックが必要か確認する。初期方針は、最小実装として速度変更のみ入れる。
- [x] 操作感がわかりにくい場合は、長押し中だけ画面上部または中央付近に `2x` の小さな表示を追加する。
- [x] フィードバックを追加する場合は、既存の `SeekFeedbackView` や `PlayerControlsOverlay` と重ならない配置にする。
- [x] フィードバックを追加する場合でも、カード的な大きい説明 UI は避け、短時間操作に合う控えめな表示にする。

### Phase 4: ビルドと自動確認 [AI🤖]

- [x] `mise run build` でビルドが通ることを確認する。
- [x] 必要に応じて `mise run gen` を実行する。ただし XcodeGen の設定変更がなければ不要。
- [x] シミュレータで起動し、プレイヤー画面まで進める状態を確認する。
- [ ] 可能ならシミュレータ操作または手元操作で、長押し開始中だけ速度が 2.0 になり、離すと元の速度へ戻ることを確認する。
- [ ] 速度メニューで 0.75x / 1.0x / 1.5x を選んだ後でも、長押し終了時に選択した速度へ戻ることを確認する。
- [ ] シングルタップ overlay、左右ダブルタップ seek、下スワイプ dismiss、向き切り替えボタンが既存通り動くことを確認する。
- [x] `VERIFY.md` の「再生速度」セクションへ、「1.5x 選択 → 長押し中 2x → 離すと 1.5x」を再利用可能な確認手順として追記する。

### 動作確認 [人間👨‍💻]

- [ ] 実機で動画再生中に画面を長押しし、押している間だけ 2倍速になることを確認する。
- [ ] 指を離すと、長押し前の速度に戻ることを確認する。
- [ ] 通常速度を 1.5x などに変更してから長押しし、離した後にその速度へ戻ることを確認する。
- [ ] 長押し、シングルタップ、ダブルタップ、下スワイプ、向き切り替えが誤爆しないことを確認する。

## ログ

### 試したこと・わかったこと

- 2026-06-20: 長押し開始位置を左右で判定し、右半分は一時2倍速、左半分は0.1秒間隔で約2x相当の巻き戻しシークを行う実装に変更した。
- 2026-06-20: `temporaryRewindTask` を `nonisolated` に変えると `@Observable` の展開後に mutable stored property 扱いでビルド失敗したため、既存方針に合わせて `nonisolated(unsafe)` に戻した。
- 2026-06-21: Simulator で左長押しが右扱いになる報告を受け、座標判定を廃止して左半分/右半分を別々の `PlayerGestureLayer` として配置する実装へ変更した。
- 2026-06-13: `mise run build` が成功した。Xcode の既存 `nonisolated(unsafe)` warning は残るが、今回変更によるビルドエラーはない。
- 2026-06-13: `mise run run` で Simulator へインストール・起動でき、動画一覧からプレイヤー画面へ遷移できることを確認した。
- 2026-06-13: CoreGraphics 経由のクリックでプレイヤー画面のシングルタップ overlay 表示は確認できた。
- 2026-06-13: CoreGraphics / AppleScript の mouse hold では Simulator 上の long press touch を安定再現できず、長押し中 2x と復元の直接確認は手動確認に残した。
- 2026-06-13: `PlayerGestureView` を `private` にすると `UIViewRepresentable` の associated type 制約で build が落ちたため、internal に戻して build 成功を確認した。

### 方針変更

- 2026-06-20: 長押しは全画面一律の一時2倍速ではなく、開始位置が右半分なら2倍速、左半分なら巻き戻しに分岐する方針へ変更した。巻き戻しは負の `AVPlayer.rate` に依存せず、対応差を避けるため定期的なシークで実現する。
- 2026-06-13: 計画レビューを反映し、一時2倍速中の `setRate(_:)` は `playbackRate` だけ更新し、終了時は常に最新の `playbackRate` へ戻す方針に明確化した。
- 2026-06-13: `isPlaying` は `AVPlayer.rate` の KVO 由来で境界条件に弱いため、長押し開始時の `wasPlayingBeforeTemporaryFastForward` と終了時の pause / 動画終了チェックを追加する方針にした。
- 2026-06-13: ジェスチャー実装は SwiftUI の `LongPressGesture` + `DragGesture` の sequenced gesture を第一候補にし、cancel 検知が不安定なら `UILongPressGestureRecognizer` へ切り替える方針にした。
- 2026-06-13: buffering / waiting 中の再生意図を拾うため、長押し開始時の判定に `player.timeControlStatus != .paused` を含める方針にした。SwiftUI gesture の cancel 検知は `@GestureState` を優先し、必要なら drag location の bounds 判定も追加する。
- 2026-06-13: SwiftUI gesture 版は Simulator 入力で single tap との共存確認が不安定だったため、single tap / double tap / long press を同じ `UIViewRepresentable` の UIKit recognizer に集約した。
- 2026-06-13: 手動確認時の操作状態を見分けやすくするため、長押し中だけ小さな `2x` フィードバックを追加した。
