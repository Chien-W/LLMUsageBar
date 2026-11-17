import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var accounts: [Account] = []
    @Published var statuses: [UUID: AccountRuntimeStatus] = [:]
    @Published var isRefreshing = false
    @Published var selectedTab: TabItem = .overview
    @Published var ideConnectionStatusText: String = "正在连接本地 IDE 语言服务..."
    @Published var isIdeConnected: Bool = false
    
    // 全局设置
    @Published var refreshInterval: TimeInterval = 15
    @Published var statusDisplayMode: ConfigManager.StatusDisplayMode = .iconOnly
    
    // 添加账号视图状态
    @Published var isAddingAccount = false
    @Published var newAccountName = ""
    @Published var newAccountEmail = ""
    @Published var newAccountApiKey = ""
    @Published var newAccountProvider: ProviderType = .google
    @Published var isShowingApiKey = false
    @Published var isTestingConnection = false
    @Published var testResultMsg: String? = nil
    
    private var timerCancellable: AnyCancellable?
    
    enum TabItem: String, CaseIterable {
        case overview = "监控概览"
        case accounts = "账号管理"
        case settings = "系统设置"
        
        var iconName: String {
            switch self {
            case .overview: return "gauge.with.needle.fill"
            case .accounts: return "person.2.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    init() {
        self.refreshInterval = ConfigManager.shared.refreshInterval
        self.statusDisplayMode = ConfigManager.shared.statusDisplayMode
        
        var loaded = ConfigManager.shared.accounts
        if loaded.isEmpty {
            let now = Date()
            let defaultGoogleAccount = Account(
                name: "Google AI Pro",
                email: "javier.wu.edu@gmail.com",
                provider: .google,
                apiKey: "",
                isEnabled: true,
                createdAt: now,
                modelGroups: [
                    ModelGroupQuota(
                        id: "gemini",
                        name: "Gemini 模型",
                        weeklyPct: 91,
                        fiveHourPct: 99,
                        weeklyResetTarget: now.addingTimeInterval(6 * 86400 + 8 * 3600),
                        fiveHourResetTarget: now.addingTimeInterval(4 * 3600 + 57 * 60),
                        weeklyDescription: "您已使用部分周额度，将在 6 天 8 小时后完全刷新。",
                        fiveHourDescription: "您已使用部分 5 小时额度，将在 4 小时 57 分钟后完全刷新。"
                    ),
                    ModelGroupQuota(
                        id: "claude_gpt",
                        name: "Claude 和 GPT 模型",
                        weeklyPct: 0,
                        fiveHourPct: 0,
                        weeklyResetTarget: now.addingTimeInterval(8 * 3600 + 10 * 60),
                        fiveHourResetTarget: now.addingTimeInterval(4 * 3600 + 54 * 60),
                        weeklyDescription: "You have hit your 5-hour limit, so the weekly limit does not currently apply. Your 5-hour limit will refresh in 8 小时, 10 分钟.",
                        fiveHourDescription: "You have hit your 5-hour limit, it will refresh in 4 小时, 54 分钟. If on a supported paid plan, you can use AI credits in the interim."
                    )
                ]
            )
            loaded = [defaultGoogleAccount]
            ConfigManager.shared.accounts = loaded
        }
        
        // 自动发现并挂载本地已配置的 OpenAI Codex
        if !loaded.contains(where: { $0.provider == .codex }) && CodexService.shared.isInstalled() {
            let authInfo = CodexService.shared.readAuthJsonInfo()
            let codexAccount = Account(
                name: "OpenAI Codex",
                email: authInfo.email ?? "",
                provider: .codex,
                apiKey: "",
                isEnabled: true,
                createdAt: Date(),
                modelGroups: [
                    ModelGroupQuota(
                        id: "codex_quota",
                        name: "Codex 模型用量",
                        weeklyPct: 0,
                        fiveHourPct: 100,
                        weeklyDisabled: false,
                        fiveHourDisabled: true,
                        weeklyResetTarget: Date().addingTimeInterval(30 * 86400),
                        fiveHourResetTarget: Date(),
                        weeklyDescription: "正在与 Codex 客户端核对...",
                        fiveHourDescription: "正在与 Codex 客户端核对...",
                        weeklyTitle: "剩余周期限额",
                        fiveHourTitle: "调用权限与用量"
                    )
                ]
            )
            loaded.append(codexAccount)
            ConfigManager.shared.accounts = loaded
        }
        
        self.accounts = loaded
        
        let now = Date()
        recalculateRealtimeCountdowns(at: now)
        
        setupRealtimeTimer()
        
        Task {
            await self.refreshAll()
        }
    }
    
    func setupRealtimeTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.fetchRealtimeQuota()
                }
            }
    }
    
    func refreshAll() async {
        isRefreshing = true
        await fetchRealtimeQuota()
        isRefreshing = false
    }
    
    func fetchRealtimeQuota() async {
        let now = Date()
        
        // 1. 直连本地 Antigravity 语言服务器 RPC
        if let live = await LocalIDEService.shared.fetchQuota() {
            self.isIdeConnected = true
            let portStr = "Port \(live.port)"
            self.ideConnectionStatusText = "🟢 IDE 官方接口实时核对中 (\(portStr))"
            
            // 找到或关联与当前 IDE 登录邮箱匹配的 Google 账号（支持多账号切换）
            let targetAccIdx: Int?
            if let uEmail = live.userEmail, !uEmail.isEmpty,
               let matchIdx = accounts.firstIndex(where: { $0.provider == .google && $0.email.lowercased() == uEmail.lowercased() }) {
                targetAccIdx = matchIdx
            } else if let ideIdx = accounts.firstIndex(where: { $0.provider == .google && $0.apiKey.isEmpty }) {
                targetAccIdx = ideIdx
            } else {
                targetAccIdx = accounts.firstIndex(where: { $0.provider == .google })
            }
            
            if let accIdx = targetAccIdx {
                if let uEmail = live.userEmail, !uEmail.isEmpty {
                    accounts[accIdx].email = uEmail
                }
                if let uTier = live.userTier, !uTier.isEmpty {
                    if accounts[accIdx].name.isEmpty || accounts[accIdx].name.contains("Google AI") || accounts[accIdx].name == "Google (Gemini)" {
                        accounts[accIdx].name = uTier
                    }
                }
                
                var updatedGroups: [ModelGroupQuota] = []
                
                for rpcGroup in live.groups {
                    let gNameLower = rpcGroup.displayName.lowercased()
                    let targetGroupId: String
                    let targetGroupName: String
                    let wTitle: String
                    
                    if gNameLower.contains("argon") {
                        targetGroupId = "gemini_argon"
                        targetGroupName = "Gemini 4 Argon"
                        wTitle = "Gemini 4 Argon 剩余周额度"
                    } else if gNameLower.contains("claude") || gNameLower.contains("gpt") || gNameLower.contains("3p") {
                        targetGroupId = "claude_gpt"
                        targetGroupName = "Claude 和 GPT 模型"
                        wTitle = "剩余周额度"
                    } else if gNameLower.contains("gemini") {
                        targetGroupId = "gemini"
                        targetGroupName = "Gemini 模型"
                        wTitle = "剩余周额度"
                    } else {
                        targetGroupId = rpcGroup.displayName
                            .lowercased()
                            .replacingOccurrences(of: " ", with: "_")
                        targetGroupName = rpcGroup.displayName
                        wTitle = "剩余周额度"
                    }
                    
                    var weeklyBucket = rpcGroup.buckets.first { $0.window.lowercased().contains("week") }
                    let fiveHourBucket = rpcGroup.buckets.first { $0.window.lowercased().contains("5h") }
                    
                    if weeklyBucket == nil && fiveHourBucket == nil && !rpcGroup.buckets.isEmpty {
                        weeklyBucket = rpcGroup.buckets[0]
                    }
                    
                    let hasFiveHour = fiveHourBucket != nil
                    
                    let wDisabled = weeklyBucket?.isDisabled ?? false
                    let fDisabled = fiveHourBucket?.isDisabled ?? false
                    let wPct = wDisabled ? 0 : (weeklyBucket?.percentage ?? 100)
                    let fPct = fDisabled ? 0 : (fiveHourBucket?.percentage ?? 100)
                    let wDate = weeklyBucket?.resetTime ?? now.addingTimeInterval(7 * 86400)
                    let fDate = fiveHourBucket?.resetTime ?? now.addingTimeInterval(5 * 3600)
                    let wDesc = weeklyBucket?.localizedDescription ?? ""
                    let fDesc = fiveHourBucket?.localizedDescription ?? ""
                    
                    updatedGroups.append(ModelGroupQuota(
                        id: targetGroupId,
                        name: targetGroupName,
                        weeklyPct: wPct,
                        fiveHourPct: fPct,
                        weeklyDisabled: wDisabled,
                        fiveHourDisabled: fDisabled,
                        weeklyResetTarget: wDate,
                        fiveHourResetTarget: fDate,
                        weeklyDescription: wDesc,
                        fiveHourDescription: fDesc,
                        weeklyTitle: wTitle,
                        fiveHourTitle: "剩余 5 小时限额",
                        hasFiveHourQuota: hasFiveHour
                    ))
                }
                
                accounts[accIdx].modelGroups = updatedGroups
                ConfigManager.shared.accounts = accounts
            }
        } else {
            self.isIdeConnected = false
            self.ideConnectionStatusText = "🟡 等待 IDE 语言服务就绪"
        }
        
        // 2. 对于配置了 API Key 的其他独立账号（如智谱 AI 或手动 Gemini Key），拉取其真实状态
        for acc in accounts {
            if acc.provider == .zhipu && !acc.apiKey.isEmpty {
                let res = await ZhipuService.shared.fetchQuotaDetail(apiKey: acc.apiKey)
                if let idx = accounts.firstIndex(where: { $0.id == acc.id }) {
                    var groups: [ModelGroupQuota] = []
                    
                    if let f = res.fiveHourQuota, let w = res.weeklyQuota {
                        groups.append(ModelGroupQuota(
                            id: "zhipu_coding",
                            name: "智谱 Coding Plan 模型用量",
                            weeklyPct: w.remainingPct,
                            fiveHourPct: f.remainingPct,
                            weeklyResetTarget: w.resetDate ?? now.addingTimeInterval(7 * 86400),
                            fiveHourResetTarget: f.resetDate ?? now.addingTimeInterval(5 * 3600),
                            weeklyDescription: w.description,
                            fiveHourDescription: f.description
                        ))
                    } else if let w = res.weeklyQuota {
                        groups.append(ModelGroupQuota(
                            id: "zhipu_coding",
                            name: "智谱 Coding Plan 模型用量",
                            weeklyPct: w.remainingPct,
                            fiveHourPct: 100,
                            weeklyResetTarget: w.resetDate ?? now.addingTimeInterval(7 * 86400),
                            fiveHourResetTarget: now.addingTimeInterval(5 * 3600),
                            weeklyDescription: w.description,
                            fiveHourDescription: "5小时限额充足"
                        ))
                    }
                    
                    if let m = res.mcpQuota {
                        groups.append(ModelGroupQuota(
                            id: "zhipu_mcp",
                            name: "智谱 MCP 每月额度",
                            weeklyPct: m.remainingPct,
                            fiveHourPct: m.remainingPct,
                            weeklyResetTarget: m.resetDate ?? now.addingTimeInterval(30 * 86400),
                            fiveHourResetTarget: m.resetDate ?? now.addingTimeInterval(30 * 86400),
                            weeklyDescription: m.description,
                            fiveHourDescription: "每月搜索与网页读取工具用量"
                        ))
                    }
                    
                    if !groups.isEmpty {
                        accounts[idx].modelGroups = groups
                        ConfigManager.shared.accounts = accounts
                    }
                }
            } else if acc.provider == .codex {
                if acc.apiKey.isEmpty {
                    // 本地 Codex CLI 直连
                    if let codexRes = await CodexService.shared.fetchQuota() {
                        if let idx = accounts.firstIndex(where: { $0.id == acc.id }) {
                            if !codexRes.email.isEmpty {
                                accounts[idx].email = codexRes.email
                            }
                            let rawPlan = codexRes.planType.lowercased()
                            let displayPlan: String
                            if rawPlan == "prolite" {
                                displayPlan = "Pro Lite"
                            } else if !rawPlan.isEmpty {
                                displayPlan = rawPlan.capitalized
                            } else {
                                displayPlan = "Free"
                            }
                            accounts[idx].name = "OpenAI Codex (\(displayPlan))"
                            
                            let groups = CodexService.shared.buildModelGroups(from: codexRes, now: now)
                            accounts[idx].modelGroups = groups
                            ConfigManager.shared.accounts = accounts
                        }
                    }
                } else {
                    let check = await CodexService.shared.checkOpenAIKey(apiKey: acc.apiKey)
                    if let idx = accounts.firstIndex(where: { $0.id == acc.id }), !accounts[idx].modelGroups.isEmpty {
                        accounts[idx].modelGroups[0].weeklyDescription = check.message
                    }
                }
            } else if acc.provider == .google && !acc.apiKey.isEmpty {
                let res = await GeminiService.shared.checkConnection(apiKey: acc.apiKey)
                if let idx = accounts.firstIndex(where: { $0.id == acc.id }) {
                    let desc = res.isConnected
                        ? "检测到 \(res.modelsCount) 个可用模型 (网络延迟 \(res.latencyMs)ms)"
                        : "连接异常: \(res.message)"
                    let statusDesc = res.isConnected
                        ? "API Key 授权有效，随时可用于模型推理"
                        : "无法访问 Google API: \(res.message)"
                    
                    let grp = ModelGroupQuota(
                        id: "gemini_api_\(acc.id.uuidString.prefix(6))",
                        name: "Gemini API (Google AI Studio)",
                        weeklyPct: res.isConnected ? 100 : 0,
                        fiveHourPct: res.isConnected ? 100 : 0,
                        weeklyDisabled: false,
                        fiveHourDisabled: false,
                        weeklyResetTarget: now.addingTimeInterval(30 * 86400),
                        fiveHourResetTarget: now.addingTimeInterval(5 * 3600),
                        weeklyDescription: desc,
                        fiveHourDescription: statusDesc,
                        weeklyTitle: "模型库与网络延迟",
                        fiveHourTitle: "API 密钥调用权限",
                        hasFiveHourQuota: true
                    )
                    accounts[idx].modelGroups = [grp]
                    ConfigManager.shared.accounts = accounts
                }
            }
        }
        
        recalculateRealtimeCountdowns(at: now)
        AppDelegate.shared?.updateStatusItemTitle()
    }
    
    private func recalculateRealtimeCountdowns(at now: Date) {
        for acc in accounts {
            var groupStatuses: [ModelGroupRuntimeStatus] = []
            
            for grp in acc.modelGroups {
                let wQuota = QuotaWindowInfo(
                    title: grp.effectiveWeeklyTitle,
                    percentage: grp.weeklyPct,
                    resetDescription: grp.weeklyDescription.isEmpty ? "正在与官方接口核对..." : grp.weeklyDescription,
                    isDisabled: grp.weeklyDisabled ?? false
                )
                
                let fQuota: QuotaWindowInfo?
                if grp.hasFiveHourQuota ?? true {
                    fQuota = QuotaWindowInfo(
                        title: grp.effectiveFiveHourTitle,
                        percentage: grp.fiveHourPct,
                        resetDescription: grp.fiveHourDescription.isEmpty ? "正在与官方接口核对..." : grp.fiveHourDescription,
                        isDisabled: grp.fiveHourDisabled ?? false
                    )
                } else {
                    fQuota = nil
                }
                
                groupStatuses.append(ModelGroupRuntimeStatus(
                    id: grp.id,
                    name: grp.name,
                    weeklyQuota: wQuota,
                    fiveHourQuota: fQuota
                ))
            }
            
            let isLocalIde = acc.provider == .google && acc.apiKey.isEmpty
            let isLocalCodex = acc.provider == .codex && acc.apiKey.isEmpty
            let isConn: Bool
            let msg: String
            
            if isLocalIde {
                let isCurrentIdeUser: Bool
                if let liveEmail = LocalIDEService.shared.cachedUserEmail, !liveEmail.isEmpty, !acc.email.isEmpty {
                    isCurrentIdeUser = acc.email.lowercased() == liveEmail.lowercased()
                } else {
                    isCurrentIdeUser = true
                }
                
                if isIdeConnected && isCurrentIdeUser {
                    isConn = true
                    msg = "IDE 实时直连"
                } else if isIdeConnected && !isCurrentIdeUser {
                    isConn = false
                    msg = "IDE 离线 (请在 IDE 切换此账号)"
                } else {
                    isConn = false
                    msg = "等待 IDE 启动"
                }
            } else if isLocalCodex {
                isConn = true
                msg = "Codex 本地直连"
            } else if acc.provider == .google && !acc.apiKey.isEmpty {
                let firstGrpDesc = acc.modelGroups.first?.weeklyDescription ?? ""
                let isOk = !firstGrpDesc.contains("连接异常") && !firstGrpDesc.contains("失败")
                isConn = isOk
                msg = isOk ? "API Key 在线" : "连接失败"
            } else {
                isConn = !acc.apiKey.isEmpty
                msg = "API Key 授权"
            }
            
            self.statuses[acc.id] = AccountRuntimeStatus(
                id: acc.id,
                isConnected: isConn,
                message: msg,
                groups: groupStatuses,
                lastUpdated: now
            )
        }
    }
    
    func addAccount(name: String, email: String, provider: ProviderType, apiKey: String) {
        let now = Date()
        var finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalName.isEmpty {
            if provider == .google {
                if apiKey.isEmpty {
                    finalName = !email.isEmpty ? "Google (\(email))" : "Google AI Pro (IDE)"
                } else {
                    finalName = !email.isEmpty ? "Gemini API (\(email))" : "Google Gemini API"
                }
            } else {
                finalName = provider.rawValue
            }
        }
        
        var groups: [ModelGroupQuota] = []
        if provider == .google {
            if apiKey.isEmpty {
                // IDE 直连/切换账号预设模型组
                groups = [
                    ModelGroupQuota(
                        id: "gemini",
                        name: "Gemini 模型",
                        weeklyPct: 100,
                        fiveHourPct: 100,
                        weeklyResetTarget: now.addingTimeInterval(7 * 86400),
                        fiveHourResetTarget: now.addingTimeInterval(5 * 3600),
                        weeklyDescription: "等待在 Antigravity 中切换登录此账号...",
                        fiveHourDescription: "等待在 Antigravity 中切换登录此账号...",
                        weeklyTitle: "剩余周额度",
                        fiveHourTitle: "剩余 5 小时限额",
                        hasFiveHourQuota: true
                    ),
                    ModelGroupQuota(
                        id: "claude_gpt",
                        name: "Claude 和 GPT 模型",
                        weeklyPct: 100,
                        fiveHourPct: 100,
                        weeklyResetTarget: now.addingTimeInterval(7 * 86400),
                        fiveHourResetTarget: now.addingTimeInterval(5 * 3600),
                        weeklyDescription: "等待在 Antigravity 中切换登录此账号...",
                        fiveHourDescription: "等待在 Antigravity 中切换登录此账号...",
                        weeklyTitle: "剩余周额度",
                        fiveHourTitle: "剩余 5 小时限额",
                        hasFiveHourQuota: true
                    ),
                    ModelGroupQuota(
                        id: "gemini_argon",
                        name: "Gemini 4 Argon",
                        weeklyPct: 100,
                        fiveHourPct: 100,
                        weeklyResetTarget: now.addingTimeInterval(7 * 86400),
                        fiveHourResetTarget: now.addingTimeInterval(5 * 3600),
                        weeklyDescription: "等待在 Antigravity 中切换登录此账号...",
                        fiveHourDescription: "等待在 Antigravity 中切换登录此账号...",
                        weeklyTitle: "Gemini 4 Argon 剩余周额度",
                        fiveHourTitle: "剩余 5 小时限额",
                        hasFiveHourQuota: false
                    )
                ]
            } else {
                // Google AI Studio API Key 账号
                groups = [
                    ModelGroupQuota(
                        id: "gemini_api",
                        name: "Gemini API (Google AI Studio)",
                        weeklyPct: 100,
                        fiveHourPct: 100,
                        weeklyResetTarget: now.addingTimeInterval(30 * 86400),
                        fiveHourResetTarget: now.addingTimeInterval(5 * 3600),
                        weeklyDescription: "正在连接 Google AI Studio...",
                        fiveHourDescription: "API 密钥权限核对中...",
                        weeklyTitle: "模型库与网络延迟",
                        fiveHourTitle: "API 密钥调用权限",
                        hasFiveHourQuota: true
                    )
                ]
            }
        } else if provider == .codex {
            groups = [
                ModelGroupQuota(
                    id: "codex_quota",
                    name: "Codex 模型用量",
                    weeklyPct: 0,
                    fiveHourPct: 100,
                    weeklyDisabled: false,
                    fiveHourDisabled: true,
                    weeklyResetTarget: now.addingTimeInterval(30 * 86400),
                    fiveHourResetTarget: now,
                    weeklyDescription: apiKey.isEmpty ? "正在与 Codex 客户端核对..." : "OpenAI API 待测试",
                    fiveHourDescription: "普通调用权限正常",
                    weeklyTitle: "剩余周期限额",
                    fiveHourTitle: "调用权限与用量",
                    hasFiveHourQuota: true
                )
            ]
        } else if provider == .zhipu {
            groups = [
                ModelGroupQuota(
                    id: "zhipu_tokens",
                    name: "智谱 GLM 模型用量",
                    weeklyPct: 100,
                    fiveHourPct: 100,
                    weeklyResetTarget: now.addingTimeInterval(30 * 86400),
                    fiveHourResetTarget: now.addingTimeInterval(5 * 3600),
                    weeklyDescription: "Token 余额监控正常。",
                    fiveHourDescription: "并发请求数在合理限度内。",
                    weeklyTitle: "剩余周额度",
                    fiveHourTitle: "剩余 5 小时限额",
                    hasFiveHourQuota: true
                )
            ]
        }
        
        var finalEmail = email
        if provider == .codex && email.isEmpty {
            finalEmail = CodexService.shared.readAuthJsonInfo().email ?? ""
        }
        
        let newAcc = Account(
            name: finalName,
            email: finalEmail,
            provider: provider,
            apiKey: apiKey,
            isEnabled: true,
            createdAt: now,
            modelGroups: groups
        )
        
        accounts.append(newAcc)
        ConfigManager.shared.accounts = accounts
        recalculateRealtimeCountdowns(at: now)
        Task {
            await self.fetchRealtimeQuota()
        }
    }
    
    func deleteAccount(id: UUID) {
        accounts.removeAll { $0.id == id }
        statuses.removeValue(forKey: id)
        ConfigManager.shared.accounts = accounts
        recalculateRealtimeCountdowns(at: Date())
    }
    
    func testNewAccountConnection() async {
        isTestingConnection = true
        testResultMsg = nil
        let key = newAccountApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = newAccountProvider
        
        if provider == .google {
            if key.isEmpty {
                if let live = await LocalIDEService.shared.fetchQuota() {
                    let emailStr = live.userEmail.map { "（当前已登录账号: \($0)）" } ?? ""
                    isTestingConnection = false
                    testResultMsg = "✅ 本地 IDE 语言服务连接正常！\(emailStr)"
                } else {
                    isTestingConnection = false
                    testResultMsg = "🟡 未检测到运行中的 IDE 语言服务，请确保 Antigravity 已打开"
                }
            } else {
                let res = await GeminiService.shared.checkConnection(apiKey: key)
                isTestingConnection = false
                testResultMsg = res.isConnected ? "✅ 连接成功！检测到 \(res.modelsCount) 个可用模型 (延迟 \(res.latencyMs)ms)" : "❌ 连接失败: \(res.message)"
            }
        } else if provider == .codex {
            if key.isEmpty {
                if let res = await CodexService.shared.fetchQuota() {
                    isTestingConnection = false
                    testResultMsg = "✅ 连接成功！检测到本地 Codex（\(res.planType.capitalized) 账号: \(res.email)），周期额度剩余 \(res.primaryRemainingPct)%"
                } else {
                    isTestingConnection = false
                    testResultMsg = "❌ 未检测到运行中的本地 Codex，请确保已安装并在终端运行过 codex login"
                }
            } else {
                let res = await CodexService.shared.checkOpenAIKey(apiKey: key)
                isTestingConnection = false
                testResultMsg = res.isConnected ? "✅ \(res.message)" : "❌ \(res.message)"
            }
        } else if provider == .zhipu {
            let res = await ZhipuService.shared.fetchQuotaDetail(apiKey: key)
            isTestingConnection = false
            if res.isConnected {
                let w = res.weeklyQuota?.remainingPct ?? 100
                let f = res.fiveHourQuota?.remainingPct ?? 100
                testResultMsg = "✅ 连接成功！周额度剩余 \(w)%，5小时限额剩余 \(f)%"
            } else {
                testResultMsg = "❌ 连接失败: \(res.message)"
            }
        } else {
            isTestingConnection = false
            testResultMsg = "✅ 自定义密钥格式已记录"
        }
    }
    
    func saveGlobalSettings() {
        ConfigManager.shared.refreshInterval = refreshInterval
        ConfigManager.shared.statusDisplayMode = statusDisplayMode
        setupRealtimeTimer()
        AppDelegate.shared?.updateStatusItemTitle()
    }
}
