# プレイヤーの向き固定切り替え対応

## 概要・やりたいこと

動画再生画面に、YouTube のような右下の向き切り替えボタンを追加する。

縦画面で動画を開いている状態からボタンを押すと横向き全画面で固定し、横向き状態でもう一度押すと縦向きに戻して固定する。iPhone 側で「画面縦向きのロック」が有効な場合でも、ボタン操作によって横向き再生できる挙動を目標にする。

このアプリは一覧画面を縦向き前提にしているため、横向き対応はプレイヤー画面だけに限定し、プレイヤーを閉じたら必ず縦向きに戻す。

## 前提・わかっていること

- 対象は iPhone のみ。`project.yml` の `TARGETED_DEVICE_FAMILY` は `1`。
- 現在の `UISupportedInterfaceOrientations` は `UIInterfaceOrientationPortrait` のみで、アプリ全体として横向きが許可されていない。
- プレイヤー画面は `VideoLibraryView` から `fullScreenCover` で `VideoPlayerView` を開く構成。
- `VideoPlayerView` は SwiftUI ベースで、実際の動画表示は `AVPlayerViewRepresentable` が `AVPlayerLayer` を持つ `UIView` を提供している。
- コントロール UI は `PlayerControlsOverlay` にあり、右下にはまだ専用ボタンがない。
- iOS 16+ の向き変更は、基本的に `UIWindowScene.requestGeometryUpdate(...)` と `UIViewController.setNeedsUpdateOfSupportedInterfaceOrientations()` を使う必要がある。
- SwiftUI だけで完結させるのは難しく、向き制御用の UIKit ブリッジが必要になる見込み。
- `UIViewControllerRepresentable` を SwiftUI tree の途中に置くだけでは、その controller の `supportedInterfaceOrientations` が root/presenting の `UIHostingController` に効く保証がない。向き許可の source of truth は App/WindowScene レベルに置く。
- 第一候補は `@UIApplicationDelegateAdaptor` で `AppDelegate.application(_:supportedInterfaceOrientationsFor:)` を実装し、そこから動的な orientation mask を返す構成にする。必要なら active `UIWindowScene` の root/topmost controller に `setNeedsUpdateOfSupportedInterfaceOrientations()` を当てる。
- AppDelegate 方式で SwiftUI の presentation stack に反映できない場合の第二候補として、UIKit lifecycle / custom `UIHostingController` root へ寄せる案を検討する。
- iPhone の画面縦向きロック中に、アプリからの明示的な landscape 要求が期待通り通るかは実機確認が必要。シミュレータだけでは最終判断しない。
- もし system orientation の切り替えがロック中に期待通り動かない場合は、フォールバックとしてプレイヤー領域だけを回転表示する案を検討する。ただし safe area、ジェスチャー、ボタン配置、閉じる操作が複雑になるため第一候補にはしない。

## 実装計画

### 事前準備 [人間👨‍💻]

- [ ] 実機 iPhone で検証できる状態にする。
- [ ] iPhone の「画面縦向きのロック」を ON/OFF できる状態にしておく。

### Phase 1: 向き制御の土台を作る [AI🤖]

- [x] `project.yml` の supported orientations を、少なくとも portrait / landscape left / landscape right を含む設定に変更する。
- [x] XcodeGen でプロジェクトを再生成する前提で、設定変更が生成物ではなく `project.yml` に入っていることを確認する。
- [x] `@MainActor` の `OrientationManager` を追加し、`allowedMask`、`requestedLock`、`actualInterfaceOrientation`、`isRequestPending`、`lastRequestError` を分けて管理する。
- [x] `@UIApplicationDelegateAdaptor` で `AppDelegate` を追加し、`application(_:supportedInterfaceOrientationsFor:)` が `OrientationManager.allowedMask` を返すようにする。
- [x] active foreground `UIWindowScene`、key window、root controller、presented stack の topmost controller を取得する helper を追加する。
- [x] mask 更新時は root controller と topmost controller の両方に `setNeedsUpdateOfSupportedInterfaceOrientations()` を呼ぶ。
- [x] 一覧画面は `allowedMask = .portrait`、プレイヤー画面でも通常は現在の固定向きだけを許可し、向き切り替え request 中だけ `allowedMask = [.portrait, .landscapeLeft, .landscapeRight]` に広げる。
- [x] 子の `UIViewControllerRepresentable` の `supportedInterfaceOrientations` には依存しない。使う場合も controller 取得や lifecycle hook 用に限定する。

### Phase 2: プレイヤーに向き切り替え状態を持たせる [AI🤖]

- [x] `VideoPlayerView` には単純な `isLandscape` ではなく、要求状態 (`requestedLock`: portrait / landscape) と実際の状態 (`windowScene.interfaceOrientation`) を分けて持たせる。
- [x] プレイヤー表示開始時は `requestedLock = .portrait`、`actualInterfaceOrientation` は active scene から読み直して初期化する。
- [x] landscape へ切り替える順序は、`allowedMask` を landscape 対応へ更新 → root/topmost controller に `setNeedsUpdateOfSupportedInterfaceOrientations()` → `requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight または .landscape))` とする。
- [x] portrait へ戻す順序は、portrait request を確実に出す → root/topmost controller に更新通知 → scene の実向きを再読込 → 必要なら `allowedMask = .portrait` に戻す、として戻し漏れを避ける。
- [x] `requestGeometryUpdate(...)` の `errorHandler` で失敗を `lastRequestError` に記録し、`isRequestPending = false`、`requestedLock` は実際の `interfaceOrientation` に合わせて戻す。
- [x] request 中は pending 状態として扱い、ボタン表示を「要求済み」と「実際の向き」のどちらに寄せるかを実装で明示する。初期方針は、失敗時に誤表示しないよう実際の `interfaceOrientation` を優先する。
- [x] 閉じる、削除後に閉じる、`onDisappear` などの終了経路で portrait に戻す処理を入れる。
- [x] 編集画面へ遷移する場合は、`showEditor = true` の前に landscape 状態を明示的に解除して portrait request を出す。編集から戻った後もプレイヤー側の `requestedLock` / `actualInterfaceOrientation` を portrait として再同期する。
- [x] `UIDevice.current.setValue(...)` に依存しすぎず、iOS 17 以降で妥当な API を優先する。

### Phase 3: 右下の切り替えボタンを追加する [AI🤖]

- [x] `PlayerControlsOverlay` に `onToggleOrientation`、`requestedLock`、`actualInterfaceOrientation`、`isOrientationRequestPending` を渡せるようにする。
- [x] bottom bar の右下付近に、YouTube 風の四角い向き切り替えボタンを追加する。
- [x] portrait 時は landscape 化を示すアイコン、landscape 時は portrait 復帰を示すアイコンに切り替える。
- [x] アイコンとアクセシビリティラベルは、原則として実際の `actualInterfaceOrientation` に基づいて決める。pending 中は二重タップを避けるため一時的に無効化するか、同一要求を無視する。
- [x] request 失敗時はボタン表示を実際の向きに戻し、必要なら debug log に失敗理由を残す。
- [x] 既存のシークバー、残り時間ラベル、ホームインジケータ safe area と干渉しない余白に調整する。
- [x] ボタン操作後も overlay の自動非表示挙動が自然になるように、`scheduleOverlayHide()` との関係を調整する。

### Phase 4: 横向き時の操作感を調整する [AI🤖]

- [ ] 横向き時のコントロール配置を確認し、上部ボタン、中央再生ボタン、下部シークバーが safe area 内に収まるようにする。
- [ ] 下スワイプで閉じるジェスチャーが横向き時にも意図通りか確認し、誤爆しやすければ横向き中だけ閾値変更または無効化を検討する。
- [ ] 縦動画を横向き表示した場合の余白とボタン配置を確認する。
- [ ] 横動画、縦動画の両方で `AVPlayerLayer.videoGravity = .resizeAspect` の見え方が破綻しないことを確認する。

### Phase 5: ビルドとシミュレータ確認 [AI🤖]

- [x] `mise run gen` で Xcode project を再生成する。
- [x] `mise run build` または `mise run run` でビルドが通ることを確認する。
- [ ] シミュレータで動画を開き、右下ボタンが表示されることを確認する。
- [ ] シミュレータで portrait → landscape → portrait の切り替えができることを確認する。
- [ ] シミュレータで request 失敗時の `lastRequestError` / debug log が確認できる状態になっていることを確認する。
- [ ] プレイヤーを閉じた後、一覧画面が portrait に戻ることを確認する。
- [ ] landscape 状態から編集ボタンを押したとき、編集画面が portrait で開き、戻った後のプレイヤー状態も portrait として再同期されることを確認する。
- [x] 確認手順が再利用可能なら `VERIFY.md` に追記する。

### Phase 6前の確認 [人間👨‍💻]

- [ ] 実機 iPhone にインストールして、画面縦向きロック OFF で portrait → landscape → portrait が期待通り動くか確認する。
- [ ] 実機 iPhone で画面縦向きロック ON にして、右下ボタンで landscape 固定できるか確認する。
- [ ] landscape 固定中にもう一度ボタンを押して portrait に戻るか確認する。
- [ ] プレイヤーを閉じた後、一覧画面が portrait 固定に戻るか確認する。

### Phase 6: 実機結果に応じた調整 [AI🤖]

- [ ] 実機で system orientation 切り替えが成功した場合は、細かい UI 位置と終了経路の戻し漏れを修正する。
- [ ] 実機で request が失敗する場合は、`errorHandler` の内容、`requestedLock`、`actualInterfaceOrientation`、画面縦向きロック状態をログとして整理する。
- [ ] 縦向きロック ON で landscape 要求が通らない場合は、プレイヤー領域だけを回転させるフォールバック実装の可否を判断する。
- [ ] フォールバックを入れる場合は、シークバー、タップ領域、下スワイプ、safe area の座標系を個別に検証する。
- [ ] 実機確認で得た再現手順と制約を `VERIFY.md` に追記する。

### 動作確認 [人間👨‍💻]

- [ ] 実機で portrait ロック OFF の通常切り替えを確認する。
- [ ] 実機で portrait ロック ON の YouTube 風切り替えを確認する。
- [ ] 横動画と縦動画の両方で表示崩れがないことを確認する。
- [ ] 再生、一時停止、シーク、10秒スキップ、速度変更、閉じる、削除、編集遷移が既存通り動くことを確認する。

## ログ

### 試したこと・わかったこと

- 2026-06-13: `mise run gen` 成功。`project.yml` から `Vid.xcodeproj` を再生成した。
- 2026-06-13: `mise run build` 成功。Swift / UIKit API の型問題なく `** BUILD SUCCEEDED **`。
- 2026-06-13: 生成済み `Info.plist` を `plutil -p` で確認し、`UISupportedInterfaceOrientations` が portrait / landscape left / landscape right の配列になっていることを確認した。
- 2026-06-13: `mise run run` でシミュレータへインストール・起動成功。`mise run shot` で一覧画面のスクリーンショットを取得し、起動クラッシュがないことを確認した。
- 2026-06-13: landscape request 後も `allowedMask` を portrait+landscape のままにすると自動回転 ON の端末で「横向き固定」にならないため、settle 後は `.landscape` / `.portrait` に絞る実装に変更した。request 前だけ transition mask を使う。
- 2026-06-13: `simctl` にはタップ操作がなく、AppleScript の `System Events click at` は `-25204` で失敗したため、プレイヤーを開いて右下ボタンを押す操作確認は自動化できていない。
- 2026-06-13: 実機スクリーンショットで向き切り替えボタンが見えていなかった。下段の時刻行に混ぜた配置と SF Symbol 依存をやめ、右下に独立した 44pt ボタンとして配置し、四角枠は SwiftUI の `RoundedRectangle` で描画するよう変更した。
- 2026-06-13: ユーザー確認でシミュレータ上の表示は良好、実機でも全画面切り替えは動いていそうとのこと。残りは縦向きロック ON/OFF、閉じる/編集遷移での portrait 復帰を必要に応じて明示確認する。
- 2026-06-13: 向き切り替えの再利用可能な確認項目を `VERIFY.md` に追記した。
- 2026-06-13: 実機確認で、横向き中に閉じる/編集へ入ると遷移先が一瞬横で開いてから約 0.4 秒後に縦へ戻ることが判明。`dismiss()` / `showEditor = true` の前に portrait request の settle を待つ `requestPortraitBeforeTransition()` を追加し、遷移先が最初から縦で出るよう修正した。

### 方針変更

- 2026-06-13: 計画レビューを反映し、単なる `UIViewControllerRepresentable` 依存ではなく、AppDelegate の orientation mask、active window scene、root/topmost controller 更新、`requestGeometryUpdate` の順序を明記した。要求状態と実際の向きも分離する方針に変更。
- 2026-06-13: プレイヤー表示中ずっと portrait+landscape を許可する方針をやめ、ボタン操作後は現在の固定向きだけを許可する方針に変更した。理由: 自動回転 ON の端末でも YouTube 風の「ボタンで固定」を実現するため。
