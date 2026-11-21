import Observation
import OSLog
import UIKit

enum OrientationLock: Equatable {
    case portrait
    case landscape
}

@MainActor
@Observable
final class OrientationManager {
    static let shared = OrientationManager()

    private let transitionAllowedMask: UIInterfaceOrientationMask = [
        .portrait,
        .landscapeLeft,
        .landscapeRight
    ]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Vid", category: "Orientation")

    private(set) var allowedMask: UIInterfaceOrientationMask = .portrait
    private(set) var requestedLock: OrientationLock = .portrait
    private(set) var actualInterfaceOrientation: UIInterfaceOrientation = .portrait
    private(set) var isRequestPending: Bool = false
    private(set) var lastRequestError: String?
    /// iPhone Duoを開いているか（開いた画面に出ているか）
    private(set) var isDeviceUnfolded: Bool = false

    private var settleTask: Task<Void, Never>?
    private var requestGeneration: Int = 0

    private init() {}

    var isActuallyLandscape: Bool {
        actualInterfaceOrientation.isLandscape
    }

    /// アプリから縦横を切り替えられるか。
    ///
    /// Duoの開いた画面はウインドウとして扱われ、縦横を決めるのは端末の向きになる。
    /// 向きを絞る`requestGeometryUpdate`は「現在のウインドウモードでは、プログラムによってインターフェイスの方向を
    /// 変更することが許可されていません」で断られる（`supportedInterfaceOrientations`の許可は効く）。
    var canControlOrientation: Bool {
        !isDeviceUnfolded
    }

    /// Duoの開閉を受け取る。
    ///
    /// - 開いたら: 全方向を許可し、端末の向きに任せる。閉じた画面で出した向きの希望（横向き切り替えなど）は
    ///   シーンに残り、開いた画面ではそれを上書きする要求が断られるので、端末を回しても動かなくなる。
    ///   全方向の希望（＝希望なし）だけは通るので、開いたときに出し直して消す。
    /// - 閉じたら: 外の画面を縦から始める（一覧は縦だけ、プレイヤーも縦で開く決まりに合わせ、
    ///   開く前の横向き固定を持ち越さない）。
    func updateDeviceUnfolded(_ unfolded: Bool) {
        guard unfolded != isDeviceUnfolded else { return }
        isDeviceUnfolded = unfolded
        settleTask?.cancel()
        settleTask = nil
        requestGeneration += 1
        lastRequestError = nil
        isRequestPending = false
        requestedLock = .portrait
        allowedMask = mask(for: .portrait)
        refreshActualInterfaceOrientation()
        updateSupportedOrientationControllers()
        logger.debug("Device hinge changed. unfolded=\(unfolded, privacy: .public), generation=\(self.requestGeneration, privacy: .public), state=\(self.stateDescription, privacy: .public)")

        guard unfolded, let scene = activeWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .all)) { [weak self] error in
            Task { @MainActor [weak self] in
                self?.logger.error("Clearing orientation preference failed. message=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func enterPlayer() {
        resetPendingRequest(reason: "enterPlayer")
    }

    func leavePlayer() {
        requestPortraitIfNeeded(reason: "leavePlayer")
    }

    func enterEditor() {
        requestPortraitIfNeeded(reason: "enterEditor")
    }

    func requestPortraitBeforeTransition() async {
        if !requestPortraitIfNeeded(reason: "beforeTransition") {
            return
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        refreshActualInterfaceOrientation()
    }

    func resumePlayerAfterEditor() {
        resetPendingRequest(reason: "resumePlayerAfterEditor")
    }

    func togglePlayerOrientation() {
        refreshActualInterfaceOrientation()
        guard canControlOrientation, !isRequestPending else { return }

        if actualInterfaceOrientation.isLandscape {
            requestPortrait(reason: "toggle")
        } else {
            requestLandscape(reason: "toggle")
        }
    }

    func refreshActualInterfaceOrientation() {
        guard let scene = activeWindowScene else { return }
        actualInterfaceOrientation = scene.interfaceOrientation
    }

    @discardableResult
    private func requestPortraitIfNeeded(reason: String) -> Bool {
        refreshActualInterfaceOrientation()
        guard canControlOrientation else {
            logger.debug("Skipping portrait request because the system controls orientation. reason=\(reason, privacy: .public), state=\(self.stateDescription, privacy: .public)")
            return false
        }
        if !actualInterfaceOrientation.isLandscape && allowedMask == .portrait && !isRequestPending {
            logger.debug("Skipping portrait request. reason=\(reason, privacy: .public), state=\(self.stateDescription, privacy: .public)")
            return false
        }

        if isRequestPending && requestedLock == .portrait {
            logger.debug("Portrait request already pending. reason=\(reason, privacy: .public), state=\(self.stateDescription, privacy: .public)")
            return true
        }

        requestPortrait(reason: reason)
        return true
    }

    private func requestLandscape(reason: String) {
        requestGeometry(
            reason: reason,
            lock: .landscape,
            targetMask: .landscapeRight,
            allowedMaskBeforeRequest: transitionAllowedMask,
            allowedMaskAfterRequest: .landscape
        )
    }

    private func requestPortrait(reason: String) {
        requestGeometry(
            reason: reason,
            lock: .portrait,
            targetMask: .portrait,
            allowedMaskBeforeRequest: transitionAllowedMask,
            allowedMaskAfterRequest: .portrait
        )
    }

    private func requestGeometry(
        reason: String,
        lock: OrientationLock,
        targetMask: UIInterfaceOrientationMask,
        allowedMaskBeforeRequest: UIInterfaceOrientationMask,
        allowedMaskAfterRequest: UIInterfaceOrientationMask
    ) {
        settleTask?.cancel()
        settleTask = nil
        requestGeneration += 1
        let generation = requestGeneration
        lastRequestError = nil
        requestedLock = lock
        isRequestPending = true
        allowedMask = allowedMaskBeforeRequest
        updateSupportedOrientationControllers()
        logger.debug("Orientation request started. id=\(generation, privacy: .public), reason=\(reason, privacy: .public), target=\(self.maskDescription(targetMask), privacy: .public), state=\(self.stateDescription, privacy: .public)")

        guard let scene = activeWindowScene else {
            handleGeometryRequestFailure(
                message: "No active UIWindowScene",
                generation: generation
            )
            return
        }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: targetMask)) { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleGeometryRequestFailure(
                    message: error.localizedDescription,
                    generation: generation
                )
            }
        }

        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self else { return }
            guard generation == self.requestGeneration else {
                self.logger.debug("Ignoring stale orientation settle. id=\(generation, privacy: .public), current=\(self.requestGeneration, privacy: .public), state=\(self.stateDescription, privacy: .public)")
                return
            }

            self.refreshActualInterfaceOrientation()
            self.isRequestPending = false
            self.lastRequestError = nil
            self.allowedMask = allowedMaskAfterRequest
            self.settleTask = nil
            self.updateSupportedOrientationControllers()
            self.logger.debug("Orientation request settled. id=\(generation, privacy: .public), state=\(self.stateDescription, privacy: .public)")
        }
    }

    private func handleGeometryRequestFailure(
        message: String,
        generation: Int
    ) {
        guard generation == self.requestGeneration else {
            logger.debug("Ignoring stale orientation failure. id=\(generation, privacy: .public), current=\(self.requestGeneration, privacy: .public), message=\(message, privacy: .public), state=\(self.stateDescription, privacy: .public)")
            return
        }

        settleTask?.cancel()
        settleTask = nil
        lastRequestError = message
        refreshActualInterfaceOrientation()
        syncRequestedStateToActualOrientation()
        isRequestPending = false
        updateSupportedOrientationControllers()
        logger.error("Orientation request failed. id=\(generation, privacy: .public), message=\(message, privacy: .public), state=\(self.stateDescription, privacy: .public)")
    }

    private func resetPendingRequest(reason: String) {
        settleTask?.cancel()
        settleTask = nil
        requestGeneration += 1
        lastRequestError = nil
        refreshActualInterfaceOrientation()
        syncRequestedStateToActualOrientation()
        isRequestPending = false
        updateSupportedOrientationControllers()
        logger.debug("Orientation request reset. reason=\(reason, privacy: .public), generation=\(self.requestGeneration, privacy: .public), state=\(self.stateDescription, privacy: .public)")
    }

    private func syncRequestedStateToActualOrientation() {
        guard canControlOrientation else {
            // 開いた画面の向きに合わせて横を固定すると、閉じたときに外の画面が横のままになる
            requestedLock = .portrait
            allowedMask = mask(for: .portrait)
            return
        }
        requestedLock = actualInterfaceOrientation.isLandscape ? .landscape : .portrait
        allowedMask = mask(for: requestedLock)
    }

    /// 開いた画面では、どちらの固定でも全方向を許可する（端末の向きに任せる）
    private func mask(for lock: OrientationLock) -> UIInterfaceOrientationMask {
        guard canControlOrientation else { return .all }
        switch lock {
        case .portrait:
            return .portrait
        case .landscape:
            return .landscape
        }
    }

    private var stateDescription: String {
        "requested=\(requestedLock), actual=\(actualInterfaceOrientation.rawValue), allowed=\(maskDescription(allowedMask)), pending=\(isRequestPending), unfolded=\(isDeviceUnfolded)"
    }

    private func maskDescription(_ mask: UIInterfaceOrientationMask) -> String {
        if mask == .all {
            return "all"
        }
        if mask == .allButUpsideDown {
            return "allButUpsideDown"
        }

        var values: [String] = []
        if mask.contains(.portrait) {
            values.append("portrait")
        }
        if mask.contains(.portraitUpsideDown) {
            values.append("portraitUpsideDown")
        }
        if mask.contains(.landscapeLeft) {
            values.append("landscapeLeft")
        }
        if mask.contains(.landscapeRight) {
            values.append("landscapeRight")
        }
        return values.isEmpty ? "[]" : values.joined(separator: "|")
    }

    private func updateSupportedOrientationControllers() {
        guard let window = activeKeyWindow else { return }

        let root = window.rootViewController
        root?.setNeedsUpdateOfSupportedInterfaceOrientations()

        let topMost = topMostViewController(from: root)
        if topMost !== root {
            topMost?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    private var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    private var activeKeyWindow: UIWindow? {
        guard let scene = activeWindowScene else { return nil }
        return scene.windows.first { $0.isKeyWindow } ?? scene.windows.first
    }

    private func topMostViewController(from controller: UIViewController?) -> UIViewController? {
        if let presented = controller?.presentedViewController {
            return topMostViewController(from: presented)
        }

        if let navigationController = controller as? UINavigationController {
            return topMostViewController(from: navigationController.visibleViewController)
        }

        if let tabBarController = controller as? UITabBarController {
            return topMostViewController(from: tabBarController.selectedViewController)
        }

        return controller
    }
}
