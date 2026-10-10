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
            
            // 找到或关联当前 Google 账号
            if let accIdx = accounts.firstIndex(where: { $0.provider == .google }) {
                if let uEmail = live.userEmail, !uEmail.isEmpty {
                    accounts[accIdx].email = uEmail
                }
                if let uTier = live.userTier, !uTier.isEmpty {
                    accounts[accIdx].name = uTier
                }
                
                var updatedGroups: [ModelGroupQuota] = accounts[accIdx].modelGroups
                
                for rpcGroup in live.groups {
                    let gNameLower = rpcGroup.displayName.lowercased()
                    let isGemini = gNameLower.contains("gemini")
                    let targetGroupId = isGemini ? "gemini" : "claude_gpt"
                    let targetGroupName = isGemini ? "Gemini 模型" : "Claude 和 GPT 模型"
                    
                    var weeklyBucket = rpcGroup.buckets.first { $0.window.lowercased().contains("week") }
                    var fiveHourBucket = rpcGroup.buckets.first { $0.window.lowercased().contains("5h") }
                    
                    if weeklyBucket == nil && rpcGroup.buckets.count > 0 { weeklyBucket = rpcGroup.buckets[0] }
                    if fiveHourBucket == nil && rpcGroup.buckets.count > 1 { fiveHourBucket = rpcGroup.buckets[1] }
                    
                    let wDisabled = weeklyBucket?.isDisabled ?? false
                    let fDisabled = fiveHourBucket?.isDisabled ?? false
                    let wPct = wDisabled ? 0 : (weeklyBucket?.percentage ?? 100)
                    let fPct = fDisabled ? 0 : (fiveHourBucket?.percentage ?? 100)
                    let wDate = weeklyBucket?.resetTime ?? now.addingTimeInterval(7 * 86400)
                    let fDate = fiveHourBucket?.resetTime ?? now.addingTimeInterval(5 * 3600)
                    let wDesc = weeklyBucket?.localizedDescription ?? ""
                    let fDesc = fiveHourBucket?.localizedDescription ?? ""
                    
                    if let grpIdx = updatedGroups.firstIndex(where: { $0.id == targetGroupId }) {
                        updatedGroups[grpIdx].weeklyPct = wPct
                        updatedGroups[grpIdx].fiveHourPct = fPct
                        updatedGroups[grpIdx].weeklyDisabled = wDisabled
                        updatedGroups[grpIdx].fiveHourDisabled = fDisabled
                        updatedGroups[grpIdx].weeklyResetTarget = wDate
                        updatedGroups[grpIdx].fiveHourResetTarget = fDate
                        updatedGroups[grpIdx].weeklyDescription = wDesc
                        updatedGroups[grpIdx].fiveHourDescription = fDesc
                    } else {
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
                            fiveHourDescription: fDesc
                        ))
                    }
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
            } else if acc.provider == .google && !acc.apiKey.isEmpty {
                let res = await GeminiService.shared.checkConnection(apiKey: acc.apiKey)
                if let idx = accounts.firstIndex(where: { $0.id == acc.id }), !accounts[idx].modelGroups.isEmpty {
                    accounts[idx].modelGroups[0].weeklyDescription = "可用模型: \(res.modelsCount) 个 (延迟 \(res.latencyMs)ms)"
                    accounts[idx].modelGroups[0].fiveHourDescription = res.message
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
                    title: "剩余周额度",
                    percentage: grp.weeklyPct,
                    resetDescription: grp.weeklyDescription.isEmpty ? "正在与官方接口核对..." : grp.weeklyDescription,
                    isDisabled: grp.weeklyDisabled ?? false
                )
                
                let fQuota = QuotaWindowInfo(
                    title: "剩余 5 小时限额",
                    percentage: grp.fiveHourPct,
                    resetDescription: grp.fiveHourDescription.isEmpty ? "正在与官方接口核对..." : grp.fiveHourDescription,
                    isDisabled: grp.fiveHourDisabled ?? false
                )
                
                groupStatuses.append(ModelGroupRuntimeStatus(
                    id: grp.id,
                    name: grp.name,
                    weeklyQuota: wQuota,
                    fiveHourQuota: fQuota
                ))
            }
            
            let isLocalIde = acc.provider == .google && acc.apiKey.isEmpty
            let isConn = isLocalIde ? isIdeConnected : !acc.apiKey.isEmpty
            let msg = isLocalIde ? (isIdeConnected ? "IDE 实时直连" : "等待 IDE 启动") : "API Key 授权"
            
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
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.rawValue : name
        
        var groups: [ModelGroupQuota] = []
        if provider == .google {
            groups = [
                ModelGroupQuota(
                    id: "gemini",
                    name: "Gemini 模型",
                    weeklyPct: 100,
                    fiveHourPct: 100,
                    weeklyResetTarget: now.addingTimeInterval(7 * 86400),
                    fiveHourResetTarget: now.addingTimeInterval(5 * 3600),
                    weeklyDescription: "额度充足，将在 7 天后刷新。",
                    fiveHourDescription: "额度充足，将在 5 小时后刷新。"
                ),
                ModelGroupQuota(
                    id: "claude_gpt",
                    name: "Claude 和 GPT 模型",
                    weeklyPct: 100,
                    fiveHourPct: 100,
                    weeklyResetTarget: now.addingTimeInterval(7 * 86400),
                    fiveHourResetTarget: now.addingTimeInterval(5 * 3600),
                    weeklyDescription: "额度充足，将在 7 天后刷新。",
                    fiveHourDescription: "额度充足，将在 5 小时后刷新。"
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
                    fiveHourDescription: "并发请求数在合理限度内。"
                )
            ]
        }
        
        let newAcc = Account(
            name: finalName,
            email: email,
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
            let res = await GeminiService.shared.checkConnection(apiKey: key)
            isTestingConnection = false
            testResultMsg = res.isConnected ? "✅ 连接成功！检测到 \(res.modelsCount) 个可用模型" : "❌ 连接失败: \(res.message)"
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
