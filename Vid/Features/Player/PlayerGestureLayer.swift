import SwiftUI
import UIKit

struct PlayerGestureLayer: UIViewRepresentable {
    let viewModel: VideoPlayerViewModel
    let isRightSide: Bool

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

        view.addGestureRecognizer(singleTap)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(longPress)
        return view
    }

    func updateUIView(_ uiView: PlayerGestureView, context: Context) {
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
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onSingleTap: () -> Void = {}
        var onDoubleTap: () -> Void = {}
        var onLongPressBegan: () -> Void = {}
        var onLongPressEnded: () -> Void = {}
        private var isLongPressActive: Bool = false

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

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
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
