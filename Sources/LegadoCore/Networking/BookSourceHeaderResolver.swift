import Foundation

public struct BookSourceHeaderResolver: Sendable {
    public init() {}

    public func resolve(_ source: BookSource, includeLoginHeader: Bool = true) throws -> [String: String] {
        var headers: [String: String] = [:]
        if let raw = source.header?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let json: String
            if raw.lowercased().hasPrefix("@js:") {
                json = try JavaScriptRuleEvaluator().evaluate(
                    script: String(raw.dropFirst(4)),
                    result: .null,
                    executionContext: .init(source: source)
                ).value.stringValue
            } else if raw.lowercased().hasPrefix("<js>"), raw.lowercased().hasSuffix("</js>") {
                json = try JavaScriptRuleEvaluator().evaluate(
                    script: String(raw.dropFirst(4).dropLast(5)),
                    result: .null,
                    executionContext: .init(source: source)
                ).value.stringValue
            } else {
                json = raw
            }
            if case .object(let object) = try LegadoURLBuilder.decodeLenientJSON(json) {
                headers = object.mapValues(\.stringValue)
            }
        }
        if includeLoginHeader {
            headers.merge(BookSourceRuntimeStore.shared.loginHeaders(sourceID: source.id)) { _, login in login }
        }
        return headers
    }
}
