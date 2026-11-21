import SwiftUI
import Photos

struct VideoLibraryView: View {
    @AppStorage("videoSortMode") private var storedSortModeRawValue = VideoSortMode.creationDate.rawValue
    @State private var viewModel = VideoLibraryViewModel()
    @State private var playerSession: PlayerSession?
    @State private var scrollToBottomRequestID = 0
    @State private var gridWidth: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    private let gridSpacing: CGFloat = 2
    private let minimumColumnCount = 5
    /// 1マスがこれを下回らない範囲で列を増やす。iPhoneの縦（幅375〜440pt）は5列のまま、
    /// Duoを開いた画面（幅 約870pt）は10列になる
    private let minimumCellSide: CGFloat = 80
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
        let columnCount = columnCount(for: gridWidth)
        let columns = Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columnCount)
        let cellSide = max(0, (gridWidth - gridSpacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
        let pixelSize = CGSize(width: cellSide * displayScale, height: cellSide * displayScale)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
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
                // 画面の幅ではなく、縦の帯などを除いた実際の幅で列を決める（Duoを開閉すると変わる）
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.width
                } action: { width in
                    gridWidth = width
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

    private func columnCount(for width: CGFloat) -> Int {
        guard width > 0 else { return minimumColumnCount }
        let fittingCount = Int((width + gridSpacing) / (minimumCellSide + gridSpacing))
        return max(minimumColumnCount, fittingCount)
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
