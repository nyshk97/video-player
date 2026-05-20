import SwiftUI

struct PlayerControlsOverlay: View {
    @Bindable var viewModel: VideoPlayerViewModel
    let onClose: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private let rates: [Float] = [0.75, 1.0, 1.5, 2.0]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.6), .clear, .clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack {
                topBar
                Spacer()
                centerControls
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.4), in: Circle())
            }

            Spacer()

            Button {
                onEdit()
            } label: {
                Image(systemName: "scissors")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .padding(.trailing, 6)

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .padding(.trailing, 6)

            Menu {
                ForEach(rates, id: \.self) { rate in
                    Button {
                        viewModel.setRate(rate)
                        viewModel.scheduleOverlayHide()
                    } label: {
                        HStack {
                            Text(formatRate(rate))
                            if viewModel.playbackRate == rate {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(formatRate(viewModel.playbackRate))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.4), in: Capsule())
            }
        }
    }

    private var centerControls: some View {
        Button {
            viewModel.togglePlayPause()
            viewModel.scheduleOverlayHide()
        } label: {
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(.black.opacity(0.35), in: Circle())
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            SeekSlider(viewModel: viewModel)
            HStack {
                Text(TimeFormatter.format(viewModel.currentTime))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                Text(TimeFormatter.formatRemaining(viewModel.duration - viewModel.currentTime))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    private func formatRate(_ rate: Float) -> String {
        if rate == floor(rate) {
            return String(format: "%.0fx", rate)
        }
        return String(format: "%.2gx", rate)
    }
}

private struct SeekSlider: View {
    @Bindable var viewModel: VideoPlayerViewModel
    @State private var isDragging: Bool = false
    @State private var dragValue: Double = 0

    var body: some View {
        let value = isDragging ? dragValue : viewModel.currentTime
        Slider(
            value: Binding(
                get: { value },
                set: { newValue in
                    dragValue = newValue
                    viewModel.seek(to: newValue)
                }
            ),
            in: 0...max(viewModel.duration, 0.1),
            onEditingChanged: { editing in
                isDragging = editing
                if editing {
                    viewModel.showOverlay()
                } else {
                    viewModel.scheduleOverlayHide()
                }
            }
        )
        .tint(.white)
    }
}
