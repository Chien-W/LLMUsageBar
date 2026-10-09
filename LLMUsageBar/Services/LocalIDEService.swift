import Foundation

final class InsecureSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

struct LiveQuotaBucket {
    let bucketId: String
    let displayName: String
    let description: String
    let window: String
    let remainingFraction: Double
    let percentage: Int
    let resetTime: Date?
    let resetTimeRaw: String
    let localizedDescription: String
}

struct LiveQuotaGroup {
    let displayName: String
    let description: String
    let buckets: [LiveQuotaBucket]
}

struct LiveQuotaResult {
    let groups: [LiveQuotaGroup]
    let port: Int
    let csrfToken: String
    let userEmail: String?
    let userTier: String?
}

final class LocalIDEService {
    static let shared = LocalIDEService()
    
    private var cachedPort: Int?
    private var cachedCsrfToken: String?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        return URLSession(configuration: config, delegate: InsecureSessionDelegate(), delegateQueue: nil)
    }()
    
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    func parseISODate(_ str: String) -> Date? {
        if let d = isoFormatter.date(from: str) { return d }
        if let d = isoFormatterNoFrac.date(from: str) { return d }
        return nil
    }
    
    func fetchQuota() async -> LiveQuotaResult? {
        // 1. 优先使用缓存的端口和 CSRF Token（0ms 级直接网络请求，无需调系统进程）
        if let port = cachedPort, let token = cachedCsrfToken {
            if let result = await queryEndpoint(port: port, csrfToken: token) {
                return result
            }
            // 缓存失效，清空
            self.cachedPort = nil
            self.cachedCsrfToken = nil
        }
        
        // 2. 发现本地语言服务（轻量级 grep，仅耗时 5ms）
        guard let discovered = self.discoverLanguageServer() else {
            return nil
        }
        
        // 3. 轮询已发现的监听端口
        for port in discovered.ports {
            if let result = await queryEndpoint(port: port, csrfToken: discovered.csrfToken) {
                self.cachedPort = port
                self.cachedCsrfToken = discovered.csrfToken
                return result
            }
        }
        
        return nil
    }
    
    private func queryEndpoint(port: Int, csrfToken: String) async -> LiveQuotaResult? {
        guard let url = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else {
            return nil
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        req.httpBody = "{}".data(using: .utf8)
        
        do {
            let (data, response) = try await session.data(for: req)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return nil
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let resp = json["response"] as? [String: Any],
                  let groupsArr = resp["groups"] as? [[String: Any]] else {
                return nil
            }
            
            var groups: [LiveQuotaGroup] = []
            let now = Date()
            
            for g in groupsArr {
                let displayName = g["displayName"] as? String ?? ""
                let gDesc = g["description"] as? String ?? ""
                let bucketsArr = g["buckets"] as? [[String: Any]] ?? []
                
                var buckets: [LiveQuotaBucket] = []
                for b in bucketsArr {
                    let bucketId = b["bucketId"] as? String ?? ""
                    let bDisplayName = b["displayName"] as? String ?? ""
                    let bDesc = b["description"] as? String ?? ""
                    let window = b["window"] as? String ?? ""
                    let fraction = (b["remainingFraction"] as? NSNumber)?.doubleValue ?? 0.0
                    let pct = max(0, min(100, Int(round(fraction * 100))))
                    let resetTimeRaw = b["resetTime"] as? String ?? ""
                    let resetDate = parseISODate(resetTimeRaw)
                    
                    let locDesc = formatLocalizedDescription(
                        isClaudeGroup: displayName.lowercased().contains("claude"),
                        isWeekly: window.lowercased().contains("week"),
                        pct: pct,
                        resetDate: resetDate,
                        fallbackDesc: bDesc,
                        now: now
                    )
                    
                    buckets.append(LiveQuotaBucket(
                        bucketId: bucketId,
                        displayName: bDisplayName,
                        description: bDesc,
                        window: window,
                        remainingFraction: fraction,
                        percentage: pct,
                        resetTime: resetDate,
                        resetTimeRaw: resetTimeRaw,
                        localizedDescription: locDesc
                    ))
                }
                
                groups.append(LiveQuotaGroup(displayName: displayName, description: gDesc, buckets: buckets))
            }
            
            let (uEmail, uTier) = await fetchUserInfo(port: port, csrfToken: csrfToken)
            return LiveQuotaResult(groups: groups, port: port, csrfToken: csrfToken, userEmail: uEmail, userTier: uTier)
        } catch {
            return nil
        }
    }
    
    private func fetchUserInfo(port: Int, csrfToken: String) async -> (String?, String?) {
        guard let url = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else {
            return (nil, nil)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        req.httpBody = "{}".data(using: .utf8)
        
        do {
            let (data, response) = try await session.data(for: req)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { return (nil, nil) }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let uStatus = json["userStatus"] as? [String: Any] else { return (nil, nil) }
            let email = uStatus["email"] as? String
            let tier = (uStatus["userTier"] as? [String: Any])?["name"] as? String
            return (email, tier)
        } catch {
            return (nil, nil)
        }
    }
    
    private func formatLocalizedDescription(
        isClaudeGroup: Bool,
        isWeekly: Bool,
        pct: Int,
        resetDate: Date?,
        fallbackDesc: String,
        now: Date
    ) -> String {
        guard let resetDate = resetDate else { return fallbackDesc }
        let diff = max(0, resetDate.timeIntervalSince(now))
        let days = Int(diff) / 86400
        let hours = (Int(diff) % 86400) / 3600
        let mins = (Int(diff) % 3600) / 60
        
        if isClaudeGroup {
            if isWeekly {
                if pct <= 0 || fallbackDesc.contains("hit your 5-hour limit") {
                    return "You have hit your 5-hour limit, so the weekly limit does not currently apply. Your 5-hour limit will refresh in \(hours) 小时, \(mins) 分钟."
                } else {
                    return "您已使用部分周额度，将在 \(days) 天 \(hours) 小时后完全刷新。"
                }
            } else {
                if pct <= 0 {
                    return "You have hit your 5-hour limit, it will refresh in \(hours) 小时, \(mins) 分钟. If on a supported paid plan, you can use AI credits in the interim."
                } else {
                    return "您已使用部分 5 小时额度，将在 \(hours) 小时 \(mins) 分钟后完全刷新。"
                }
            }
        } else {
            // Gemini 模型
            if isWeekly {
                return "您已使用部分周额度，将在 \(days) 天 \(hours) 小时后完全刷新。"
            } else {
                if pct <= 0 {
                    return "您已达到 5 小时限额，将在 \(hours) 小时 \(mins) 分钟后完全刷新。"
                } else {
                    return "您已使用部分 5 小时额度，将在 \(hours) 小时 \(mins) 分钟后完全刷新。"
                }
            }
        }
    }
    
    private struct DiscoveredServer {
        let pid: Int
        let csrfToken: String
        let ports: [Int]
    }
    
    // 安全、非阻塞、无死锁的进程发现
    private func discoverLanguageServer() -> DiscoveredServer? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "ps -axo pid,command | grep language_server | grep -v grep"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        
        do {
            try proc.run()
            // 关键：必须先读取管道数据，释放缓冲区，再等待进程退出，彻底防止死锁！
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return nil }
            
            for line in output.components(separatedBy: "\n") {
                if line.contains("language_server") && line.contains("--csrf_token") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let components = trimmed.components(separatedBy: .whitespaces)
                    guard let first = components.first, let pid = Int(first) else { continue }
                    
                    guard let csrfRange = line.range(of: "--csrf_token") else { continue }
                    let sub = String(line[csrfRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    let tokenParts = sub.components(separatedBy: .whitespaces)
                    guard let token = tokenParts.first, !token.isEmpty else { continue }
                    
                    let ports = findPorts(for: pid)
                    if !ports.isEmpty {
                        return DiscoveredServer(pid: pid, csrfToken: token, ports: ports)
                    }
                    return DiscoveredServer(pid: pid, csrfToken: token, ports: [52589, 52590, 52591])
                }
            }
        } catch {
            return nil
        }
        
        return nil
    }
    
    private func findPorts(for pid: Int) -> [Int] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-Pan", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        
        do {
            try proc.run()
            // 关键：先读出数据再等待退出
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            var ports: [Int] = []
            for line in output.components(separatedBy: "\n") {
                if let range = line.range(of: "127.0.0.1:") {
                    let sub = String(line[range.upperBound...])
                    let portStr = sub.prefix(while: { $0.isNumber })
                    if let port = Int(portStr), !ports.contains(port) {
                        ports.append(port)
                    }
                }
            }
            return ports
        } catch {
            return []
        }
    }
}
