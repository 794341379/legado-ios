import Foundation

public enum AddBookURLError: LocalizedError, Equatable {
    case invalidURL
    case sourceNotFound
    case detailFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "书籍地址格式不对"
        case .sourceNotFound: "未找到匹配书源"
        case .detailFailed: "匹配书源未能解析书籍详情"
        }
    }
}

public struct AddBookURLResult: Sendable {
    public var source: BookSource
    public var book: Book
    public var diagnostics: [RuleDiagnostic]
}

public struct AddBookURLService: Sendable {
    private let detailService: NetworkBookService
    public init(detailService: NetworkBookService = .init()) { self.detailService = detailService }

    public func resolve(bookURL: String, sources: [BookSource]) async throws -> AddBookURLResult {
        let parsed = Self.parse(bookURL)
        guard let url = URL(string: parsed.url), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host else {
            throw AddBookURLError.invalidURL
        }
        let baseURL = "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
        let enabled = sources.filter(\.enabled).sorted { $0.customOrder < $1.customOrder }
        var candidates: [BookSource] = []
        if let origin = parsed.origin, let source = sources.first(where: { $0.bookSourceUrl == origin }) { candidates.append(source) }
        if let source = enabled.first(where: { $0.bookSourceUrl == baseURL }) { candidates.append(source) }
        for source in enabled where source.bookUrlPattern?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && source.bookUrlPattern != "NONE" {
            guard let rule = source.bookUrlPattern, let expression = try? NSRegularExpression(pattern: rule) else { continue }
            let range = NSRange(parsed.url.startIndex..., in: parsed.url)
            if let match = expression.firstMatch(in: parsed.url, range: range), match.range == range { candidates.append(source) }
        }
        var seen = Set<String>()
        for source in candidates where seen.insert(source.bookSourceUrl).inserted {
            let searchBook = SearchBook(bookURL: bookURL, origin: source.bookSourceUrl, originName: source.bookSourceName, type: source.bookSourceType, name: "")
            let detail = await detailService.loadDetail(searchBook: searchBook, source: source)
            if !detail.book.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .init(source: source, book: detail.book, diagnostics: detail.diagnostics)
            }
        }
        if candidates.isEmpty { throw AddBookURLError.sourceNotFound }
        throw AddBookURLError.detailFailed
    }

    public static func matchingSource(bookURL: String, sources: [BookSource]) -> BookSource? {
        let parsed = parse(bookURL)
        if let origin = parsed.origin, let source = sources.first(where: { $0.bookSourceUrl == origin }) { return source }
        guard let url = URL(string: parsed.url), let scheme = url.scheme, let host = url.host else { return nil }
        let baseURL = "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
        let enabled = sources.filter(\.enabled).sorted { $0.customOrder < $1.customOrder }
        if let source = enabled.first(where: { $0.bookSourceUrl == baseURL }) { return source }
        return enabled.first { source in
            guard let rule = source.bookUrlPattern?.trimmingCharacters(in: .whitespacesAndNewlines), !rule.isEmpty, rule != "NONE",
                  let expression = try? NSRegularExpression(pattern: rule) else { return false }
            let range = NSRange(parsed.url.startIndex..., in: parsed.url)
            return expression.firstMatch(in: parsed.url, range: range)?.range == range
        }
    }

    private static func parse(_ value: String) -> (url: String, origin: String?) {
        guard let expression = try? NSRegularExpression(pattern: #"\s*,\s*(?=\{)"#),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range, in: value) else { return (value, nil) }
        let url = String(value[..<range.lowerBound])
        let option = String(value[range.upperBound...])
        guard let data = option.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (url, nil) }
        return (url, object["origin"] as? String ?? object["bookSourceUrl"] as? String)
    }
}
