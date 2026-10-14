import Testing
@testable import LegadoCore

struct ContentSanitizerTests {
    @Test func metadataCleanerRemovesHTMLDecodesEntitiesAndKeepsParagraphs() {
        let input = "<p>第一段&nbsp;文字</p><div>第二段<br>换行</div><script>bad()</script>"

        let value = MetadataTextSanitizer().clean(input)

        #expect(value == "第一段 文字\n第二段\n换行")
        #expect(MetadataTextSanitizer().clean("  纯文本简介  ") == "纯文本简介")
        #expect(MetadataTextSanitizer().clean("<br><p></p>") == nil)
    }

    @Test func appliesOrderedScopedRulesAndRemovesDuplicateTitle() {
        let book = Book(bookUrl: "https://source.test/book/1", name: "测试书", origin: "https://source.test")
        let chapter = BookChapter(url: "chapter/1", title: "第一章 开始", bookUrl: book.bookUrl, index: 0)
        var titleRule = ReplaceRule(id: 1, name: "标题", pattern: "开始", replacement: "启程")
        titleRule.scopeTitle = true
        titleRule.scopeContent = false
        titleRule.scope = "测试书"
        var adRule = ReplaceRule(id: 2, name: "广告", pattern: "广告[^\n]*", replacement: "")
        adRule.scopeContent = true
        adRule.sortOrder = 1
        var excluded = ReplaceRule(id: 3, name: "排除", pattern: "正文", replacement: "错误")
        excluded.excludeScope = "https://source.test"

        let report = ContentSanitizer().process(
            book: book,
            chapter: chapter,
            content: "第一章 开始\n 正文第一段 \n广告请访问 example.com\n正文第二段",
            rules: [excluded, adRule, titleRule]
        )

        #expect(report.title == "第一章 启程")
        #expect(report.content == "正文第一段\n\n正文第二段")
        #expect(report.removedDuplicateTitle)
        #expect(report.effectiveRuleIDs == [1, 2])
        #expect(report.diagnostics.isEmpty)
    }

    @Test func rejectsHighRiskRegexWithoutChangingContent() {
        let book = Book(bookUrl: "local", name: "书", origin: "local")
        let chapter = BookChapter(url: "1", title: "章节", bookUrl: book.bookUrl, index: 0)
        let risky = ReplaceRule(id: 7, name: "危险", pattern: "(a+)+$", replacement: "")

        let report = ContentSanitizer().process(book: book, chapter: chapter, content: "aaaa!", rules: [risky])

        #expect(report.content == "aaaa!")
        #expect(report.diagnostics.contains { $0.code == "rule.resource_limit" })
    }
}
