import SwiftUI

struct CircularProgressView: View {
    let progress: Double // 0.0 ~ 100.0
    let lineWidth: CGFloat
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            
            Circle()
                .trim(from: 0, to: min(max(CGFloat(progress / 100.0), 0), 1))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)
        }
    }
}
