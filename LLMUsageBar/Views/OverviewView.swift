import SwiftUI

struct OverviewView: View {
    @ObservedObject var state = AppState.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            // 循环呈现各个独立账号卡片（如主 Google 账号内部完整呈现 Gemini 与 Claude/GPT 两个模型组）
            ForEach(state.accounts) { acc in
                AccountCardView(
                    account: acc,
                    status: state.statuses[acc.id],
                    onRefresh: {
                        Task {
                            await state.refreshAll()
                        }
                    }
                )
            }
            
            // 底部实时校准状态栏
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(state.isIdeConnected ? Color(red: 0.20, green: 0.82, blue: 0.40) : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(state.ideConnectionStatusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await state.refreshAll()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(state.isRefreshing ? 360 : 0))
                            .animation(state.isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: state.isRefreshing)
                        Text(state.isRefreshing ? "核对中..." : "立即刷新")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(state.isRefreshing)
            }
            .padding(.top, 4)
            .padding(.horizontal, 2)
        }
    }
}
