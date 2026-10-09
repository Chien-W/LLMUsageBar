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
    var weeklyResetTarget: Date
    var fiveHourResetTarget: Date
    var weeklyDescription: String
    var fiveHourDescription: String
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
    var isDepleted: Bool { percentage <= 0 }
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
