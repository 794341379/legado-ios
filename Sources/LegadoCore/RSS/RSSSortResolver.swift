import Foundation

public struct RSSSort: Hashable, Identifiable, Sendable {
    public var name: String
    public var url: String
    public var id: String { "\(name)\u{0}\(url)" }
    public init(name: String, url: String) { self.name = name; self.url = url }
}

public struct RSSSortResolver: Sendable {
    private let engine: RuleEngine
    public init(engine: RuleEngine = .init()) { self.engine = engine }

    public func resolve(_ source: RssSource) async -> [RSSSort] {
        var value = source.sortUrl
        if let rule = value, rule.hasPrefix("@js:") || rule.hasPrefix("<js>") {
            let result = await engine.evaluate(rule, in: .null, context: .init(source: source.bookSourceAdapter))
            value = result.joinedString
        }
        guard let value else { return [.init(name: "", url: source.sourceUrl)] }
        let pattern = try? NSRegularExpression(pattern: "(?:&&|\\n)+")
        let range = NSRange(value.startIndex..., in: value)
        let normalized = pattern?.stringByReplacingMatches(in: value, range: range, withTemplate: "\u{1F}") ?? value
        let sorts = normalized.split(separator: "\u{1F}", omittingEmptySubsequences: true).compactMap { item -> RSSSort? in
            let text = String(item)
            let parts = text.components(separatedBy: "::")
            let name = parts.first ?? ""
            let url = parts.dropFirst().joined(separator: "::")
            return url.isEmpty ? nil : .init(name: name, url: url)
        }
        return sorts.isEmpty ? [.init(name: "", url: source.sourceUrl)] : sorts
    }
}
