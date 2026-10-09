import SwiftUI

struct SettingsView: View {
    @ObservedObject var state = AppState.shared
    
    var body: some View {
        VStack(spacing: 12) {
            // 系统参数卡片
            VStack(alignment: .leading, spacing: 10) {
                Text("运行偏好设置")
                    .font(.system(size: 12, weight: .bold))
                
                HStack {
                    Text("自动刷新间隔")
                        .font(.system(size: 11))
                    Spacer()
                    Picker("", selection: $state.refreshInterval) {
                        Text("1 分钟").tag(TimeInterval(60))
                        Text("3 分钟").tag(TimeInterval(180))
                        Text("5 分钟").tag(TimeInterval(300))
                        Text("15 分钟").tag(TimeInterval(900))
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 90)
                    .onChange(of: state.refreshInterval) { _, _ in
                        state.saveGlobalSettings()
                    }
                }
                
                Divider()
                
                HStack {
                    Text("菜单栏显示样式")
                        .font(.system(size: 11))
                    Spacer()
                    Picker("", selection: $state.statusDisplayMode) {
                        ForEach(ConfigManager.StatusDisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 90)
                    .onChange(of: state.statusDisplayMode) { _, _ in
                        state.saveGlobalSettings()
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
            
            // 快捷控制台链接
            VStack(alignment: .leading, spacing: 6) {
                Text("服务商官方控制台")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Button(action: {
                        if let url = URL(string: "https://open.bigmodel.cn/usercenter/apikeys") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.shield.fill")
                                .foregroundColor(Color(red: 0.0, green: 0.83, blue: 0.67))
                            Text("智谱开放平台")
                        }
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: {
                        if let url = URL(string: "https://aistudio.google.com/apikey") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.blue)
                            Text("Google AI Studio")
                        }
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
            
            // 底部操作
            HStack {
                Button("退出程序") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11))
                .foregroundColor(.red)
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("v1.2.0 · macOS 原生版")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
    }
}
