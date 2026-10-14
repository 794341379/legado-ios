import Foundation

public struct BookSourceIssue: Codable, Hashable, Identifiable, Sendable {
    public enum Severity: String, Codable, Sendable {
        case warning
        case error
    }

    public var severity: Severity
    public var code: String
    public var field: String
    public var message: String

    public var id: String { "\(code):\(field):\(message)" }

    public init(severity: Severity, code: String, field: String, message: String) {
        self.severity = severity
        self.code = code
        self.field = field
        self.message = message
    }
}

public enum BookSourceValidator {
    public static func validate(_ source: BookSource) -> [BookSourceIssue] {
        var issues: [BookSourceIssue] = []
        if source.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(
                severity: .error,
                code: "source_url.empty",
                field: "bookSourceUrl",
                message: "书源地址不能为空"
            ))
        }
        if source.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(
                severity: .error,
                code: "source_name.empty",
                field: "bookSourceName",
                message: "书源名称不能为空"
            ))
        }
        if !source.bookSourceUrl.isEmpty,
           let components = URLComponents(string: source.bookSourceUrl),
           components.scheme == nil {
            issues.append(.init(
                severity: .warning,
                code: "source_url.no_scheme",
                field: "bookSourceUrl",
                message: "书源地址没有 URL scheme，运行时可能无法解析相对地址"
            ))
        }
        if source.searchUrl?.isEmpty == false, source.ruleSearch == nil {
            issues.append(.init(
                severity: .warning,
                code: "search.rule_missing",
                field: "ruleSearch",
                message: "配置了搜索地址但没有搜索解析规则"
            ))
        }
        if source.exploreUrl?.isEmpty == false, source.ruleExplore == nil {
            issues.append(.init(
                severity: .warning,
                code: "explore.rule_missing",
                field: "ruleExplore",
                message: "配置了发现地址但没有发现解析规则"
            ))
        }
        return issues
    }
}

