import Foundation
import Observation
import AVFoundation
import Photos

@MainActor
@Observable
final class VideoPlayerViewModel {
    let video: VideoAsset
    private(set) var player: AVPlayer = AVPlayer()
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackRate: Float = 1.0
    var isOverlayVisible: Bool = false
    var loadError: String?
    var seekFeedback: SeekFeedback?

    nonisolated(unsafe) private var timeObserver: Any?
    nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    nonisolated(unsafe) private var rateObservation: NSKeyValueObservation?
    nonisolated(unsafe) private let playerRef: AVPlayer
    private var hideOverlayTask: Task<Void, Never>?

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
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        rateObservation?.invalidate()
    }

    func setUp() async {
        // silent mode でも再生し、他のアプリの音声を中断する
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        let asset: AVAsset? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: video.phAsset, options: options) { asset, _, _ in
                continuation.resume(returning: asset)
            }
        }
        guard let asset else {
            loadError = "動画の読み込みに失敗しました"
            return
        }

        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        player.replaceCurrentItem(with: item)
        duration = video.duration

        installObservers(for: item)
        player.play()
        isPlaying = true
    }

    private func installObservers(for item: AVPlayerItem) {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                self?.currentTime = seconds
            }
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] _, change in
            let isPlayingNow = (change.newValue ?? 0) != 0
            Task { @MainActor [weak self] in
                self?.isPlaying = isPlayingNow
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = false
            }
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            if currentTime >= duration - 0.05 {
                player.seek(to: .zero)
            }
            player.playImmediately(atRate: playbackRate)
        }
    }

    func seek(to seconds: TimeInterval) {
        let target = max(0, min(seconds, duration))
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seekRelative(seconds: TimeInterval) {
        seek(to: currentTime + seconds)
        seekFeedback = SeekFeedback(seconds: seconds, id: UUID())
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player.rate = rate
        }
    }

    func showOverlay() {
        isOverlayVisible = true
        scheduleOverlayHide()
    }

    func toggleOverlay() {
        if isOverlayVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    func hideOverlay() {
        hideOverlayTask?.cancel()
        isOverlayVisible = false
    }

    func scheduleOverlayHide() {
        hideOverlayTask?.cancel()
        hideOverlayTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                self?.isOverlayVisible = false
            }
        }
    }
}

struct SeekFeedback: Equatable {
    let seconds: TimeInterval
    let id: UUID
}
