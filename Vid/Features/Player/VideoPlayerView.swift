import SwiftUI

struct VideoPlayerView: View {
    @State private var viewModel: VideoPlayerViewModel
    @State private var orientationManager = OrientationManager.shared
    @State private var dragOffset: CGFloat = 0
    @State private var showEditor: Bool = false
    @State private var isPreparingTransition: Bool = false
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
            orientationManager.enterPlayer()
            await viewModel.setUp()
        }
        .onDisappear {
            viewModel.pause()
            orientationManager.leavePlayer()
        }
        .fullScreenCover(isPresented: $showEditor, onDismiss: {
            // 編集画面から戻ったら再生位置をリセットしないが、停止状態に
            viewModel.pause()
            orientationManager.resumePlayerAfterEditor()
        }) {
            VideoEditorView(video: viewModel.video)
        }
    }

    private var playerContent: some View {
        ZStack {
            AVPlayerViewRepresentable(player: viewModel.player)
                .ignoresSafeArea()

            if let error = viewModel.loadError {
                errorOverlay(error)
            } else {
                gestureLayer
                if viewModel.isOverlayVisible {
                    PlayerControlsOverlay(
                        viewModel: viewModel,
                        requestedOrientationLock: orientationManager.requestedLock,
                        actualInterfaceOrientation: orientationManager.actualInterfaceOrientation,
                        isOrientationRequestPending: orientationManager.isRequestPending,
                        onClose: {
                            startCloseAfterPortrait()
                        },
                        onEdit: {
                            openEditorAfterPortrait()
                        },
                        onDelete: {
                            Task {
                                let ok = await viewModel.deleteVideo()
                                if ok {
                                    await closeAfterPortrait()
                                }
                            }
                        },
                        onToggleOrientation: {
                            orientationManager.togglePlayerOrientation()
                        }
                    )
                    .transition(.opacity)
                }
                if viewModel.isTemporaryFastForwarding || viewModel.isTemporaryRewinding {
                    temporaryPlaybackFeedback(text: viewModel.isTemporaryRewinding ? "-2x" : "2x")
                        .transition(.opacity)
                }
                if let feedback = viewModel.seekFeedback {
                    SeekFeedbackView(seconds: feedback.seconds)
                        .id(feedback.id)
                }
            }
        }
    }

    private var gestureLayer: some View {
        HStack(spacing: 0) {
            PlayerGestureLayer(viewModel: viewModel, isRightSide: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PlayerGestureLayer(viewModel: viewModel, isRightSide: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private func temporaryPlaybackFeedback(text: String) -> some View {
        VStack {
            Text(text)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.5), in: Capsule())
            Spacer()
        }
        .padding(.top, 72)
        .allowsHitTesting(false)
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
                    startCloseAfterPortrait()
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
            Button("戻る") { startCloseAfterPortrait() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func startCloseAfterPortrait() {
        Task { @MainActor in
            await closeAfterPortrait()
        }
    }

    private func closeAfterPortrait() async {
        guard !isPreparingTransition else { return }
        isPreparingTransition = true
        await orientationManager.requestPortraitBeforeTransition()
        dismiss()
    }

    private func openEditorAfterPortrait() {
        guard !isPreparingTransition else { return }
        isPreparingTransition = true
        viewModel.pause()

        Task { @MainActor in
            await orientationManager.requestPortraitBeforeTransition()
            showEditor = true
            isPreparingTransition = false
        }
    }
}
