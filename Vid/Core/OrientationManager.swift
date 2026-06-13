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

    private var settleTask: Task<Void, Never>?

    private init() {}

    var isActuallyLandscape: Bool {
        actualInterfaceOrientation.isLandscape
    }

    func enterPlayer() {
        settleTask?.cancel()
        lastRequestError = nil
        requestedLock = .portrait
        allowedMask = .portrait
        refreshActualInterfaceOrientation()
        updateSupportedOrientationControllers()
    }

    func leavePlayer() {
        requestPortrait()
    }

    func enterEditor() {
        requestPortrait()
    }

    func requestPortraitBeforeTransition() async {
        refreshActualInterfaceOrientation()
        if !actualInterfaceOrientation.isLandscape && allowedMask == .portrait && !isRequestPending {
            return
        }

        requestPortrait()
        try? await Task.sleep(nanoseconds: 500_000_000)
        refreshActualInterfaceOrientation()
    }

    func resumePlayerAfterEditor() {
        settleTask?.cancel()
        lastRequestError = nil
        requestedLock = .portrait
        allowedMask = .portrait
        refreshActualInterfaceOrientation()
        updateSupportedOrientationControllers()
    }

    func togglePlayerOrientation() {
        refreshActualInterfaceOrientation()
        guard !isRequestPending else { return }

        if actualInterfaceOrientation.isLandscape {
            requestPortrait()
        } else {
            requestLandscape()
        }
    }

    func refreshActualInterfaceOrientation() {
        guard let scene = activeWindowScene else { return }
        actualInterfaceOrientation = scene.interfaceOrientation
    }

    private func requestLandscape() {
        requestGeometry(
            lock: .landscape,
            targetMask: .landscapeRight,
            allowedMaskBeforeRequest: transitionAllowedMask,
            allowedMaskAfterRequest: .landscape
        )
    }

    private func requestPortrait() {
        requestGeometry(
            lock: .portrait,
            targetMask: .portrait,
            allowedMaskBeforeRequest: transitionAllowedMask,
            allowedMaskAfterRequest: .portrait
        )
    }

    private func requestGeometry(
        lock: OrientationLock,
        targetMask: UIInterfaceOrientationMask,
        allowedMaskBeforeRequest: UIInterfaceOrientationMask,
        allowedMaskAfterRequest: UIInterfaceOrientationMask
    ) {
        settleTask?.cancel()
        lastRequestError = nil
        requestedLock = lock
        isRequestPending = true
        allowedMask = allowedMaskBeforeRequest
        updateSupportedOrientationControllers()

        guard let scene = activeWindowScene else {
            handleGeometryRequestFailure(
                message: "No active UIWindowScene",
                fallbackAllowedMask: allowedMaskAfterRequest
            )
            return
        }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: targetMask)) { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleGeometryRequestFailure(
                    message: error.localizedDescription,
                    fallbackAllowedMask: allowedMaskAfterRequest
                )
            }
        }

        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self else { return }

            refreshActualInterfaceOrientation()
            isRequestPending = false
            allowedMask = allowedMaskAfterRequest
            updateSupportedOrientationControllers()
            logger.debug("Orientation request settled. requested=\(String(describing: requestedLock), privacy: .public), actual=\(actualInterfaceOrientation.rawValue, privacy: .public)")
        }
    }

    private func handleGeometryRequestFailure(
        message: String,
        fallbackAllowedMask: UIInterfaceOrientationMask
    ) {
        settleTask?.cancel()
        lastRequestError = message
        refreshActualInterfaceOrientation()
        requestedLock = actualInterfaceOrientation.isLandscape ? .landscape : .portrait
        isRequestPending = false
        allowedMask = fallbackAllowedMask
        updateSupportedOrientationControllers()
        logger.error("Orientation request failed: \(message, privacy: .public)")
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
