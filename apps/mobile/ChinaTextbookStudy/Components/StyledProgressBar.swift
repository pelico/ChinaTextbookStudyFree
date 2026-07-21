import SwiftUI

/// Duolingo-style progress bar with animated green fill and rounded caps.
/// Replaces the stock `ProgressView` in the lesson runner.
struct StyledProgressBar: View {
    /// 0.0 ... 1.0
    let progress: Double
    var height: CGFloat = 16
    var fillColor: Color = DuoColors.primary
    var trackColor: Color = DuoColors.bgSofter

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(trackColor)
                    .frame(height: height)

                // Fill
                Capsule()
                    .fill(fillColor)
                    .frame(width: max(height, geo.size.width * CGFloat(min(1, max(0, progress)))),
                           height: height)
                    // Inner highlight for 3D effect
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(.white.opacity(0.30))
                            .frame(height: height * 0.4)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    }
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: progress)
    }
}
