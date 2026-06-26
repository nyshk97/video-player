import Foundation
import Observation
import AVFoundation
import Photos

@MainActor
@Observable
final class VideoPlayerViewModel {
    private(set) var video: VideoAsset
    private(set) var player: AVPlayer = AVPlayer()
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackRate: Float = 1.0
    private(set) var isTemporaryFastForwarding: Bool = false
    private(set) var isTemporaryRewinding: Bool = false
    private(set) var isLoadingNextVideo: Bool = false
    var isOverlayVisible: Bool = false
    var loadError: String?
    var navigationMessage: String?
    var seekFeedback: SeekFeedback?

    nonisolated(unsafe) private var timeObserver: Any?
    nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    nonisolated(unsafe) private var rateObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var temporaryRewindTask: Task<Void, Never>?
    nonisolated(unsafe) private var activeAVAssetRequest: AVAssetRequest?
    nonisolated(unsafe) private let playerRef: AVPlayer
    private var hideOverlayTask: Task<Void, Never>?
    private var navigationMessageTask: Task<Void, Never>?
    private var wasPlayingBeforeTemporaryFastForward: Bool = false
    private var wasPlayingBeforeTemporaryRewind: Bool = false
    private var temporaryRewindTargetTime: TimeInterval = 0
    private var loadGeneration: Int = 0

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
        activeAVAssetRequest?.cancel()
    }

    var canNavigateBySwipe: Bool {
        !isLoadingNextVideo && loadError == nil && player.currentItem != nil
    }

    func setUp() async {
        // silent mode でも再生し、他のアプリの音声を中断する
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        await load(video: video, autoPlay: true, isInitialLoad: true)
    }

    func cancelLoading() {
        loadGeneration += 1
        activeAVAssetRequest?.cancel()
        activeAVAssetRequest = nil
        isLoadingNextVideo = false
    }

    @discardableResult
    func load(video newVideo: VideoAsset, autoPlay: Bool? = nil, isInitialLoad: Bool = false) async -> Bool {
        loadGeneration += 1
        let generation = loadGeneration
        let shouldAutoPlay = autoPlay ?? (playerHasPlaybackIntent && !hasReachedEnd)
        let rateBeforeLoad = playbackRate

        if !isInitialLoad {
            prepareForVideoSwitch()
            isLoadingNextVideo = true
            navigationMessage = nil
        }
        defer {
            if !isInitialLoad, generation == loadGeneration {
                isLoadingNextVideo = false
            }
        }

        activeAVAssetRequest?.cancel()
        let request = AVAssetRequest()
        activeAVAssetRequest = request

        let asset = await requestAVAsset(for: newVideo, request: request)
        if let activeRequest = activeAVAssetRequest, activeRequest === request {
            activeAVAssetRequest = nil
        }

        guard !Task.isCancelled, generation == loadGeneration else {
            return false
        }

        guard let asset else {
            if isInitialLoad {
                loadError = "動画の読み込みに失敗しました"
            } else {
                showNavigationMessage("動画の読み込みに失敗しました")
                if shouldAutoPlay {
                    player.playImmediately(atRate: rateBeforeLoad)
                    isPlaying = true
                }
            }
            return false
        }

        removePlaybackObservers()

        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        player.replaceCurrentItem(with: item)

        video = newVideo
        duration = newVideo.duration
        currentTime = 0
        loadError = nil
        seekFeedback = nil

        installObservers(for: item)
        if shouldAutoPlay {
            player.playImmediately(atRate: rateBeforeLoad)
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }

        return true
    }

    private func requestAVAsset(for video: VideoAsset, request: AVAssetRequest) async -> AVAsset? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                request.setContinuation(continuation)
                let requestID = PHImageManager.default().requestAVAsset(forVideo: video.phAsset, options: options) { asset, _, _ in
                    request.finish(with: asset)
                }
                request.setRequestID(requestID)
            }
        } onCancel: {
            request.cancel()
        }
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

    private func removePlaybackObservers() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        rateObservation?.invalidate()
        rateObservation = nil
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

    private func prepareForVideoSwitch() {
        pause()
        hideOverlayTask?.cancel()
        seekFeedback = nil
    }

    private func showNavigationMessage(_ message: String) {
        navigationMessageTask?.cancel()
        navigationMessage = message
        navigationMessageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            self?.navigationMessage = nil
        }
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

private final class AVAssetRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var continuation: CheckedContinuation<AVAsset?, Never>?
    private var isFinished: Bool = false

    func setContinuation(_ continuation: CheckedContinuation<AVAsset?, Never>) {
        var shouldResumeImmediately = false

        lock.lock()
        if isFinished {
            shouldResumeImmediately = true
        } else {
            self.continuation = continuation
        }
        lock.unlock()

        if shouldResumeImmediately {
            continuation.resume(returning: nil)
        }
    }

    func setRequestID(_ requestID: PHImageRequestID) {
        var shouldCancel = false

        lock.lock()
        if isFinished {
            shouldCancel = true
        } else {
            self.requestID = requestID
        }
        lock.unlock()

        if shouldCancel {
            PHImageManager.default().cancelImageRequest(requestID)
        }
    }

    func finish(with asset: AVAsset?) {
        complete(returning: asset, shouldCancelRequest: false)
    }

    func cancel() {
        complete(returning: nil, shouldCancelRequest: true)
    }

    private func complete(returning asset: AVAsset?, shouldCancelRequest: Bool) {
        let continuationToResume: CheckedContinuation<AVAsset?, Never>?
        let requestIDToCancel: PHImageRequestID

        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        continuationToResume = continuation
        continuation = nil
        requestIDToCancel = requestID
        lock.unlock()

        if shouldCancelRequest, requestIDToCancel != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestIDToCancel)
        }
        continuationToResume?.resume(returning: asset)
    }
}
