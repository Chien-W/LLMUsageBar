import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state = AppState.shared
    @Environment(\.colorScheme) var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏
            headerView
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            Divider()
                .opacity(isDark ? 0.25 : 0.5)
            
            // 内容滚动区
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    switch state.selectedTab {
                    case .overview:
                        OverviewView()
                    case .accounts:
                        AccountsManageView()
                    case .settings:
                        SettingsView()
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 380, height: 530)
        // 关键：背景严格跟随系统窗口背景色，浅色模式为清新浅灰/白，深色模式为原生暗黑，不再强制全黑
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.needle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.20, green: 0.82, blue: 0.40))
                    Text("AI 用量与额度监控")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(NSColor.labelColor))
                }
                
                Spacer()
                
                // 快捷按钮：右上角加号添加新账号
                Button(action: {
                    state.newAccountName = ""
                    state.newAccountEmail = ""
                    state.newAccountApiKey = ""
                    state.isAddingAccount = true
                    state.selectedTab = .accounts
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("添加新账号")
            }
            
            // 导航切换
            HStack(spacing: 4) {
                ForEach(AppState.TabItem.allCases, id: \.self) { tab in
                    Button(action: {
                        state.selectedTab = tab
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 10))
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: state.selectedTab == tab ? .semibold : .regular))
                        }
                        .padding(.vertical, 4.5)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            state.selectedTab == tab
                                ? (isDark ? Color.white.opacity(0.14) : Color.white)
                                : Color.clear
                        )
                        .cornerRadius(6)
                        .shadow(color: state.selectedTab == tab && !isDark ? Color.black.opacity(0.08) : Color.clear, radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(
                        state.selectedTab == tab
                            ? Color(NSColor.labelColor)
                            : Color(NSColor.secondaryLabelColor)
                    )
                }
            }
            .padding(2.5)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}
