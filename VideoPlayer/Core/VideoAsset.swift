import Foundation
import Photos

struct VideoAsset: Identifiable, Hashable {
    let id: String
    let phAsset: PHAsset
    let duration: TimeInterval
    let creationDate: Date?

    init(phAsset: PHAsset) {
        self.id = phAsset.localIdentifier
        self.phAsset = phAsset
        self.duration = phAsset.duration
        self.creationDate = phAsset.creationDate
    }

    static func == (lhs: VideoAsset, rhs: VideoAsset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
