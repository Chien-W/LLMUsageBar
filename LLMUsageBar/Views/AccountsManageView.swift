import SwiftUI

struct AccountsManageView: View {
    @ObservedObject var state = AppState.shared
    @Environment(\.colorScheme) var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(spacing: 12) {
            // 顶部操作栏
            HStack {
                Text("账号管理 (\(state.accounts.count))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(NSColor.labelColor))
                
                Spacer()
                
                Button(action: {
                    state.newAccountName = ""
                    state.newAccountEmail = ""
                    state.newAccountApiKey = ""
                    state.testResultMsg = nil
                    state.isAddingAccount.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: state.isAddingAccount ? "minus.circle.fill" : "plus.circle.fill")
                        Text(state.isAddingAccount ? "收起" : "添加账号")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            // 添加新账号表单（核心配置凭据：API Key）
            if state.isAddingAccount {
                addAccountForm
            }
            
            // 账号列表
            VStack(spacing: 8) {
                ForEach(state.accounts) { acc in
                    accountRow(acc: acc)
                }
            }
        }
    }
    
    private var addAccountForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("✨ 添加新账号凭据")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(NSColor.labelColor))
                
                Spacer()
                
                // 快捷获取 Key 链接
                Button(action: {
                    openApiKeyPortal(for: state.newAccountProvider)
                }) {
                    HStack(spacing: 3) {
                        Text("获取 Key")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            
            // 1. 服务商选择
            HStack {
                Text("服务商:")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .frame(width: 54, alignment: .leading)
                
                Picker("", selection: $state.newAccountProvider) {
                    ForEach(ProviderType.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
            }
            
            // 2. API Key (核心必填凭据)
            HStack {
                Text("API Key:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(NSColor.labelColor))
                    .frame(width: 54, alignment: .leading)
                
                HStack {
                    if state.isShowingApiKey {
                        TextField(apiKeyPlaceholder(for: state.newAccountProvider), text: $state.newAccountApiKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                    } else {
                        SecureField(apiKeyPlaceholder(for: state.newAccountProvider), text: $state.newAccountApiKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    
                    Button(action: {
                        state.isShowingApiKey.toggle()
                    }) {
                        Image(systemName: state.isShowingApiKey ? "eye.slash" : "eye")
                            .font(.system(size: 11))
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                    }
                    .buttonStyle(.plain)
                    .help(state.isShowingApiKey ? "隐藏密钥" : "显示明文")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.8)
                )
            }
            
            // 3. 账号备注名
            HStack {
                Text("名称:")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .frame(width: 54, alignment: .leading)
                
                TextField("如: 备用 Gemini Pro / 智谱团队账号", text: $state.newAccountName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }
            
            // 4. 账号邮箱/备注（选填）
            HStack {
                Text("邮箱/备注:")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .frame(width: 54, alignment: .leading)
                
                TextField("选填，仅作本地身份辨识，如: user@gmail.com", text: $state.newAccountEmail)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }
            
            if let result = state.testResultMsg {
                Text(result)
                    .font(.system(size: 10))
                    .foregroundColor(result.contains("成功") ? .green : .red)
                    .padding(.horizontal, 2)
            }
            
            // 底部按钮栏
            HStack {
                Button("取消") {
                    state.isAddingAccount = false
                    state.testResultMsg = nil
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                
                Spacer()
                
                // 测试连接
                Button(action: {
                    Task {
                        await state.testNewAccountConnection()
                    }
                }) {
                    if state.isTestingConnection {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("测试连接")
                    }
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.newAccountApiKey.trimmingCharacters(in: .whitespaces).isEmpty || state.isTestingConnection)
                
                // 确认保存
                Button("确认保存") {
                    let key = state.newAccountApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.addAccount(
                        name: state.newAccountName,
                        email: state.newAccountEmail,
                        provider: state.newAccountProvider,
                        apiKey: key
                    )
                    state.isAddingAccount = false
                    state.testResultMsg = nil
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(state.newAccountApiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func accountRow(acc: Account) -> some View {
        let isLocalIdeAccount = acc.apiKey.isEmpty && acc.provider == .google
        
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: acc.provider.iconName)
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(acc.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(NSColor.labelColor))
                        
                        // 凭据类型徽章
                        if isLocalIdeAccount {
                            Text("⚡️ IDE 直连 (免 Key)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Color(red: 0.20, green: 0.82, blue: 0.40))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.12))
                                .cornerRadius(3)
                        } else {
                            Text("🔑 API Key 授权")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.12))
                                .cornerRadius(3)
                        }
                    }
                    
                    if !acc.email.isEmpty {
                        Text(acc.email)
                            .font(.system(size: 10))
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                    } else if !acc.apiKey.isEmpty {
                        Text("密钥: \(maskedKey(acc.apiKey))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                    }
                }
                
                Spacer()
                
                // 仅剩一个账号时不可删除
                if state.accounts.count > 1 {
                    Button(action: {
                        state.deleteAccount(id: acc.id)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("删除该账号")
                }
            }
            
            // 模型组概览标签
            HStack(spacing: 6) {
                ForEach(acc.modelGroups) { grp in
                    HStack(spacing: 3) {
                        Text(grp.name)
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(grp.weeklyPct)% / \(grp.fiveHourPct)%")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
                    .cornerRadius(4)
                }
                
                Spacer()
                
                Button("立即核对") {
                    Task {
                        await state.refreshAll()
                    }
                }
                .font(.system(size: 9))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.8)
                )
        )
    }
    
    private func apiKeyPlaceholder(for provider: ProviderType) -> String {
        switch provider {
        case .google:
            return "粘贴 AIzaSy 开头的 Gemini API Key"
        case .zhipu:
            return "粘贴 智谱清言 API Key (id.secret)"
        case .custom:
            return "粘贴 API 凭据密钥 (sk-...)"
        }
    }
    
    private func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return "••••••••" }
        let start = key.prefix(4)
        let end = key.suffix(4)
        return "\(start)...\(end)"
    }
    
    private func openApiKeyPortal(for provider: ProviderType) {
        let urlStr: String
        switch provider {
        case .google:
            urlStr = "https://aistudio.google.com/apikey"
        case .zhipu:
            urlStr = "https://open.bigmodel.cn/usercenter/apikeys"
        case .custom:
            urlStr = "https://platform.openai.com/api-keys"
        }
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }
}
