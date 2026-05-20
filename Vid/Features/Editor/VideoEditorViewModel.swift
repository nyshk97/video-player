import Foundation
import Observation
import AVFoundation
import Photos

@MainActor
@Observable
final class VideoEditorViewModel {
    let video: VideoAsset
    private(set) var player: AVPlayer = AVPlayer()
    private(set) var duration: TimeInterval = 0
    private(set) var asset: AVAsset?

    var startTime: TimeInterval = 0
    var endTime: TimeInterval = 0
    var currentTime: TimeInterval = 0
    var isPlaying: Bool = false

    var isExporting: Bool = false
    var exportProgress: Double = 0
    var exportError: String?
    var exportCompleted: Bool = false
    var loadError: String?

    nonisolated(unsafe) private var timeObserver: Any?
    nonisolated(unsafe) private var rateObservation: NSKeyValueObservation?
    nonisolated(unsafe) private let playerRef: AVPlayer

    init(video: VideoAsset) {
        self.video = video
        let p = AVPlayer()
        self.player = p
        self.playerRef = p
    }

    deinit {
        if let observer = timeObserver {
            playerRef.removeTimeObserver(observer)
        }
        rateObservation?.invalidate()
    }

    func setUp() async {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        let loaded: AVAsset? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: video.phAsset, options: options) { asset, _, _ in
                continuation.resume(returning: asset)
            }
        }
        guard let loaded else {
            loadError = "動画の読み込みに失敗しました"
            return
        }
        self.asset = loaded
        self.duration = video.duration
        self.endTime = video.duration

        let item = AVPlayerItem(asset: loaded)
        item.audioTimePitchAlgorithm = .spectral
        player.replaceCurrentItem(with: item)

        installObservers()
    }

    private func installObservers() {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = seconds
                // 再生中に endTime を超えたら自動で startTime に戻る
                if self.isPlaying, seconds >= self.endTime - 0.05 {
                    self.seek(to: self.startTime)
                }
            }
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] _, change in
            let isPlayingNow = (change.newValue ?? 0) != 0
            Task { @MainActor [weak self] in
                self?.isPlaying = isPlayingNow
            }
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            if currentTime < startTime || currentTime >= endTime - 0.05 {
                seek(to: startTime)
            }
            player.play()
        }
    }

    func seek(to seconds: TimeInterval) {
        let target = max(0, min(seconds, duration))
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setStartTime(_ t: TimeInterval) {
        let clamped = max(0, min(t, endTime - 0.1))
        startTime = clamped
        // プレビューも開始点に追従
        seek(to: clamped)
    }

    func setEndTime(_ t: TimeInterval) {
        let clamped = max(startTime + 0.1, min(t, duration))
        endTime = clamped
        seek(to: clamped)
    }

    func export() async {
        guard let asset else { return }
        guard endTime > startTime else {
            exportError = "範囲が不正です"
            return
        }

        isExporting = true
        exportProgress = 0
        exportError = nil
        defer { isExporting = false }

        player.pause()

        let composition = AVMutableComposition()
        let timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )

        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceVideo = videoTracks.first,
                  let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            else {
                exportError = "動画トラックがありません"
                return
            }
            try videoTrack.insertTimeRange(timeRange, of: sourceVideo, at: .zero)
            let transform = try await sourceVideo.load(.preferredTransform)
            videoTrack.preferredTransform = transform

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let sourceAudio = audioTracks.first,
               let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try audioTrack.insertTimeRange(timeRange, of: sourceAudio, at: .zero)
            }
        } catch {
            exportError = "範囲の切り出しに失敗: \(error.localizedDescription)"
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vid-\(UUID().uuidString).mov")

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            exportError = "Exporter の作成に失敗しました"
            return
        }
        session.outputURL = tempURL
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = true

        // progress polling
        let progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self {
                self.exportProgress = Double(session.progress)
                if session.status == .completed || session.status == .failed || session.status == .cancelled {
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        await session.export()
        progressTask.cancel()
        exportProgress = 1.0

        guard session.status == .completed else {
            exportError = "書き出し失敗: \(session.error?.localizedDescription ?? "不明")"
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: tempURL, options: nil)
            }
            try? FileManager.default.removeItem(at: tempURL)
            exportCompleted = true
        } catch {
            exportError = "写真ライブラリへの保存に失敗: \(error.localizedDescription)"
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
}
