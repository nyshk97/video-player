import SwiftUI
import Photos

struct VideoLibraryView: View {
    @State private var viewModel = VideoLibraryViewModel()
    @State private var selectedVideo: VideoAsset?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 5)

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("動画")
                .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await viewModel.bootstrap()
        }
        .fullScreenCover(item: $selectedVideo) { video in
            VideoPlayerView(video: video)
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

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(viewModel.videos) { video in
                    VideoThumbnailCell(video: video, pixelSize: pixelSize)
                        .onTapGesture {
                            selectedVideo = video
                        }
                }
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
}
