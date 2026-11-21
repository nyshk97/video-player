import SwiftUI
import UIKit

// iPhone Duo（折りたたみ）向けの対応。
// - 閉じた画面では、時刻やツールバーを右端に縦に並べる「縦の帯」をシステムが置く
// - 開いた画面はウインドウとして扱われ、アプリから縦横を指定できない

extension View {
    /// 縦の帯を使わず、ふつうの上下の帯にする。
    ///
    /// 全画面で動画を見せる画面向け。帯を使ったままだと、ステータスバーを隠しても
    /// 帯の分の余白が右に残り、操作ボタンが左に寄る。
    @ViewBuilder
    func verticalBarDisabled() -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(.disabled)
        } else {
            self
        }
    }

    /// 折りたたみの開閉を`OrientationManager`に伝える。
    ///
    /// 全画面で出す画面は前の画面を階層から外すので、画面ごとに付ける
    /// （階層を外れた側には状態が届かなくなる）。
    func reportsDeviceHinge() -> some View {
        background {
            DeviceHingeReporter()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct DeviceHingeReporter: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        if #available(iOS 27.1, *) {
            // 付けた直後に今の状態で1回呼ばれ、以後は開閉のたびに呼ばれる
            view.addInteraction(UIHingeInteraction { _, update in
                // 階層を外れたときはnil。最後に分かった状態をそのまま使う
                guard let hinge = update.hinge else { return }
                switch hinge.status {
                case .partiallyOpen, .fullyOpen:
                    OrientationManager.shared.updateDeviceUnfolded(true)
                case .closed:
                    OrientationManager.shared.updateDeviceUnfolded(false)
                default:
                    break
                }
            })
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
