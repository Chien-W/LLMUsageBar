import Foundation

enum ProviderType: String, Codable, CaseIterable, Identifiable {
    case google = "Google (Gemini)"
    case zhipu = "智谱 (zai)"
    case custom = "自定义提供商"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .google: return "sparkles"
        case .zhipu: return "bolt.shield.fill"
        case .custom: return "cpu"
        }
    }
}

struct ModelGroupQuota: Identifiable, Codable, Equatable {
    var id: String                       // 如 "gemini", "claude_gpt"
    var name: String                     // 如 "Gemini 模型", "Claude 和 GPT 模型"
    var weeklyPct: Int                   // 0 ~ 100
    var fiveHourPct: Int                 // 0 ~ 100
    var weeklyDisabled: Bool? = false    // 是否已停用/不适用（如周额度用尽后 5 小时限额不适用）
    var fiveHourDisabled: Bool? = false  // 是否已停用/不适用
    var weeklyResetTarget: Date
    var fiveHourResetTarget: Date
    var weeklyDescription: String
    var fiveHourDescription: String
    
    init(
        id: String,
        name: String,
        weeklyPct: Int,
        fiveHourPct: Int,
        weeklyDisabled: Bool? = false,
        fiveHourDisabled: Bool? = false,
        weeklyResetTarget: Date,
        fiveHourResetTarget: Date,
        weeklyDescription: String,
        fiveHourDescription: String
    ) {
        self.id = id
        self.name = name
        self.weeklyPct = weeklyPct
        self.fiveHourPct = fiveHourPct
        self.weeklyDisabled = weeklyDisabled
        self.fiveHourDisabled = fiveHourDisabled
        self.weeklyResetTarget = weeklyResetTarget
        self.fiveHourResetTarget = fiveHourResetTarget
        self.weeklyDescription = weeklyDescription
        self.fiveHourDescription = fiveHourDescription
    }
}

struct Account: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String                     // 账号展示名称，如 "Google AI Pro"
    var email: String                    // 绑定邮箱，如 "javier.wu.edu@gmail.com"
    var provider: ProviderType
    var apiKey: String
    var isEnabled: Bool
    var createdAt: Date
    var modelGroups: [ModelGroupQuota]
    
    init(
        id: UUID = UUID(),
        name: String,
        email: String = "",
        provider: ProviderType = .google,
        apiKey: String = "",
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        modelGroups: [ModelGroupQuota] = []
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.provider = provider
        self.apiKey = apiKey
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.modelGroups = modelGroups
    }
}

struct QuotaWindowInfo: Identifiable {
    var id: String { title }
    var title: String              // 如 "剩余周额度"
    var percentage: Int            // 0 ~ 100
    var resetDescription: String   // 实时计算的倒计时文案
    var isDisabled: Bool = false   // 当为 true 时，表示当前不适用（不展示百分比和圆环，与官方 IDE 一致）
    var isDepleted: Bool { percentage <= 0 }
    
    init(
        title: String,
        percentage: Int,
        resetDescription: String,
        isDisabled: Bool = false
    ) {
        self.title = title
        self.percentage = percentage
        self.resetDescription = resetDescription
        self.isDisabled = isDisabled
    }
}

struct ModelGroupRuntimeStatus: Identifiable {
    var id: String
    var name: String
    var weeklyQuota: QuotaWindowInfo
    var fiveHourQuota: QuotaWindowInfo
}

struct AccountRuntimeStatus: Identifiable {
    let id: UUID
    var isConnected: Bool = true
    var message: String = "IDE 实时直连"
    var groups: [ModelGroupRuntimeStatus] = []
    var lastUpdated: Date? = nil
}
