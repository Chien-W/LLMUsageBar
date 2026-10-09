import Foundation

final class ConfigManager {
    static let shared = ConfigManager()
    
    private let defaults = UserDefaults.standard
    
    private let kAccounts = "kLLM_Accounts_V3"
    private let kRefreshInterval = "kLLM_RefreshInterval"
    private let kStatusDisplayMode = "kLLM_StatusDisplayMode"
    
    enum StatusDisplayMode: String, CaseIterable, Identifiable {
        case iconOnly = "仅图标"
        case accountCount = "账号数量"
        case connectionDot = "在线状态"
        
        var id: String { rawValue }
    }
    
    var accounts: [Account] {
        get {
            guard let data = defaults.data(forKey: kAccounts),
                  let list = try? JSONDecoder().decode([Account].self, from: data) else {
                return []
            }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: kAccounts)
            }
        }
    }
    
    var refreshInterval: TimeInterval {
        get {
            let val = defaults.double(forKey: kRefreshInterval)
            return val > 0 ? val : 300 // 默认5分钟
        }
        set { defaults.set(newValue, forKey: kRefreshInterval) }
    }
    
    var statusDisplayMode: StatusDisplayMode {
        get {
            guard let raw = defaults.string(forKey: kStatusDisplayMode),
                  let mode = StatusDisplayMode(rawValue: raw) else {
                return .iconOnly
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: kStatusDisplayMode) }
    }
}
