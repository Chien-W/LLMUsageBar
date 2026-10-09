import Foundation

final class GeminiService {
    static let shared = GeminiService()
    
    func checkConnection(apiKey: String) async -> (
        isConnected: Bool,
        message: String,
        latencyMs: Int,
        modelsCount: Int,
        lastUpdated: Date?
    ) {
        guard !apiKey.isEmpty else {
            return (false, "未设置 API Key", 0, 0, nil)
        }
        
        let startTime = DispatchTime.now()
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)") else {
            return (false, "API Key 格式异常", 0, 0, nil)
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let endTime = DispatchTime.now()
            let nanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
            let latency = Int(nanos / 1_000_000)
            
            if let httpResp = response as? HTTPURLResponse {
                if httpResp.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let modelList = json["models"] as? [[String: Any]] {
                        return (true, "连接正常", latency, modelList.count, Date())
                    }
                    return (true, "连接正常", latency, 0, Date())
                } else {
                    var errorMsg = "HTTP \(httpResp.statusCode)"
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let err = json["error"] as? [String: Any],
                       let msg = err["message"] as? String {
                        errorMsg = msg
                    }
                    return (false, errorMsg, latency, 0, nil)
                }
            }
        } catch {
            return (false, "连接超时: \(error.localizedDescription)", 0, 0, nil)
        }
        return (false, "未知网络响应", 0, 0, nil)
    }
}
