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
    private(set) var isTemporaryFastForwarding: Bool = false
    private(set) var isTemporaryRewinding: Bool = false
    var isOverlayVisible: Bool = false
    var loadError: String?
    var seekFeedback: SeekFeedback?

    nonisolated(unsafe) private var timeObserver: Any?
    nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    nonisolated(unsafe) private var rateObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var temporaryRewindTask: Task<Void, Never>?
    nonisolated(unsafe) private let playerRef: AVPlayer
    private var hideOverlayTask: Task<Void, Never>?
    private var wasPlayingBeforeTemporaryFastForward: Bool = false
    private var wasPlayingBeforeTemporaryRewind: Bool = false
    private var temporaryRewindTargetTime: TimeInterval = 0

    private let temporaryRewindInterval: TimeInterval = 0.1
    private let temporaryRewindRate: TimeInterval = 2.0

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
        temporaryRewindTask?.cancel()
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
                self?.resetTemporaryLongPressPlaybackState()
                self?.isPlaying = false
            }
        }
    }

    func togglePlayPause() {
        if isTemporaryFastForwarding || isTemporaryRewinding {
            pause()
            return
        }
        if isPlaying || playerHasPlaybackIntent {
            pause()
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
        currentTime = target
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seekRelative(seconds: TimeInterval) {
        seek(to: currentTime + seconds)
        seekFeedback = SeekFeedback(seconds: seconds, id: UUID())
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isTemporaryFastForwarding || isTemporaryRewinding {
            return
        }
        if playerHasPlaybackIntent {
            player.rate = rate
        }
    }

    func beginTemporaryFastForward() {
        guard !isTemporaryFastForwarding, !isTemporaryRewinding else { return }

        wasPlayingBeforeTemporaryFastForward = playerHasPlaybackIntent && !hasReachedEnd
        guard wasPlayingBeforeTemporaryFastForward else { return }

        isTemporaryFastForwarding = true
        player.rate = 2.0
    }

    func endTemporaryFastForward() {
        let shouldRestoreRate = isTemporaryFastForwarding &&
            wasPlayingBeforeTemporaryFastForward &&
            playerHasPlaybackIntent &&
            !hasReachedEnd

        resetTemporaryFastForwardState()

        if shouldRestoreRate {
            player.rate = playbackRate
        }
    }

    func beginTemporaryRewind() {
        guard !isTemporaryFastForwarding, !isTemporaryRewinding else { return }

        wasPlayingBeforeTemporaryRewind = playerHasPlaybackIntent && !hasReachedEnd
        guard wasPlayingBeforeTemporaryRewind else { return }

        isTemporaryRewinding = true
        temporaryRewindTargetTime = currentTime
        player.pause()
        startTemporaryRewindTask()
    }

    func endTemporaryRewind() {
        let shouldResume = isTemporaryRewinding &&
            wasPlayingBeforeTemporaryRewind &&
            !hasReachedEnd

        resetTemporaryRewindState()

        if shouldResume {
            player.playImmediately(atRate: playbackRate)
        }
    }

    func endTemporaryLongPressPlayback() {
        endTemporaryFastForward()
        endTemporaryRewind()
    }

    func pause() {
        player.pause()
        resetTemporaryLongPressPlaybackState()
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

    /// 動画を「最近削除した項目」へ移動。
    /// 成功時のみ true を返す。ユーザーがシステム確認ダイアログでキャンセルした場合は false。
    func deleteVideo() async -> Bool {
        let asset = video.phAsset
        pause()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSFastEnumeration)
            }
            return true
        } catch {
            return false
        }
    }

    private var playerHasPlaybackIntent: Bool {
        player.rate != 0 || player.timeControlStatus != .paused
    }

    private var hasReachedEnd: Bool {
        duration > 0 && currentTime >= duration - 0.05
    }

    private func resetTemporaryFastForwardState() {
        isTemporaryFastForwarding = false
        wasPlayingBeforeTemporaryFastForward = false
    }

    private func startTemporaryRewindTask() {
        temporaryRewindTask?.cancel()
        let intervalNanoseconds = UInt64(temporaryRewindInterval * 1_000_000_000)
        temporaryRewindTask = Task { [weak self] in
            while !Task.isCancelled {
                let shouldContinue = await MainActor.run { [weak self] in
                    guard let self, self.isTemporaryRewinding else { return false }
                    return self.stepTemporaryRewind()
                }
                guard shouldContinue else { return }
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
            }
        }
    }

    private func stepTemporaryRewind() -> Bool {
        let distance = temporaryRewindRate * temporaryRewindInterval
        temporaryRewindTargetTime = max(0, temporaryRewindTargetTime - distance)
        seek(to: temporaryRewindTargetTime)
        return temporaryRewindTargetTime > 0
    }

    private func resetTemporaryRewindState() {
        temporaryRewindTask?.cancel()
        temporaryRewindTask = nil
        isTemporaryRewinding = false
        wasPlayingBeforeTemporaryRewind = false
        temporaryRewindTargetTime = 0
    }

    private func resetTemporaryLongPressPlaybackState() {
        resetTemporaryFastForwardState()
        resetTemporaryRewindState()
    }
}

struct SeekFeedback: Equatable {
    let seconds: TimeInterval
    let id: UUID
}
