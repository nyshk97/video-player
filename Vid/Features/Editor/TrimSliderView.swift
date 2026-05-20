import SwiftUI

struct TrimSliderView: View {
    let duration: TimeInterval
    @Binding var startTime: TimeInterval
    @Binding var endTime: TimeInterval
    let currentTime: TimeInterval

    let onChangeStart: (TimeInterval) -> Void
    let onChangeEnd: (TimeInterval) -> Void
    let onScrub: (TimeInterval) -> Void

    private let handleWidth: CGFloat = 14
    private let trackHeight: CGFloat = 56
    private let accent = Color.yellow

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let usable = max(width - handleWidth * 2, 1)
            let startRatio = duration > 0 ? CGFloat(startTime / duration) : 0
            let endRatio = duration > 0 ? CGFloat(endTime / duration) : 1
            let currentRatio = duration > 0 ? CGFloat(currentTime / duration) : 0
            let startX = startRatio * usable + handleWidth / 2
            let endX = endRatio * usable + handleWidth * 1.5
            let currentX = currentRatio * usable + handleWidth

            ZStack(alignment: .leading) {
                background

                // 選択範囲のハイライト
                Rectangle()
                    .fill(accent.opacity(0.18))
                    .frame(width: max(endX - startX, 0), height: trackHeight)
                    .offset(x: startX)

                // 上下のボーダー (選択範囲)
                Rectangle()
                    .fill(accent)
                    .frame(width: max(endX - startX, 0), height: 3)
                    .offset(x: startX, y: -trackHeight / 2 + 1.5)
                Rectangle()
                    .fill(accent)
                    .frame(width: max(endX - startX, 0), height: 3)
                    .offset(x: startX, y: trackHeight / 2 - 1.5)

                // 現在位置インジケータ (選択範囲内に居るときだけ)
                if currentTime >= startTime && currentTime <= endTime {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: trackHeight)
                        .offset(x: currentX - 1)
                }

                // 左ハンドル
                handle(side: .leading)
                    .offset(x: startX - handleWidth / 2)
                    .gesture(dragGesture(side: .leading, usable: usable))

                // 右ハンドル
                handle(side: .trailing)
                    .offset(x: endX - handleWidth / 2)
                    .gesture(dragGesture(side: .trailing, usable: usable))
            }
            .frame(height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = max(0, min(1, (value.location.x - handleWidth) / usable))
                        let t = Double(ratio) * duration
                        if t > startTime && t < endTime {
                            onScrub(t)
                        }
                    }
            )
        }
        .frame(height: trackHeight)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.18))
            .frame(height: trackHeight - 8)
            .padding(.vertical, 4)
    }

    private func handle(side: HorizontalEdge) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: handleWidth, height: trackHeight)
            Image(systemName: side == .leading ? "chevron.compact.left" : "chevron.compact.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
        }
    }

    private func dragGesture(side: HorizontalEdge, usable: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let ratio = max(0, min(1, (value.location.x - handleWidth) / usable))
                let newTime = Double(ratio) * duration
                if side == .leading {
                    onChangeStart(min(newTime, endTime - 0.1))
                } else {
                    onChangeEnd(max(newTime, startTime + 0.1))
                }
            }
    }
}
