import Foundation
import Testing
@testable import LegadoCore

private struct DebuggerMockTransport: HTTPTransport {
    let pages: [String: String]

    func data(for request: URLRequest) async throws -> HTTPResponse {
        let url = try #require(request.url)
        let body = try #require(pages[url.absoluteString], "缺少调试页面：\(url.absoluteString)")
        return .init(data: Data(body.utf8), statusCode: 200, headers: [:], finalURL: url)
    }
}

struct BookSourceDebuggerTests {
    @Test func runsSearchDetailTocAndContentInOrder() async throws {
        let pages = [
            "https://debug.example.test/search?q=demo": #"{"books":[{"name":"调试之书","url":"/book/1"}]}"#,
            "https://debug.example.test/book/1": #"<h1>调试之书</h1><a class="toc" href="/toc/1">目录</a>"#,
            "https://debug.example.test/toc/1": #"<li class="chapter"><a href="/chapter/1">第一章</a></li>"#,
            "https://debug.example.test/chapter/1": "<article>调试正文成功</article>"
        ]
        var source = BookSource(bookSourceUrl: "https://debug.example.test", bookSourceName: "调试源")
        source.searchUrl = "/search?q={{key}}"
        source.ruleSearch = .init(bookList: "$.books", name: "$.name", bookUrl: "$.url")
        var info = BookInfoRule()
        info.name = "@CSS:h1@text"
        info.tocUrl = "@CSS:a.toc@href"
        source.ruleBookInfo = info
        var toc = TocRule()
        toc.chapterList = "@CSS:li.chapter"
        toc.chapterName = "@CSS:a@text"
        toc.chapterUrl = "@CSS:a@href"
        source.ruleToc = toc
        var content = ContentRule()
        content.content = "@CSS:article@text"
        source.ruleContent = content

        let report = await BookSourceDebugger(transport: DebuggerMockTransport(pages: pages))
            .run(source: source, keyword: "demo")

        #expect(report.steps.map(\.stage) == SourceDebugStage.allCases)
        #expect(report.steps.allSatisfy { $0.status == .passed })
        #expect(report.sampleBookName == "调试之书")
        #expect(report.sampleChapterTitle == "第一章")
        #expect(report.contentPreview == "调试正文成功")
        #expect(report.passed)
    }

    @Test func reportsConfigurationAndSkipsAfterEmptySearch() async {
        let pages = ["https://debug.example.test/search?q=none": #"{"books":[]}"#]
        var source = BookSource(bookSourceUrl: "https://debug.example.test", bookSourceName: "空源")
        source.searchUrl = "/search?q={{key}}"
        source.ruleSearch = .init(bookList: "$.books", name: "$.name", bookUrl: "$.url")

        let report = await BookSourceDebugger(transport: DebuggerMockTransport(pages: pages))
            .run(source: source, keyword: "none")

        #expect(report.steps.first?.status == .failed)
        #expect(report.steps.first(where: { $0.stage == .search })?.status == .failed)
        #expect(report.steps.first(where: { $0.stage == .detail })?.status == .skipped)
        #expect(!report.passed)
    }
}
