import Foundation
import Testing
@testable import LegadoCore

private struct ImportedSourceTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> HTTPResponse {
        let url = try #require(request.url)
        let text: String
        switch url.path {
        case "/search":
            text = #"{"books":[{"name":"第一本","url":"/book/1"},{"name":"第二本","url":"/book/2"}]}"#
        case "/book/2":
            text = #"<h1>第二本</h1><a class="toc" href="/toc/2">目录</a>"#
        case "/toc/2":
            text = #"<li><a href="/chapter/2">第一章</a></li>"#
        case "/chapter/2": text = "<article>导入后正文解析成功</article>"
        default: throw URLError(.fileDoesNotExist)
        }
        return .init(data: Data(text.utf8), statusCode: 200, headers: [:], finalURL: url)
    }
}

struct ImportedSourcePipelineTests {
    @Test func importedAndEditedSourceRunsSearchDetailTocAndContentInOrder() async throws {
        let json = #"{"bookSourceUrl":"https://pipeline.test","bookSourceName":"导入源","searchUrl":"/search?q={{key}}","ruleSearch":"{\"bookList\":\"-$.books\",\"name\":\"$.name\",\"bookUrl\":\"$.url\"}","ruleBookInfo":{"name":"@CSS:h1@text","tocUrl":"@CSS:a.toc@href"},"ruleToc":{"chapterList":"@CSS:li","chapterName":"@CSS:a@text","chapterUrl":"@CSS:a@href"},"ruleContent":{"content":"@CSS:missing@text","future":true}}"#
        let imported = try #require(BookSourceImporter().decode(Data(json.utf8)).first)
        var draft = try BookSourceEditorDocument(source: imported)
        draft.set(.string("@CSS:article@text"), at: "ruleContent.content")
        let saved = try JSONDecoder().decode(BookSource.self, from: JSONEncoder().encode(draft.source()))
        let report = await BookSourceDebugger(transport: ImportedSourceTransport()).run(source: saved, keyword: "任意")
        #expect(report.passed)
        #expect(report.sampleBookName == "第二本")
        #expect(report.sampleChapterTitle == "第一章")
        #expect(report.contentPreview == "导入后正文解析成功")
        #expect(saved.additionalFields["ruleContent"]?["future"] == .bool(true))
    }

    @Test func plusListPrefixKeepsSearchOrder() async throws {
        var source = BookSource(bookSourceUrl: "https://pipeline.test", bookSourceName: "正序")
        source.searchUrl = "/search?q={{key}}"
        source.ruleSearch = .init(bookList: "+$.books", name: "$.name", bookUrl: "$.url")
        var iterator = BookSearchService(transport: ImportedSourceTransport()).searchOutcomes(keyword: "任意", sources: [source]).makeAsyncIterator()
        let outcome = try #require(await iterator.next())
        #expect(outcome.books.map(\.name) == ["第一本", "第二本"])
        #expect(outcome.diagnostics.isEmpty)
    }
}
