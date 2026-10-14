import Foundation

public struct ExploreKind: Codable, Hashable, Identifiable, Sendable {
    public var title: String
    public var url: String?
    public var type: String
    public var action: String?
    public var chars: [String?]?
    public var defaultValue: String?

    public var id: String { "\(title)\u{0}\(url ?? "")" }

    public var navigableURL: String? {
        guard type.caseInsensitiveCompare("url") == .orderedSame,
              let value = url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    enum CodingKeys: String, CodingKey {
        case title, url, type, action, chars
        case defaultValue = "default"
    }

    public init(
        title: String,
        url: String? = nil,
        type: String = "url",
        action: String? = nil,
        chars: [String?]? = nil,
        defaultValue: String? = nil
    ) {
        self.title = title
        self.url = url
        self.type = type
        self.action = action
        self.chars = chars
        self.defaultValue = defaultValue
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = values.lossyString(forKey: .title) ?? ""
        url = values.lossyString(forKey: .url)
        type = values.lossyString(forKey: .type) ?? "url"
        action = values.lossyString(forKey: .action)
        defaultValue = values.lossyString(forKey: .defaultValue)
        if let decoded = try? values.decodeIfPresent([JSONValue].self, forKey: .chars) {
            chars = decoded.map { value in
                if case .null = value { return nil }
                return value.stringValue
            }
        } else if let scalar = values.lossyString(forKey: .chars) {
            chars = [scalar]
        } else {
            chars = nil
        }
    }
}

private extension KeyedDecodingContainer where Key == ExploreKind.CodingKeys {
    func lossyString(forKey key: Key) -> String? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Bool.self, forKey: key) { return String(value) }
        if let value = try? decode(Int64.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) {
            return value.rounded() == value ? String(format: "%.0f", value) : String(value)
        }
        return nil
    }
}

public struct ExploreKindsReport: Sendable {
    public var kinds: [ExploreKind]
    public var diagnostics: [RuleDiagnostic]

    public init(kinds: [ExploreKind] = [], diagnostics: [RuleDiagnostic] = []) {
        self.kinds = kinds
        self.diagnostics = diagnostics
    }
}
