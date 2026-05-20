import Foundation
import Observation
import Photos
import UIKit

@MainActor
@Observable
final class VideoLibraryViewModel: NSObject, PHPhotoLibraryChangeObserver {
    var videos: [VideoAsset] = []
    var authorizationStatus: PHAuthorizationStatus = .notDetermined
    var isLoading: Bool = false

    private let service = PhotoLibraryService.shared
    nonisolated(unsafe) private var isObserving = false

    override init() {
        super.init()
    }

    deinit {
        if isObserving {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    func bootstrap() async {
        authorizationStatus = service.currentAuthorizationStatus()
        switch authorizationStatus {
        case .notDetermined:
            authorizationStatus = await service.requestAuthorization()
            if authorizationStatus == .authorized || authorizationStatus == .limited {
                await load()
                startObservingIfNeeded()
            }
        case .authorized, .limited:
            await load()
            startObservingIfNeeded()
        default:
            break
        }
    }

    private func startObservingIfNeeded() {
        guard !isObserving else { return }
        isObserving = true
        PHPhotoLibrary.shared().register(self)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let fetched = await Task.detached(priority: .userInitiated) { @MainActor in
            PhotoLibraryService.shared.fetchVideos()
        }.value
        videos = fetched
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - PHPhotoLibraryChangeObserver

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            await self?.load()
        }
    }
}
