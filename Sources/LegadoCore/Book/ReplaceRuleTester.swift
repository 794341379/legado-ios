import Foundation

public enum ReplaceRuleValidator {
    public static func validate(_ rule: ReplaceRule) throws {
        guard !rule.pattern.isEmpty else { throw ReplaceRuleImportError.emptyPattern(rule.name) }
        guard rule.scopeTitle || rule.scopeContent else { throw ReplaceRuleImportError.invalidDocument("至少选择标题或正文一个作用域") }
        if rule.isRegex {
            do { _ = try NSRegularExpression(pattern: rule.pattern) }
            catch { throw ReplaceRuleImportError.invalidDocument("正则语法错误：\(error.localizedDescription)") }
            if rule.pattern.hasSuffix("|"), !rule.pattern.hasSuffix("\\|") {
                throw ReplaceRuleImportError.invalidDocument("正则不能以空分支 | 结尾")
            }
        }
    }
}

public struct ReplaceRuleTestResult: Sendable {
    public let report: ContentProcessingReport
    public let elapsedMilliseconds: Double
}

public struct ReplaceRuleTester: Sendable {
    public init() {}
    public func test(rule: ReplaceRule, title: String, content: String, bookName: String, sourceURL: String) throws -> ReplaceRuleTestResult {
        try ReplaceRuleValidator.validate(rule)
        let book = Book(bookUrl: "test", name: bookName, origin: sourceURL)
        let chapter = BookChapter(url: "chapter", title: title, bookUrl: book.bookUrl, index: 0)
        let started = DispatchTime.now().uptimeNanoseconds
        let report = ContentSanitizer().process(book: book, chapter: chapter, content: content,
            rules: [rule], removeDuplicateTitle: false, resegment: false)
        return .init(report: report, elapsedMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
    }
}
