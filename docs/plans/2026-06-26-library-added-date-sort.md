# 撮影日順とライブラリ追加日順の切り替え

## 概要・やりたいこと

動画一覧の並び順を、現在の「撮影日順」に加えて「ライブラリ追加日順」でも切り替えられるようにする。

デフォルトは現在と同じ撮影日順のままにし、どちらの並び順でも古いものが上、新しいものが下に来る。初期表示は今と同じく下端、つまり最新側が見える状態を維持する。

## 前提・わかっていること

- 現在の `PhotoLibraryService.fetchVideos()` は `PHAsset.creationDate` 昇順で動画を取得している。古い動画が配列の前、新しい動画が配列の後になる。
- `VideoLibraryView` は `viewModel.videos` をそのまま `LazyVGrid` に渡し、`.defaultScrollAnchor(.bottom)` で初期表示を下端にしている。
- `VideoPlayerView` の前後移動は `videos` 配列の index を基準にしている。並び順を変えると、プレイヤー内の左スワイプ/右スワイプの「次/前」もその並び順に追従する。
- 「端末への追加日」的な並び順には `PHAsset.addedDate` が最も近い。UI 表記は誤解を避けるため「ライブラリ追加日」とする。
- ローカル SDK ヘッダ上では `PHAsset.addedDate` は `iOS 26.0+` API。プロジェクトの deployment target は iOS 17.0 なので、iOS 26 未満ではこの項目を出さない。
- `photoLibraryDidChange` は `VideoLibraryViewModel.load()` を引数なしで呼んでいるため、並び順 state を View 側だけに閉じると、写真ライブラリ変更時に選択中の並び順を維持できない。ViewModel 側にも現在の effective sort mode を保持し、全 reload 経路で同じ値を使う。
- `.defaultScrollAnchor(.bottom)` は初期表示向けで、データ更新や並び順切り替え後に必ず下端へ戻る保証は弱い。並び順切り替え時は明示的に下端へスクロールする。
- ライブラリ追加日順の検証では、動画を一括投入すると `addedDate` が同時刻になり順序確認が不安定になる可能性がある。時間差で追加するか、追加日が明確に異なる実データを使う。
- ユーザー合意済みの仕様:
  - デフォルトは撮影日順。
  - 追加する選択肢は「ライブラリ追加日」。
  - iOS 26 未満では「ライブラリ追加日」を非表示。
  - UI は一覧右上のメニュー。
  - 並び方向は古い → 新しい、最新が一番下。

## 実装計画

### 事前準備 [人間👨‍💻]

- [x] デフォルト並び順を撮影日順のままにすることを決める。
- [x] UI 表記を「ライブラリ追加日」にすることを決める。
- [x] iOS 26 未満では「ライブラリ追加日」を非表示にすることを決める。
- [x] 並び替え UI を一覧右上メニューにすることを決める。

### Phase 1: 並び順モデルを追加する [AI🤖]

- [x] `VideoSortMode` を追加し、`creationDate` と `libraryAddedDate` を表現できるようにする。
- [x] 表示名は「撮影日」「ライブラリ追加日」にする。
- [x] `VideoLibraryView` 側の `@AppStorage` で選択中の並び順を保存し、初期値は `creationDate` にする。
- [x] iOS 26 未満で保存済み値が `libraryAddedDate` だった場合は、effective sort mode を `creationDate` として扱う。
- [x] `VideoLibraryViewModel` 側にも `currentSortMode` を持たせ、写真ライブラリ変更通知など View を経由しない reload でも同じ effective sort mode を使えるようにする。

### Phase 2: PhotoKit の取得順を切り替える [AI🤖]

- [x] `PhotoLibraryService.fetchVideos()` に sort mode を渡せるようにする。
- [x] `VideoLibraryViewModel.bootstrap(sortMode:)` と `load(sortMode:)` を用意し、呼び出し時に `currentSortMode` を更新してから fetch する。
- [x] `photoLibraryDidChange` からの reload は `currentSortMode` を使い、bootstrap / メニュー切り替え / 写真ライブラリ変更の全経路で同じ effective sort mode を使う。
- [x] 撮影日順では既存通り `NSSortDescriptor(key: "creationDate", ascending: true)` を使う。
- [x] iOS 26 以降のライブラリ追加日順では `NSSortDescriptor(key: "addedDate", ascending: true)` を使う。
- [x] iOS 26 未満では `addedDate` を参照しないよう、`#available(iOS 26.0, *)` で分岐する。

### Phase 3: 一覧右上メニューを追加する [AI🤖]

- [x] `VideoLibraryView` の navigation toolbar 右上に並び替えメニューを追加する。
- [x] メニュー内に `Picker` か同等の選択 UI を置き、撮影日順とライブラリ追加日順を切り替えられるようにする。
- [x] iOS 26 未満では「ライブラリ追加日」をメニューに表示しない。
- [x] 並び順を切り替えたら effective sort mode を `VideoLibraryViewModel.load(sortMode:)` に渡して一覧を更新する。
- [x] `ScrollViewReader` / `scrollPosition` / 下端 sentinel などで、並び順切り替え後に明示的に下端へスクロールする。
- [x] 初回表示では既存の最新側表示を維持し、明示スクロールは並び順切り替え時に優先して行う。

### Phase 4: プレイヤー連携を確認・調整する [AI🤖]

- [x] 並び順変更後に開いたプレイヤーへ、変更後の `videos` 配列が渡ることを確認する。
- [x] プレイヤー表示中に写真ライブラリ変更や並び順変更が起きても、現在動画 id を基準に index が再同期されることを確認する。
- [x] 左スワイプは現在の並び順における `index + 1`、右スワイプは `index - 1` のままでよいか確認する。

### Phase 5: ドキュメントと確認手順を更新する [AI🤖]

- [x] `VERIFY.md` の一覧画面に、撮影日順/ライブラリ追加日順の切り替え確認を追加する。
- [x] 既存の「新しい順」表記が実装とズレている場合は、「古い → 新しい、最新が下」に修正する。
- [x] 必要なら plan のログに、iOS 26 未満の確認可否や SDK 条件を記録する。

### Phase 6: ビルドと動作確認 [AI🤖]

- [x] Swift の型チェックまたは iOS ビルドを実行し、`addedDate` の availability 分岐でコンパイルが通ることを確認する。
- [x] 可能なら iOS 26 以降の実機または Simulator で、右上メニューに「ライブラリ追加日」が出ることを確認する。
- [ ] 可能なら iOS 26 未満の実機または Simulator で、右上メニューに「ライブラリ追加日」が出ないことを確認する。
- [ ] 動画を複数本入れた状態で、撮影日順とライブラリ追加日順のどちらも最新が下になることを確認する。
- [ ] ライブラリ追加日順の確認では、`xcrun simctl addmedia booted /tmp/vp-samples/*.mov` のような一括投入だけに依存せず、動画を時間差で追加するか、追加日が異なる実データを使う。

### 動作確認 [人間👨‍💻]

- [ ] iOS 26 以降の端末で、一覧右上メニューから「撮影日」と「ライブラリ追加日」を切り替えられることを確認する。
- [ ] 「撮影日」を選んだ状態で、撮影日が新しい動画ほど下に並ぶことを確認する。
- [ ] 「ライブラリ追加日」を選んだ状態で、ライブラリに最近追加した動画ほど下に並ぶことを確認する。
- [ ] アプリを再起動しても選択中の並び順が維持されることを確認する。
- [ ] iOS 26 未満の端末では「ライブラリ追加日」が表示されないことを確認する。

## ログ

### 試したこと・わかったこと

- 2026-06-26: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer mise run build` で iOS Simulator 向けビルド成功。通常の `mise run build` は `xcode-select` が Command Line Tools を向いていたため失敗した。
- 2026-06-26: iOS 26.5 Simulator で権限許可後、右上メニューに「撮影日」「ライブラリ追加日」が表示されることを確認。「ライブラリ追加日」選択後、`UserDefaults` に `videoSortMode = libraryAddedDate` が保存された。
- 2026-06-26: 利用可能な simulator runtime は iOS 26.5 のみだったため、iOS 26 未満で「ライブラリ追加日」が非表示になる実機/Simulator 目視確認は未実施。
- 2026-06-26: `/tmp/vp-samples` の動画を `xcrun simctl addmedia` で一括投入し、一覧が下端表示になることは確認した。一括投入のため、`addedDate` の厳密な順序確認には使っていない。

### 方針変更

- 2026-06-26: plan review を反映し、全 reload 経路で同じ effective sort mode を使うこと、並び順切り替え後に明示的に下端へスクロールすること、ライブラリ追加日順の検証は時間差追加または追加日が異なる実データで行うことを計画に追加した。
