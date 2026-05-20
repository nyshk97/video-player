import SwiftUI

struct VideoPlayerView: View {
    @State private var viewModel: VideoPlayerViewModel
    @State private var dragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    private let dismissThreshold: CGFloat = 120

    init(video: VideoAsset) {
        _viewModel = State(initialValue: VideoPlayerViewModel(video: video))
    }

    var body: some View {
        ZStack {
            // 下スワイプ時に背景が透けて見えるように、ドラッグ中は透過
            Color.black.opacity(backgroundOpacity).ignoresSafeArea()

            playerContent
                .offset(y: dragOffset)
                .scaleEffect(playerScale, anchor: .center)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isOverlayVisible)
        .simultaneousGesture(dismissDragGesture)
        .task {
            await viewModel.setUp()
        }
        .onDisappear {
            viewModel.player.pause()
        }
    }

    private var playerContent: some View {
        ZStack {
            AVPlayerViewRepresentable(player: viewModel.player)
                .ignoresSafeArea()

            if let error = viewModel.loadError {
                errorOverlay(error)
            } else {
                PlayerGestureLayer(viewModel: viewModel)
                if viewModel.isOverlayVisible {
                    PlayerControlsOverlay(viewModel: viewModel, onClose: { dismiss() })
                        .transition(.opacity)
                }
                if let feedback = viewModel.seekFeedback {
                    SeekFeedbackView(seconds: feedback.seconds)
                        .id(feedback.id)
                }
            }
        }
    }

    private var backgroundOpacity: Double {
        let fade = max(0, min(1, Double(dragOffset / 400)))
        return 1 - fade * 0.6
    }

    private var playerScale: CGFloat {
        let progress = max(0, min(1, dragOffset / 400))
        return 1 - progress * 0.1
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard value.translation.height > 0,
                      abs(value.translation.width) < value.translation.height * 1.5 else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > dismissThreshold ||
                    value.predictedEndTranslation.height > 250 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.white)
            Text(message)
                .foregroundStyle(.white)
            Button("戻る") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }
}
