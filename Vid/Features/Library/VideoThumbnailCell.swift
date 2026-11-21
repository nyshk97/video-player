import SwiftUI
import Photos
import UIKit

struct VideoThumbnailCell: View {
    let video: VideoAsset
    let pixelSize: CGSize

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Color(white: 0.15)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                durationLabel
            }
            .clipped()
            .contentShape(Rectangle())
            .onAppear { requestImage() }
            .onChange(of: pixelSize) { _, _ in
                // Duoの開閉でマスの大きさが変わったら、その大きさで取り直す（今の画像は届くまで出したまま）
                cancelRequest()
                requestImage()
            }
            .onDisappear { cancelRequest() }
    }

    private func cancelRequest() {
        if let id = requestID {
            PhotoLibraryService.shared.cancelThumbnailRequest(id)
            requestID = nil
        }
    }

    private var durationLabel: some View {
        Text(TimeFormatter.format(video.duration))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .padding(4)
    }

    private func requestImage() {
        // 一覧の幅を測る前（最初の1回の描画）は大きさが0なので取らない
        guard pixelSize.width > 0, pixelSize.height > 0 else { return }
        requestID = PhotoLibraryService.shared.requestThumbnail(
            for: video.phAsset,
            targetSize: pixelSize
        ) { uiImage in
            Task { @MainActor in
                if let uiImage {
                    self.image = uiImage
                }
            }
        }
    }
}
