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
            .onDisappear {
                if let id = requestID {
                    PhotoLibraryService.shared.cancelThumbnailRequest(id)
                    requestID = nil
                }
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
