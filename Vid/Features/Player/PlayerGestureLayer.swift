import SwiftUI

struct PlayerGestureLayer: View {
    let viewModel: VideoPlayerViewModel

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                gestureArea(proxy: proxy, isRight: false)
                gestureArea(proxy: proxy, isRight: true)
            }
        }
    }

    private func gestureArea(proxy: GeometryProxy, isRight: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                viewModel.seekRelative(seconds: isRight ? 10 : -10)
            }
            .onTapGesture(count: 1) {
                viewModel.toggleOverlay()
            }
    }
}
