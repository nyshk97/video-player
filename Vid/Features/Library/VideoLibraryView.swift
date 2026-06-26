import SwiftUI
import Photos

struct VideoLibraryView: View {
    @AppStorage("videoSortMode") private var storedSortModeRawValue = VideoSortMode.creationDate.rawValue
    @State private var viewModel = VideoLibraryViewModel()
    @State private var playerSession: PlayerSession?
    @State private var scrollToBottomRequestID = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 5)
    private let bottomAnchorID = "video-library-bottom-anchor"

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("動画")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if canShowSortMenu {
                        ToolbarItem(placement: .topBarTrailing) {
                            sortMenu
                        }
                    }
                }
        }
        .task {
            await viewModel.bootstrap(sortMode: effectiveSortMode)
        }
        .fullScreenCover(item: $playerSession) { session in
            if let initialVideo = initialVideo(for: session) {
                VideoPlayerView(
                    videos: viewModel.videos,
                    initialVideo: initialVideo,
                    initialIndex: session.initialIndex
                )
            } else {
                Color.black
                    .ignoresSafeArea()
                    .task {
                        playerSession = nil
                    }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.authorizationStatus {
        case .authorized, .limited:
            if viewModel.videos.isEmpty {
                emptyState
            } else {
                gridView
            }
        case .denied, .restricted:
            deniedState
        case .notDetermined:
            ProgressView()
        @unknown default:
            EmptyView()
        }
    }

    private var gridView: some View {
        let screenWidth = UIScreen.main.bounds.width
        let totalSpacing: CGFloat = 2 * 4
        let cellSide = (screenWidth - totalSpacing) / 5
        let scale = UIScreen.main.scale
        let pixelSize = CGSize(width: cellSide * scale, height: cellSide * scale)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
                        VideoThumbnailCell(video: video, pixelSize: pixelSize)
                            .onTapGesture {
                                playerSession = PlayerSession(
                                    initialVideoID: video.id,
                                    initialIndex: index
                                )
                            }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: scrollToBottomRequestID) { _, _ in
                scrollToBottom(with: proxy)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("並び順", selection: sortModeBinding) {
                ForEach(VideoSortMode.availableModes) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("並び順")
    }

    private var sortModeBinding: Binding<VideoSortMode> {
        Binding(
            get: {
                effectiveSortMode
            },
            set: { newValue in
                storedSortModeRawValue = newValue.rawValue
                Task {
                    await applySortMode(newValue)
                }
            }
        )
    }

    private var effectiveSortMode: VideoSortMode {
        VideoSortMode.effectiveMode(rawValue: storedSortModeRawValue)
    }

    private var canShowSortMenu: Bool {
        viewModel.authorizationStatus == .authorized ||
            viewModel.authorizationStatus == .limited
    }

    private func applySortMode(_ sortMode: VideoSortMode) async {
        let effectiveMode = sortMode.effectiveMode
        guard effectiveMode != viewModel.currentSortMode else { return }
        await viewModel.load(sortMode: effectiveMode)
        scrollToBottomRequestID += 1
    }

    private func scrollToBottom(with proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("動画がありません")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("写真へのアクセスが必要です")
                .font(.headline)
            Text("「設定」アプリでこのアプリの写真アクセス権を許可してください。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("設定を開く") {
                viewModel.openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func initialVideo(for session: PlayerSession) -> VideoAsset? {
        if let video = viewModel.videos.first(where: { $0.id == session.initialVideoID }) {
            return video
        }
        if viewModel.videos.indices.contains(session.initialIndex) {
            return viewModel.videos[session.initialIndex]
        }
        return viewModel.videos.first
    }
}

private struct PlayerSession: Identifiable {
    let id = UUID()
    let initialVideoID: String
    let initialIndex: Int
}
