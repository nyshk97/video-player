import SwiftUI
import UIKit

enum HorizontalSwipeDirection: Equatable {
    case left
    case right
}

struct PlayerGestureLayer: UIViewRepresentable {
    let viewModel: VideoPlayerViewModel
    let isRightSide: Bool
    let canReceiveGestures: () -> Bool
    let canBeginHorizontalPan: () -> Bool
    let onHorizontalPanChanged: (CGFloat) -> Void
    let onHorizontalPanEnded: (HorizontalSwipeDirection?) -> Void
    let onHorizontalPanCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerGestureView {
        let view = PlayerGestureView()

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false
        singleTap.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delegate = context.coordinator
        singleTap.require(toFail: doubleTap)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.35
        longPress.allowableMovement = 18
        longPress.cancelsTouchesInView = false
        longPress.delegate = context.coordinator

        let horizontalPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleHorizontalPan(_:))
        )
        horizontalPan.cancelsTouchesInView = false
        horizontalPan.delegate = context.coordinator

        view.addGestureRecognizer(singleTap)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(longPress)
        view.addGestureRecognizer(horizontalPan)
        return view
    }

    func updateUIView(_ uiView: PlayerGestureView, context: Context) {
        context.coordinator.canReceiveGestures = canReceiveGestures
        context.coordinator.canBeginHorizontalPan = canBeginHorizontalPan
        context.coordinator.onSingleTap = {
            viewModel.toggleOverlay()
        }
        context.coordinator.onDoubleTap = {
            viewModel.seekRelative(seconds: isRightSide ? 10 : -10)
        }
        context.coordinator.onLongPressBegan = {
            if isRightSide {
                viewModel.beginTemporaryFastForward()
            } else {
                viewModel.beginTemporaryRewind()
            }
        }
        context.coordinator.onLongPressEnded = {
            viewModel.endTemporaryLongPressPlayback()
        }
        context.coordinator.onHorizontalPanBegan = {
            viewModel.endTemporaryLongPressPlayback()
        }
        context.coordinator.onHorizontalPanChanged = onHorizontalPanChanged
        context.coordinator.onHorizontalPanEnded = onHorizontalPanEnded
        context.coordinator.onHorizontalPanCancelled = onHorizontalPanCancelled
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canReceiveGestures: () -> Bool = { true }
        var canBeginHorizontalPan: () -> Bool = { false }
        var onSingleTap: () -> Void = {}
        var onDoubleTap: () -> Void = {}
        var onLongPressBegan: () -> Void = {}
        var onLongPressEnded: () -> Void = {}
        var onHorizontalPanBegan: () -> Void = {}
        var onHorizontalPanChanged: (CGFloat) -> Void = { _ in }
        var onHorizontalPanEnded: (HorizontalSwipeDirection?) -> Void = { _ in }
        var onHorizontalPanCancelled: () -> Void = {}
        private var isLongPressActive: Bool = false
        private var isHorizontalPanActive: Bool = false

        private let minimumHorizontalTranslation: CGFloat = 70
        private let minimumHorizontalVelocity: CGFloat = 600
        private let horizontalDominanceRatio: CGFloat = 1.2

        @objc func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onSingleTap()
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onDoubleTap()
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                isLongPressActive = true
                onLongPressBegan()
            case .changed:
                endLongPressIfMovedOutside(recognizer)
            case .ended, .cancelled, .failed:
                endLongPressIfNeeded()
            default:
                break
            }
        }

        @objc func handleHorizontalPan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                isHorizontalPanActive = true
                endLongPressIfNeeded()
                onHorizontalPanBegan()
                onHorizontalPanChanged(0)
            case .changed:
                guard isHorizontalPanActive, let view = recognizer.view else { return }
                onHorizontalPanChanged(recognizer.translation(in: view).x)
            case .ended:
                defer { isHorizontalPanActive = false }
                guard let view = recognizer.view else { return }
                let translation = recognizer.translation(in: view)
                let velocity = recognizer.velocity(in: view)
                let isHorizontal = abs(translation.x) > abs(translation.y) * horizontalDominanceRatio
                let hasEnoughDistance = abs(translation.x) >= minimumHorizontalTranslation ||
                    abs(velocity.x) >= minimumHorizontalVelocity

                if isHorizontal && hasEnoughDistance {
                    onHorizontalPanEnded(translation.x < 0 ? .left : .right)
                } else {
                    onHorizontalPanEnded(nil)
                }
            case .cancelled, .failed:
                isHorizontalPanActive = false
                onHorizontalPanCancelled()
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard canReceiveGestures() else { return false }

            if let pan = gestureRecognizer as? UIPanGestureRecognizer {
                guard canBeginHorizontalPan(), let view = pan.view else { return false }
                let velocity = pan.velocity(in: view)
                return abs(velocity.x) > abs(velocity.y) * horizontalDominanceRatio
            }

            return !isHorizontalPanActive
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if gestureRecognizer is UIPanGestureRecognizer || otherGestureRecognizer is UIPanGestureRecognizer {
                return false
            }
            return true
        }

        private func endLongPressIfMovedOutside(_ recognizer: UILongPressGestureRecognizer) {
            guard isLongPressActive, let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            if !view.bounds.contains(location) {
                endLongPressIfNeeded()
            }
        }

        private func endLongPressIfNeeded() {
            guard isLongPressActive else { return }
            isLongPressActive = false
            onLongPressEnded()
        }
    }
}

final class PlayerGestureView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
