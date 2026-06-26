import SwiftUI
import UIKit

struct VideoPlayerView: View {
    @State private var viewModel: VideoPlayerViewModel
    @State private var orientationManager = OrientationManager.shared
    @State private var currentVideoID: String
    @State private var currentIndex: Int
    @State private var dragOffset: CGFloat = 0
    @State private var showEditor: Bool = false
    @State private var isPreparingTransition: Bool = false
    @State private var navigationTask: Task<Void, Never>?
    @State private var horizontalDragOffset: CGFloat = 0
    @State private var isHorizontalTransitioning: Bool = false
    @State private var viewportWidth: CGFloat = UIScreen.main.bounds.width
    @Environment(\.dismiss) private var dismiss

    private let videos: [VideoAsset]
    private let dismissThreshold: CGFloat = 120
    private let horizontalEdgeResistance: CGFloat = 0.28

    init(videos: [VideoAsset], initialVideo: VideoAsset, initialIndex: Int) {
        self.videos = videos
        let resolvedIndex = videos.firstIndex { $0.id == initialVideo.id }
            ?? (videos.indices.contains(initialIndex) ? initialIndex : 0)
        _viewModel = State(initialValue: VideoPlayerViewModel(video: initialVideo))
        _currentVideoID = State(initialValue: initialVideo.id)
        _currentIndex = State(initialValue: resolvedIndex)
    }

    var body: some View {
        ZStack {
            // 下スワイプ時に背景が透けて見えるように、ドラッグ中は透過
            Color.black.opacity(backgroundOpacity).ignoresSafeArea()

            playerContent
                .offset(x: horizontalDragOffset, y: dragOffset)
                .scaleEffect(playerScale, anchor: .center)

            if isPlayerInteractionBlocked {
                transitionBlockerOverlay
                    .transition(.opacity)
            }
        }
        .background(viewportSizeReader)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isOverlayVisible)
        .simultaneousGesture(dismissDragGesture)
        .task {
            orientationManager.enterPlayer()
            await viewModel.setUp()
        }
        .onChange(of: videoIDs) { _, _ in
            syncCurrentVideoWithVideos()
        }
        .onDisappear {
            cancelNavigationLoad()
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
                if let message = viewModel.navigationMessage {
                    navigationMessageOverlay(message)
                        .transition(.opacity)
                }
            }
        }
    }

    private var gestureLayer: some View {
        HStack(spacing: 0) {
            PlayerGestureLayer(
                viewModel: viewModel,
                isRightSide: false,
                canReceiveGestures: { canReceivePlayerInput },
                canBeginHorizontalPan: { canBeginHorizontalPan },
                onHorizontalPanChanged: handleHorizontalPanChanged,
                onHorizontalPanEnded: handleHorizontalPanEnded,
                onHorizontalPanCancelled: resetHorizontalDragOffset
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PlayerGestureLayer(
                viewModel: viewModel,
                isRightSide: true,
                canReceiveGestures: { canReceivePlayerInput },
                canBeginHorizontalPan: { canBeginHorizontalPan },
                onHorizontalPanChanged: handleHorizontalPanChanged,
                onHorizontalPanEnded: handleHorizontalPanEnded,
                onHorizontalPanCancelled: resetHorizontalDragOffset
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private var viewportSizeReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    viewportWidth = proxy.size.width
                }
                .onChange(of: proxy.size.width) { _, width in
                    viewportWidth = width
                }
        }
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

    private var transitionBlockerOverlay: some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()

            if viewModel.isLoadingNextVideo {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
                    .padding(18)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .contentShape(Rectangle())
    }

    private func navigationMessageOverlay(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.6), in: Capsule())
            Spacer().frame(height: 108)
        }
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
                guard canReceivePlayerInput,
                      isDismissDragDirection(value.translation)
                else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let actualIsDismissDirection = isDismissDragDirection(value.translation)
                let predictedIsDismissDirection = isDismissDragDirection(value.predictedEndTranslation)

                guard canReceivePlayerInput,
                      actualIsDismissDirection || predictedIsDismissDirection
                else {
                    resetDismissDragOffset()
                    return
                }

                if (actualIsDismissDirection && value.translation.height > dismissThreshold) ||
                    (predictedIsDismissDirection && value.predictedEndTranslation.height > 250) {
                    startCloseAfterPortrait()
                } else {
                    resetDismissDragOffset()
                }
        }
    }

    private var videoIDs: [String] {
        videos.map(\.id)
    }

    private var canReceivePlayerInput: Bool {
        !isPlayerInteractionBlocked &&
            !isPreparingTransition
    }

    private var isPlayerInteractionBlocked: Bool {
        viewModel.isLoadingNextVideo || isHorizontalTransitioning
    }

    private var canBeginHorizontalPan: Bool {
        canReceivePlayerInput &&
            viewModel.canNavigateBySwipe &&
            !orientationManager.isRequestPending
    }

    private func isDismissDragDirection(_ translation: CGSize) -> Bool {
        translation.height > 0 &&
            abs(translation.width) < translation.height * 1.5
    }

    private func resetDismissDragOffset() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = 0
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

    private func handleHorizontalPanChanged(_ translationX: CGFloat) {
        guard canBeginHorizontalPan else { return }

        let direction: HorizontalSwipeDirection = translationX < 0 ? .left : .right
        let canNavigate = abs(translationX) < 1 || canNavigateHorizontally(direction)
        horizontalDragOffset = canNavigate ? translationX : translationX * horizontalEdgeResistance
    }

    private func handleHorizontalPanEnded(_ direction: HorizontalSwipeDirection?) {
        guard let direction else {
            resetHorizontalDragOffset()
            return
        }

        guard canNavigateHorizontally(direction) else {
            playEdgeFeedback()
            resetHorizontalDragOffset()
            return
        }

        navigateToAdjacentVideo(direction)
    }

    private func navigateToAdjacentVideo(_ direction: HorizontalSwipeDirection) {
        let delta = direction == .left ? 1 : -1
        navigateToAdjacentVideo(delta: delta)
    }

    private func navigateToAdjacentVideo(delta: Int) {
        guard canBeginHorizontalPan else { return }
        guard let resolvedCurrentIndex = videos.firstIndex(where: { $0.id == currentVideoID }) else {
            startCloseAfterPortrait()
            return
        }

        currentIndex = resolvedCurrentIndex
        let targetIndex = resolvedCurrentIndex + delta
        guard videos.indices.contains(targetIndex) else {
            playEdgeFeedback()
            return
        }

        let targetVideo = videos[targetIndex]
        navigationTask?.cancel()
        navigationTask = Task { @MainActor in
            defer {
                navigationTask = nil
                isHorizontalTransitioning = false
            }
            guard !Task.isCancelled else { return }
            isHorizontalTransitioning = true

            let exitOffset = delta > 0 ? -viewportWidth : viewportWidth
            let entryOffset = -exitOffset
            withAnimation(.easeOut(duration: 0.16)) {
                horizontalDragOffset = exitOffset
            }
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }

            let didLoad = await viewModel.load(video: targetVideo)
            guard !Task.isCancelled else { return }
            guard didLoad else {
                resetHorizontalDragOffset()
                return
            }

            currentVideoID = targetVideo.id
            currentIndex = videos.firstIndex(where: { $0.id == targetVideo.id }) ?? targetIndex
            withTransaction(Transaction(animation: nil)) {
                horizontalDragOffset = entryOffset
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.9)) {
                horizontalDragOffset = 0
            }
            try? await Task.sleep(nanoseconds: 340_000_000)
        }
    }

    private func canNavigateHorizontally(_ direction: HorizontalSwipeDirection) -> Bool {
        guard let resolvedCurrentIndex = videos.firstIndex(where: { $0.id == currentVideoID }) else {
            return false
        }

        let targetIndex = resolvedCurrentIndex + (direction == .left ? 1 : -1)
        return videos.indices.contains(targetIndex)
    }

    private func resetHorizontalDragOffset() {
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.86)) {
            horizontalDragOffset = 0
        }
    }

    private func syncCurrentVideoWithVideos() {
        if let syncedIndex = videos.firstIndex(where: { $0.id == currentVideoID }) {
            currentIndex = syncedIndex
        } else {
            startCloseAfterPortrait()
        }
    }

    private func playEdgeFeedback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func startCloseAfterPortrait() {
        Task { @MainActor in
            await closeAfterPortrait()
        }
    }

    private func closeAfterPortrait() async {
        guard !isPreparingTransition else { return }
        isPreparingTransition = true
        cancelNavigationLoad()
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

    private func cancelNavigationLoad() {
        navigationTask?.cancel()
        navigationTask = nil
        isHorizontalTransitioning = false
        horizontalDragOffset = 0
        viewModel.cancelLoading()
    }
}
