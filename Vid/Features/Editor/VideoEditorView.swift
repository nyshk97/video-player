import SwiftUI

struct VideoEditorView: View {
    @State private var viewModel: VideoEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSuccessAlert: Bool = false

    init(video: VideoAsset) {
        _viewModel = State(initialValue: VideoEditorViewModel(video: video))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                playerArea
                Spacer(minLength: 0)
                trimArea
                actionArea
            }
            .foregroundStyle(.white)

            if viewModel.isExporting {
                exportingOverlay
            }
        }
        .statusBarHidden(true)
        .task { await viewModel.setUp() }
        .onDisappear { viewModel.player.pause() }
        .onChange(of: viewModel.exportCompleted) { _, completed in
            if completed { showSuccessAlert = true }
        }
        .alert("書き出し完了", isPresented: $showSuccessAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("写真ライブラリに保存しました")
        }
        .alert("エラー", isPresented: Binding(
            get: { viewModel.exportError != nil },
            set: { if !$0 { viewModel.exportError = nil } }
        )) {
            Button("OK") { viewModel.exportError = nil }
        } message: {
            Text(viewModel.exportError ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("キャンセル")
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("動画をトリム")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            // バランスのためのダミー
            Text("キャンセル").opacity(0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var playerArea: some View {
        ZStack {
            AVPlayerViewRepresentable(player: viewModel.player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .onTapGesture {
                    viewModel.togglePlayPause()
                }

            if !viewModel.isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(20)
                    .background(.black.opacity(0.35), in: Circle())
                    .allowsHitTesting(false)
            }
        }
    }

    private var trimArea: some View {
        VStack(spacing: 12) {
            HStack {
                timeChip(viewModel.startTime, label: "開始")
                Spacer()
                Text(TimeFormatter.format(viewModel.endTime - viewModel.startTime))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                timeChip(viewModel.endTime, label: "終了")
            }
            .padding(.horizontal, 24)

            TrimSliderView(
                duration: viewModel.duration,
                startTime: Binding(
                    get: { viewModel.startTime },
                    set: { viewModel.setStartTime($0) }
                ),
                endTime: Binding(
                    get: { viewModel.endTime },
                    set: { viewModel.setEndTime($0) }
                ),
                currentTime: viewModel.currentTime,
                onChangeStart: { viewModel.setStartTime($0) },
                onChangeEnd: { viewModel.setEndTime($0) },
                onScrub: { viewModel.seek(to: $0) }
            )
            .padding(.horizontal, 16)
        }
        .padding(.top, 24)
    }

    private var actionArea: some View {
        HStack(spacing: 24) {
            Button {
                viewModel.togglePlayPause()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 44)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }
            Button {
                Task { await viewModel.export() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                    Text("書き出す")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.yellow, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }

    private func timeChip(_ time: TimeInterval, label: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Text(TimeFormatter.format(time))
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
        }
    }

    private var exportingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView(value: viewModel.exportProgress)
                    .progressViewStyle(.linear)
                    .tint(.yellow)
                    .frame(width: 200)
                Text("書き出し中… \(Int(viewModel.exportProgress * 100))%")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
