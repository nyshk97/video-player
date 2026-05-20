import Foundation
import Photos
import UIKit

@MainActor
final class PhotoLibraryService {
    static let shared = PhotoLibraryService()

    private let cachingManager = PHCachingImageManager()
    private var cachedAssetIDs: Set<String> = []

    private init() {}

    func currentAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    func fetchVideos() -> [VideoAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .video, options: options)
        var videos: [VideoAsset] = []
        videos.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            videos.append(VideoAsset(phAsset: asset))
        }
        return videos
    }

    func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping @Sendable (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        return cachingManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }

    func cancelThumbnailRequest(_ id: PHImageRequestID) {
        cachingManager.cancelImageRequest(id)
    }

    func startCaching(assets: [PHAsset], targetSize: CGSize) {
        let newIDs = Set(assets.map(\.localIdentifier))
        let toAdd = assets.filter { !cachedAssetIDs.contains($0.localIdentifier) }
        if !toAdd.isEmpty {
            cachingManager.startCachingImages(
                for: toAdd,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: nil
            )
        }
        cachedAssetIDs = newIDs
    }

    func stopCachingAll() {
        cachingManager.stopCachingImagesForAllAssets()
        cachedAssetIDs.removeAll()
    }
}
