import Foundation

enum VideoSortMode: String, CaseIterable, Identifiable, Sendable {
    case creationDate
    case libraryAddedDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .creationDate:
            return "撮影日"
        case .libraryAddedDate:
            return "ライブラリ追加日"
        }
    }

    var effectiveMode: VideoSortMode {
        switch self {
        case .creationDate:
            return .creationDate
        case .libraryAddedDate:
            if #available(iOS 26.0, *) {
                return .libraryAddedDate
            }
            return .creationDate
        }
    }

    static var availableModes: [VideoSortMode] {
        if #available(iOS 26.0, *) {
            return allCases
        }
        return [.creationDate]
    }

    static func effectiveMode(rawValue: String) -> VideoSortMode {
        (VideoSortMode(rawValue: rawValue) ?? .creationDate).effectiveMode
    }
}
