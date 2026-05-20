import Foundation
import Observation
import Photos
import UIKit

@MainActor
@Observable
final class VideoLibraryViewModel {
    var videos: [VideoAsset] = []
    var authorizationStatus: PHAuthorizationStatus = .notDetermined
    var isLoading: Bool = false

    private let service = PhotoLibraryService.shared

    func bootstrap() async {
        authorizationStatus = service.currentAuthorizationStatus()
        switch authorizationStatus {
        case .notDetermined:
            authorizationStatus = await service.requestAuthorization()
            if authorizationStatus == .authorized || authorizationStatus == .limited {
                await load()
            }
        case .authorized, .limited:
            await load()
        default:
            break
        }
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
}
