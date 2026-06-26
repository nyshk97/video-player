# 横画面切り替えボタンが反応しなくなる問題の修正

## 概要・やりたいこと

動画を複数見た後や、縦画面と横画面の切り替えを何度か行った後に、右下の横画面表示ボタンを押しても反応せず縦画面のままになる問題を修正する。

調査では、`OrientationManager.isRequestPending` が `true` のまま残り、ボタン側の disabled と `togglePlayerOrientation()` の guard によって以後の向き切り替えが無視される可能性が高いと判断した。向き変更 request の pending lifecycle を整理し、プレイヤーを閉じる・再表示する・編集から戻るなどの経路でも pending が残らない状態にする。

## 前提・わかっていること

- 横画面切り替えボタンは `PlayerControlsOverlay` で `isOrientationRequestPending` 中に disabled になる。
- `OrientationManager.togglePlayerOrientation()` は `isRequestPending == true` の場合に即 return する。
- `OrientationManager.requestGeometry(...)` は `isRequestPending = true` にした後、450ms 後の `settleTask` で `false` に戻す設計になっている。
- `enterPlayer()` と `resumePlayerAfterEditor()` は `settleTask?.cancel()` するが、現状では `isRequestPending` を `false` に戻していない。
- `leavePlayer()` は現在すでに portrait でも `requestPortrait()` を呼ぶため、プレイヤーを閉じた直後にも不要な pending が発生しうる。
- 「閉じる → すぐ次の動画を開く」などが 450ms の settle 待ちと重なると、`enterPlayer()` が settle task をキャンセルし、pending flag だけが残る race が起こりうる。
- 左右スワイプ実装は直接 orientation request を出していないが、動画切り替えやプレイヤー再表示の頻度が増えることで race に当たりやすくなる。
- 実機での最終確認が必要。シミュレータでは iPhone の縦向きロック ON/OFF を含む挙動を完全には確認できない。

## 実装計画

### 事前準備 [人間👨‍💻]

- [ ] 実機 iPhone で、動画を複数本見られる状態にしておく。
- [ ] 画面縦向きロック ON/OFF を切り替えられる状態にしておく。

### Phase 1: pending lifecycle を整理する [AI🤖]

- [x] `OrientationManager` 内で `settleTask` をキャンセルする経路を洗い出す。
- [x] pending request の reset helper を作り、`settleTask` cancel、`settleTask = nil`、request generation invalidation、`isRequestPending = false`、実向きに基づく state 再同期を 1 箇所に寄せる。
- [x] `enterPlayer()` と `resumePlayerAfterEditor()` では、直接 state を個別更新せず reset helper 経由で pending request を破棄する。
- [x] pending を解除するときに `lastRequestError`、`requestedLock`、`allowedMask`、`actualInterfaceOrientation` が矛盾しないように同期する。
- [x] request generation を導入し、`requestGeometryUpdate` の error callback と `settleTask` の両方で最新 request か確認してから state を更新する。
- [x] 古い request / callback / settle task が、新しい request や reset 後の state を上書きできないことをコード上で確認する。

### Phase 2: 不要な portrait request を抑制する [AI🤖]

- [x] `leavePlayer()` が、すでに portrait かつ `allowedMask == .portrait` で pending もない場合は request を出さずに終了するようにする。
- [x] `requestPortraitBeforeTransition()` と `leavePlayer()` の重複 request が無駄な pending を作らないことを確認する。
- [x] landscape から閉じる・編集へ進む経路では、従来通り portrait settle を待ってから遷移する挙動を維持する。
- [x] `requestGeometryUpdate` 失敗時は、`requestedLock` と `allowedMask` の両方を実際の `actualInterfaceOrientation` に基づいて戻し、`requestedLock = .portrait` かつ `allowedMask = .landscape` のような不整合を作らない。

### Phase 3: 再発検知しやすくする [AI🤖]

- [x] `OrientationManager` の debug log に、request 開始、settle、failure、cancel/reset の状態を出す。
- [x] ログには `requestedLock`、`actualInterfaceOrientation`、`allowedMask`、`isRequestPending` が追える情報を含める。
- [x] 本番 UI には不要なエラー表示を増やさず、調査に必要な情報は `OSLog` に限定する。

### Phase 4: ビルドと静的確認 [AI🤖]

- [x] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer mise run build` を実行する。
- [x] Simulator runtime / Asset Catalog 由来で失敗する場合は、Swift compile まで進んでいるか、既知の環境問題かをログから切り分ける。
- [x] `rg` で `isRequestPending` の書き込み箇所を再確認し、true にしたまま戻らない経路が残っていないことを確認する。

### Phase 5: 実機確認 [人間👨‍💻]

- [ ] 動画を開く → 横画面ボタン → 縦画面ボタンを数回繰り返して、毎回反応することを確認する。
- [ ] 動画を閉じてすぐ別の動画を開き、横画面ボタンが反応することを確認する。
- [ ] 複数動画を左右スワイプで切り替えた後、横画面ボタンが反応することを確認する。
- [ ] 横向き中に閉じる・編集へ入る経路で、一覧や編集画面が最初から portrait で表示されることを確認する。
- [ ] 横画面ボタンを押してすぐに × で閉じても、次回プレイヤー表示時に横画面ボタンが反応することを確認する。
- [ ] 横画面ボタンを押してすぐに編集へ入っても、戻った後に横画面ボタンが反応することを確認する。
- [ ] 画面縦向きロック ON/OFF の両方で、横画面ボタンが反応しなくなる状態が再発しないことを確認する。

### Phase 6: 確認手順の反映 [AI🤖]

- [x] 再利用可能な確認手順が `VERIFY.md` に未記載なら、既存の「向き切り替え」セクションへ追記する。
- [x] 今回の race 条件に特化した「閉じてすぐ開く」「複数動画切り替え後に向き変更」の確認項目を追加する。

## ログ

### 試したこと・わかったこと

（実装中に随時追記）

- 2026-06-26: `OrientationManager` に request generation と pending reset helper を追加し、`enterPlayer()` / `resumePlayerAfterEditor()` で stale settle task と callback を無効化するようにした。
- 2026-06-26: `requestPortraitIfNeeded(reason:)` で portrait 済みの `leavePlayer()` と既存 portrait pending の重複 request を抑制した。
- 2026-06-26: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer mise run build` は初回 Swift capture の明示 `self` 不足で失敗し、修正後に `** BUILD SUCCEEDED **` を確認した。
- 2026-06-26: `rg "isRequestPending\\s*="` で `true` は request 開始時のみ、`false` は settle / failure / reset の 3 経路のみであることを確認した。
- 2026-06-26: 実機で同現象が継続して見えたが、直前の確認は simulator build のみで実機へ修正版を未インストールだった可能性が高い。`xcodebuild -destination 'id=73C0CECF-CEE2-5483-9967-303546396F11' build` と `devicectl device install app` で修正版を実機へ入れ直し、ユーザー側で改善傾向を確認中。

### 方針変更

（実装中に随時追記）

- 2026-06-26: plan review を反映し、失敗時 fallback の state invariant 維持と request generation による stale callback 防止を必須対応に変更した。pending reset は helper に集約し、orientation pending 中に閉じる / 編集へ入る実機確認も追加する。
