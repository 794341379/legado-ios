import Foundation

public struct DiagnosticLogEntry: Codable, Identifiable, Sendable {
    public enum Level: String, Codable, CaseIterable, Sendable { case info, warning, error }
    public var id: UUID
    public var date: Date
    public var level: Level
    public var category: String
    public var message: String
}

public final class DiagnosticLog: @unchecked Sendable {
    public static let shared = DiagnosticLog()
    private let lock = NSLock()
    private let fileURL: URL
    private let maximumEntries: Int
    private let isEnabled: @Sendable () -> Bool
    private var entries: [DiagnosticLogEntry]

    public init(directory: URL? = nil, maximumEntries: Int = 500,
                isEnabled: @escaping @Sendable () -> Bool = { ApplicationSettingsStore.shared.settings.recordLog }) {
        fileURL = (directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Legado/Logs", isDirectory: true)).appendingPathComponent("diagnostics.json")
        self.maximumEntries = max(1, maximumEntries)
        self.isEnabled = isEnabled
        entries = (try? JSONDecoder().decode([DiagnosticLogEntry].self, from: Data(contentsOf: fileURL))) ?? []
        entries = Array(entries.suffix(self.maximumEntries))
    }

    public func record(_ level: DiagnosticLogEntry.Level = .info, category: String, message: String) {
        guard isEnabled() else { return }
        lock.lock()
        defer { lock.unlock() }
        entries.append(.init(id: UUID(), date: Date(), level: level,
                             category: String(category.prefix(80)), message: Self.redact(String(message.prefix(2048)))))
        entries = Array(entries.suffix(maximumEntries))
        try? persist()
    }

    public func snapshot() -> [DiagnosticLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.reversed()
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        entries.removeAll()
    }

    public func export() -> String {
        let formatter = ISO8601DateFormatter()
        return snapshot().reversed().map {
            "\(formatter.string(from: $0.date)) [\($0.level.rawValue.uppercased())] [\($0.category)] \($0.message)"
        }.joined(separator: "\n")
    }

    public func network(_ request: URLRequest, status: Int? = nil, error: Error? = nil, startedAt: Date) {
        // URL query strings, credentials and fragments can contain access tokens.
        let url = request.url.map(Self.safeURL) ?? "未知地址"
        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
        let result: String
        if let error, case HTTPClientError.statusResponse(let response) = error {
            result = "HTTP \(response.statusCode)"
        } else {
            result = error.map { "失败 (\(($0 as NSError).domain):\(($0 as NSError).code))" } ?? "HTTP \(status ?? 0)"
        }
        record(error != nil || (status ?? 0) >= 400 ? .error : .info, category: "网络",
               message: "\(request.httpMethod ?? "GET") \(url) · \(result) · \(duration) ms")
    }

    public static func safeURL(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "[URL]" }
        parts.user = nil; parts.password = nil; parts.query = nil; parts.fragment = nil
        return parts.string ?? "[URL]"
    }

    public static func redact(_ text: String) -> String {
        var value = text
        if let regex = try? NSRegularExpression(pattern: #"https?://[^\s\"<>]+"#) {
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let range = Range(match.range, in: value), let url = URL(string: String(value[range])) else { continue }
                value.replaceSubrange(range, with: safeURL(url))
            }
        }
        for pattern in [
            #"(?im)(authorization|cookie)["']?(\s*[=:]\s*)[^\r\n]+"#,
            #"(?i)["']?(password|passwd|token|secret)["']?(\s*[=:]\s*)(?:"[^"]*"|'[^']*'|[^\s,;]+)"#
        ] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                value = regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "$1$2[已隐藏]")
            }
        }
        return value
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }
}
