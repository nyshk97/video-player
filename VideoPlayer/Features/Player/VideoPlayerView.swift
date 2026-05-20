import SwiftUI

struct VideoPlayerView: View {
    @State private var viewModel: VideoPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    init(video: VideoAsset) {
        _viewModel = State(initialValue: VideoPlayerViewModel(video: video))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isOverlayVisible)
        .task {
            await viewModel.setUp()
        }
        .onDisappear {
            viewModel.player.pause()
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
