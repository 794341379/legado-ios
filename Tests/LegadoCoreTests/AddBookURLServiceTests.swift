import Foundation
import Testing
@testable import LegadoCore

@Suite struct AddBookURLServiceTests {
    @Test func explicitOriginHasPriority() {
        var exact = BookSource(bookSourceUrl: "https://site.example", bookSourceName: "域名源")
        exact.customOrder = 0
        var explicit = BookSource(bookSourceUrl: "https://chosen.example", bookSourceName: "指定源")
        explicit.customOrder = 9
        let matched = AddBookURLService.matchingSource(
            bookURL: "https://site.example/book/1,{\"origin\":\"https://chosen.example\"}",
            sources: [exact, explicit]
        )
        #expect(matched?.bookSourceUrl == explicit.bookSourceUrl)
    }

    @Test func exactBasePrecedesPattern() {
        var pattern = BookSource(bookSourceUrl: "https://fallback.example", bookSourceName: "正则源")
        pattern.bookUrlPattern = #"https://site\.example/book/.*"#
        pattern.customOrder = 0
        var exact = BookSource(bookSourceUrl: "https://site.example", bookSourceName: "域名源")
        exact.customOrder = 10
        let matched = AddBookURLService.matchingSource(bookURL: "https://site.example/book/1", sources: [pattern, exact])
        #expect(matched?.bookSourceUrl == exact.bookSourceUrl)
    }

    @Test func patternRequiresWholeURLMatchAndEnabledSource() {
        var disabled = BookSource(bookSourceUrl: "https://disabled.example", bookSourceName: "停用")
        disabled.bookUrlPattern = #"https://site\.example/book/.*"#; disabled.enabled = false
        var enabled = BookSource(bookSourceUrl: "https://enabled.example", bookSourceName: "启用")
        enabled.bookUrlPattern = #"https://site\.example/book/\d+"#
        let matched = AddBookURLService.matchingSource(bookURL: "https://site.example/book/12", sources: [disabled, enabled])
        #expect(matched?.bookSourceUrl == enabled.bookSourceUrl)
        #expect(AddBookURLService.matchingSource(bookURL: "https://site.example/book/12/extra", sources: [enabled]) == nil)
    }
}
