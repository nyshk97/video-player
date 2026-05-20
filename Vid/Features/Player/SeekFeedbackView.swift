import SwiftUI

struct SeekFeedbackView: View {
    let seconds: TimeInterval
    @State private var opacity: Double = 1.0

    var body: some View {
        HStack {
            if seconds < 0 { content; Spacer() } else { Spacer(); content }
        }
        .padding(.horizontal, 40)
        .allowsHitTesting(false)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) {
                opacity = 0
            }
        }
    }

    private var content: some View {
        VStack(spacing: 4) {
            Image(systemName: seconds < 0 ? "gobackward.10" : "goforward.10")
                .font(.system(size: 36, weight: .semibold))
            Text(String(format: "%+.0f秒", seconds))
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(.black.opacity(0.55), in: Circle())
    }
}
