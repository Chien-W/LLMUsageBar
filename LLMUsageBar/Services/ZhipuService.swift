import Foundation
import CommonCrypto

struct ZhipuQuotaParsedItem {
    let title: String
    let usedPct: Int
    let remainingPct: Int
    let resetDate: Date?
    let resetTimeText: String
    let description: String
}

struct ZhipuQuotaParsedResult {
    let isConnected: Bool
    let message: String
    let fiveHourQuota: ZhipuQuotaParsedItem?
    let weeklyQuota: ZhipuQuotaParsedItem?
    let mcpQuota: ZhipuQuotaParsedItem?
    let level: String
}

struct ZhipuQuotaItem: Codable {
    let type: String?
    let unit: Int?
    let number: Int?
    let percentage: Double?
    let usage: Double?
    let currentValue: Double?
    let remaining: Double?
    let nextResetTime: Double?
}

struct ZhipuQuotaResponse: Codable {
    let code: Int?
    let msg: String?
    let success: Bool?
    struct DataClass: Codable {
        let limits: [ZhipuQuotaItem]?
        let level: String?
    }
    let data: DataClass?
}

final class ZhipuService {
    static let shared = ZhipuService()
    
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
    
    private let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
    
    // 生成智谱 API 规范的 JWT Token
    static func generateJWT(apiKey: String) -> String {
        let parts = apiKey.split(separator: ".")
        guard parts.count == 2 else { return apiKey }
        let id = String(parts[0])
        let secret = String(parts[1])
        
        let header = ["alg": "HS256", "sign_type": "SIGN"]
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let expMs = nowMs + 3600 * 1000
        let payload: [String: Any] = [
            "api_key": id,
            "exp": expMs,
            "timestamp": nowMs
        ]
        
        guard let headerData = try? JSONSerialization.data(withJSONObject: header),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            return apiKey
        }
        
        let headerB64 = base64UrlEncode(headerData)
        let payloadB64 = base64UrlEncode(payloadData)
        let signInput = "\(headerB64).\(payloadB64)"
        
        guard let secretData = secret.data(using: .utf8),
              let inputData = signInput.data(using: .utf8) else {
            return apiKey
        }
        
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        secretData.withUnsafeBytes { secBytes in
            inputData.withUnsafeBytes { inBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       secBytes.baseAddress, secBytes.count,
                       inBytes.baseAddress, inBytes.count,
                       &digest)
            }
        }
        
        let signatureData = Data(digest)
        let signatureB64 = base64UrlEncode(signatureData)
        
        return "\(signInput).\(signatureB64)"
    }
    
    private static func base64UrlEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    func fetchQuotaDetail(apiKey: String) async -> ZhipuQuotaParsedResult {
        guard !apiKey.isEmpty else {
            return ZhipuQuotaParsedResult(isConnected: false, message: "未设置 API Key", fiveHourQuota: nil, weeklyQuota: nil, mcpQuota: nil, level: "")
        }
        
        let token = ZhipuService.generateJWT(apiKey: apiKey)
        guard let url = URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit") else {
            return ZhipuQuotaParsedResult(isConnected: false, message: "URL 无效", fiveHourQuota: nil, weeklyQuota: nil, mcpQuota: nil, level: "")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                if let decoded = try? JSONDecoder().decode(ZhipuQuotaResponse.self, from: data),
                   let limits = decoded.data?.limits {
                    
                    let now = Date()
                    var fiveHItem: ZhipuQuotaParsedItem? = nil
                    var weeklyItem: ZhipuQuotaParsedItem? = nil
                    var mcpItem: ZhipuQuotaParsedItem? = nil
                    let level = decoded.data?.level ?? "Pro"
                    
                    for lim in limits {
                        let unit = lim.unit ?? 0
                        let num = lim.number ?? 0
                        let usedPct = Int(round(lim.percentage ?? 0))
                        let remainPct = max(0, min(100, 100 - usedPct))
                        let resetDate: Date? = lim.nextResetTime != nil ? Date(timeIntervalSince1970: lim.nextResetTime! / 1000.0) : nil
                        
                        // 1. 5小时额度 (unit: 3, number: 5)
                        if unit == 3 && num == 5 {
                            let timeStr = resetDate != nil ? timeFormatter.string(from: resetDate!) : "稍后"
                            let diff = max(0, resetDate?.timeIntervalSince(now) ?? 0)
                            let hours = Int(diff) / 3600
                            let mins = (Int(diff) % 3600) / 60
                            let desc = "已使用 \(usedPct)% 5小时额度，将在 \(timeStr) 完全刷新（约 \(hours) 小时 \(mins) 分钟后）。"
                            
                            fiveHItem = ZhipuQuotaParsedItem(
                                title: "剩余 5 小时限额",
                                usedPct: usedPct,
                                remainingPct: remainPct,
                                resetDate: resetDate,
                                resetTimeText: timeStr,
                                description: desc
                            )
                        }
                        // 2. 每周额度 (unit: 6, number: 1)
                        else if unit == 6 && num == 1 {
                            let timeStr = resetDate != nil ? dateTimeFormatter.string(from: resetDate!) : "稍后"
                            let diff = max(0, resetDate?.timeIntervalSince(now) ?? 0)
                            let days = Int(diff) / 86400
                            let hours = (Int(diff) % 86400) / 3600
                            let desc = "已使用 \(usedPct)% 周额度，将在 \(timeStr) 完全刷新（约 \(days) 天 \(hours) 小时后）。"
                            
                            weeklyItem = ZhipuQuotaParsedItem(
                                title: "剩余周额度",
                                usedPct: usedPct,
                                remainingPct: remainPct,
                                resetDate: resetDate,
                                resetTimeText: timeStr,
                                description: desc
                            )
                        }
                        // 3. MCP 每月额度 (TIME_LIMIT 或 unit: 5, number: 1)
                        else if lim.type == "TIME_LIMIT" || (unit == 5 && num == 1) {
                            let timeStr = resetDate != nil ? dateTimeFormatter.string(from: resetDate!) : "稍后"
                            let desc = "已使用 \(usedPct)% MCP 工具额度，将在 \(timeStr) 完全刷新。"
                            
                            mcpItem = ZhipuQuotaParsedItem(
                                title: "MCP 每月额度",
                                usedPct: usedPct,
                                remainingPct: remainPct,
                                resetDate: resetDate,
                                resetTimeText: timeStr,
                                description: desc
                            )
                        }
                    }
                    
                    return ZhipuQuotaParsedResult(
                        isConnected: true,
                        message: "官方实时直连",
                        fiveHourQuota: fiveHItem,
                        weeklyQuota: weeklyItem,
                        mcpQuota: mcpItem,
                        level: level
                    )
                }
            }
        } catch {
            // 继续备用检测
        }
        
        let direct = await testDirectChat(apiKey: apiKey, token: token)
        return ZhipuQuotaParsedResult(
            isConnected: direct.isConnected,
            message: direct.message,
            fiveHourQuota: nil,
            weeklyQuota: nil,
            mcpQuota: nil,
            level: "Normal"
        )
    }
    
    private func testDirectChat(apiKey: String, token: String) async -> (isConnected: Bool, message: String) {
        guard let url = URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions") else {
            return (false, "URL 无效")
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "glm-4-flash",
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let httpResp = response as? HTTPURLResponse {
                if httpResp.statusCode == 200 {
                    return (true, "连接正常")
                } else {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let err = json["error"] as? [String: Any],
                       let msg = err["message"] as? String {
                        return (false, msg)
                    }
                    return (false, "HTTP \(httpResp.statusCode)")
                }
            }
        } catch {
            return (false, "连接超时: \(error.localizedDescription)")
        }
        return (false, "未知网络错误")
    }
}
