import Foundation

struct CodexQuotaResult {
    let email: String
    let planType: String
    let ordinaryUsageAllowed: Bool
    let primaryRemainingPct: Int
    let primaryUsedPct: Int
    let primaryResetDate: Date?
    let primaryDurationMins: Int?
    let secondaryRemainingPct: Int?
    let secondaryUsedPct: Int?
    let secondaryResetDate: Date?
    let secondaryDurationMins: Int?
    let lifetimeTokens: Int?
    let currentStreakDays: Int?
    let isConnected: Bool
    let message: String
}

final class CodexService: @unchecked Sendable {
    static let shared = CodexService()
    
    func findCodexExecutable() -> String? {
        let candidates = [
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex"
        ]
        for c in candidates {
            if FileManager.default.isExecutableFile(atPath: c) {
                return c
            }
        }
        
        // 尝试通过 which 寻找
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["codex"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {}
        
        return nil
    }
    
    func isInstalled() -> Bool {
        if findCodexExecutable() != nil { return true }
        let authPath = "\(NSHomeDirectory())/.codex/auth.json"
        return FileManager.default.fileExists(atPath: authPath)
    }
    
    /// 从本地 auth.json 快速读取缓存的邮箱与账号 ID
    func readAuthJsonInfo() -> (email: String?, accountId: String?) {
        let authPath = "\(NSHomeDirectory())/.codex/auth.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: authPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any] else {
            return (nil, nil)
        }
        
        let accountId = tokens["account_id"] as? String
        var email: String? = nil
        
        if let idToken = tokens["id_token"] as? String {
            let parts = idToken.components(separatedBy: ".")
            if parts.count > 1 {
                var payloadBase64 = parts[1]
                let rem = payloadBase64.count % 4
                if rem > 0 {
                    payloadBase64.append(String(repeating: "=", count: 4 - rem))
                }
                payloadBase64 = payloadBase64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                if let payloadData = Data(base64Encoded: payloadBase64),
                   let payloadJson = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                    email = payloadJson["email"] as? String
                }
            }
        }
        
        return (email, accountId)
    }
    
    /// 与本地 codex app-server 建立 stdio JSON-RPC 通信，拉取真实额度
    func fetchQuota() async -> CodexQuotaResult? {
        guard let exe = findCodexExecutable() else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: exe)
                proc.arguments = ["app-server", "--stdio"]
                
                let inPipe = Pipe()
                let outPipe = Pipe()
                proc.standardInput = inPipe
                proc.standardOutput = outPipe
                proc.standardError = FileHandle.nullDevice
                
                do {
                    try proc.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                
                // 1. 初始化
                let initJson = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"LLMUsageBar\",\"version\":\"1.0\"},\"protocolVersion\":\"2024-11-05\",\"capabilities\":{}}}\n"
                inPipe.fileHandleForWriting.write(initJson.data(using: .utf8) ?? Data())
                
                // 2. 读取账号基本信息
                let accountJson = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"account/read\",\"params\":{}}\n"
                inPipe.fileHandleForWriting.write(accountJson.data(using: .utf8) ?? Data())
                
                // 3. 读取实时配额与限额
                let rateLimitJson = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"account/rateLimits/read\",\"params\":null}\n"
                inPipe.fileHandleForWriting.write(rateLimitJson.data(using: .utf8) ?? Data())
                
                // 4. 读取历史用量统计
                let usageJson = "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"account/usage/read\",\"params\":null}\n"
                inPipe.fileHandleForWriting.write(usageJson.data(using: .utf8) ?? Data())
                
                var buffer = Data()
                let handle = outPipe.fileHandleForReading
                let start = Date()
                var rateLimitsResult: [String: Any]? = nil
                var accountResult: [String: Any]? = nil
                var usageResult: [String: Any]? = nil
                
                while Date().timeIntervalSince(start) < 4.0 {
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        Thread.sleep(forTimeInterval: 0.05)
                        continue
                    }
                    buffer.append(chunk)
                    
                    if let text = String(data: buffer, encoding: .utf8) {
                        let lines = text.components(separatedBy: "\n")
                        for line in lines {
                            guard !line.isEmpty, let lineData = line.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                                continue
                            }
                            if let id = json["id"] as? Int {
                                if id == 2 {
                                    accountResult = json["result"] as? [String: Any]
                                } else if id == 3 {
                                    rateLimitsResult = json["result"] as? [String: Any]
                                } else if id == 4 {
                                    usageResult = json["result"] as? [String: Any]
                                }
                            }
                        }
                    }
                    
                    if rateLimitsResult != nil && accountResult != nil {
                        break
                    }
                }
                
                proc.terminate()
                
                // 解析各模块数据
                var email = ""
                var planType = "free"
                if let acc = accountResult, let aObj = acc["account"] as? [String: Any] {
                    email = aObj["email"] as? String ?? ""
                    planType = aObj["planType"] as? String ?? "free"
                }
                if email.isEmpty {
                    let cached = self.readAuthJsonInfo()
                    email = cached.email ?? ""
                }
                
                var ordinaryAllowed = true
                var primaryUsed = 0
                var primaryRemaining = 100
                var primaryResetDate: Date? = nil
                var primaryDurationMins: Int? = nil
                
                var secUsed: Int? = nil
                var secRemaining: Int? = nil
                var secResetDate: Date? = nil
                var secDurationMins: Int? = nil
                
                if let rl = rateLimitsResult {
                    ordinaryAllowed = (rl["ordinaryUsageAllowed"] as? Bool) ?? true
                    if let rates = rl["rateLimits"] as? [String: Any] {
                        if let p = rates["primary"] as? [String: Any] {
                            primaryUsed = (p["usedPercent"] as? Int) ?? 0
                            primaryRemaining = max(0, min(100, 100 - primaryUsed))
                            primaryDurationMins = p["windowDurationMins"] as? Int
                            if let resetsAt = p["resetsAt"] as? Int64 {
                                primaryResetDate = Date(timeIntervalSince1970: TimeInterval(resetsAt))
                            }
                        }
                        if let s = rates["secondary"] as? [String: Any] {
                            let sUsed = (s["usedPercent"] as? Int) ?? 0
                            secUsed = sUsed
                            secRemaining = max(0, min(100, 100 - sUsed))
                            secDurationMins = s["windowDurationMins"] as? Int
                            if let sResetsAt = s["resetsAt"] as? Int64 {
                                secResetDate = Date(timeIntervalSince1970: TimeInterval(sResetsAt))
                            }
                        }
                    }
                }
                
                var lifetimeTokens: Int? = nil
                var streakDays: Int? = nil
                if let u = usageResult, let sum = u["summary"] as? [String: Any] {
                    lifetimeTokens = sum["lifetimeTokens"] as? Int
                    streakDays = sum["currentStreakDays"] as? Int
                }
                
                let result = CodexQuotaResult(
                    email: email,
                    planType: planType,
                    ordinaryUsageAllowed: ordinaryAllowed,
                    primaryRemainingPct: primaryRemaining,
                    primaryUsedPct: primaryUsed,
                    primaryResetDate: primaryResetDate,
                    primaryDurationMins: primaryDurationMins,
                    secondaryRemainingPct: secRemaining,
                    secondaryUsedPct: secUsed,
                    secondaryResetDate: secResetDate,
                    secondaryDurationMins: secDurationMins,
                    lifetimeTokens: lifetimeTokens,
                    currentStreakDays: streakDays,
                    isConnected: true,
                    message: "Codex 本地直连"
                )
                continuation.resume(returning: result)
            }
        }
    }
    
    /// 构建适合展示的模型组配额列表
    func buildModelGroups(from res: CodexQuotaResult, now: Date) -> [ModelGroupQuota] {
        var weeklyDesc = ""
        let weeklyTarget = res.primaryResetDate ?? now.addingTimeInterval(30 * 86400)
        let diff = max(0, weeklyTarget.timeIntervalSince(now))
        let days = Int(diff) / 86400
        let hours = (Int(diff) % 86400) / 3600
        
        if res.primaryUsedPct > 0 {
            if days > 0 {
                weeklyDesc = "已使用 \(res.primaryUsedPct)% 周期配额，将在 \(days) 天 \(hours) 小时后刷新。"
            } else {
                weeklyDesc = "已使用 \(res.primaryUsedPct)% 周期配额，将在 \(hours) 小时后刷新。"
            }
        } else {
            weeklyDesc = "周期配额充足，将在 \(days) 天后刷新。"
        }
        
        var fiveHourDesc = ""
        var fiveHourPct = 100
        var fiveHourDisabled = true
        var fiveHourTarget = now
        
        if let sRemaining = res.secondaryRemainingPct, let sUsed = res.secondaryUsedPct {
            fiveHourPct = sRemaining
            fiveHourDisabled = false
            fiveHourTarget = res.secondaryResetDate ?? now.addingTimeInterval(5 * 3600)
            let sDiff = max(0, fiveHourTarget.timeIntervalSince(now))
            let sHours = Int(sDiff) / 3600
            let sMins = (Int(sDiff) % 3600) / 60
            fiveHourDesc = "已使用 \(sUsed)% 短期限额，将在 \(sHours) 小时 \(sMins) 分钟后完全刷新。"
        } else {
            // Free 计划或单周期计划：展示 Token 累计与活跃统计
            if let tokens = res.lifetimeTokens {
                let formatted = NumberFormatter.localizedString(from: NSNumber(value: tokens), number: .decimal)
                fiveHourDesc = "累计消耗 \(formatted) Tokens · 正常调用权限生效中"
            } else {
                fiveHourDesc = "普通调用权限正常，无并发限流阻塞"
            }
        }
        
        return [
            ModelGroupQuota(
                id: "codex_quota",
                name: "Codex 模型用量",
                weeklyPct: res.primaryRemainingPct,
                fiveHourPct: fiveHourPct,
                weeklyDisabled: false,
                fiveHourDisabled: fiveHourDisabled,
                weeklyResetTarget: weeklyTarget,
                fiveHourResetTarget: fiveHourTarget,
                weeklyDescription: weeklyDesc,
                fiveHourDescription: fiveHourDesc
            )
        ]
    }
    
    /// 验证 OpenAI API Key
    func checkOpenAIKey(apiKey: String) async -> (isConnected: Bool, message: String) {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            return (false, "无效的 API 地址")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 6
        
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return (false, "网络响应无效")
            }
            if http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let list = json["data"] as? [[String: Any]] {
                    return (true, "连接成功！检测到 \(list.count) 个可用模型")
                }
                return (true, "API Key 验证通过")
            } else {
                return (false, "HTTP \(http.statusCode) 认证失败")
            }
        } catch {
            return (false, "请求超时或网络不可达: \(error.localizedDescription)")
        }
    }
}
