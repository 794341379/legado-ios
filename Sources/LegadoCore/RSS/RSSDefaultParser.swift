import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct RSSParseResult: Sendable, Equatable {
    public var articles: [RssArticle]
    public var nextURL: String?
    public init(articles: [RssArticle], nextURL: String? = nil) {
        self.articles = articles
        self.nextURL = nextURL
    }
}

public enum RSSDefaultParser {
    public static func parse(sortName: String, xml: String, sourceURL: String) throws -> RSSParseResult {
        let delegate = Delegate(sortName: sortName, sourceURL: sourceURL)
        let parser = XMLParser(data: Data(xml.utf8))
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? RSSParserError.invalidXML }
        return .init(articles: delegate.articles)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let sortName: String
        let sourceURL: String
        var articles: [RssArticle] = []
        var article = RssArticle()
        var insideItem = false
        var activeField: String?
        var text = ""

        init(sortName: String, sourceURL: String) {
            self.sortName = sortName
            self.sourceURL = sourceURL
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let name = elementName.lowercased()
            if name == "item" { insideItem = true; article = RssArticle(); return }
            guard insideItem else { return }
            if name == "media:thumbnail" {
                article.image = attribute(attributeDict, named: "url")
            } else if name == "enclosure", attribute(attributeDict, named: "type")?.localizedCaseInsensitiveContains("image/") == true {
                article.image = attribute(attributeDict, named: "url")
            }
            if ["title", "link", "description", "content:encoded", "pubdate", "time"].contains(name) {
                activeField = name
                text = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if insideItem, activeField != nil { text += string }
        }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if insideItem, activeField != nil { text += String(decoding: CDATABlock, as: UTF8.self) }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let name = elementName.lowercased()
            if name == "item" {
                article.origin = sourceURL; article.sort = sortName; articles.append(article)
                insideItem = false; activeField = nil
                return
            }
            guard insideItem, name == activeField else { return }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "title": article.title = value
            case "link": article.link = value
            case "description": article.description = value; if article.image == nil { article.image = firstImageURL(in: text) }
            case "content:encoded": article.content = value; if article.image == nil { article.image = firstImageURL(in: text) }
            case "pubdate", "time": article.pubDate = value
            default: break
            }
            activeField = nil; text = ""
        }

        private func attribute(_ values: [String: String], named name: String) -> String? {
            values.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        private func firstImageURL(in input: String) -> String? {
            guard let expression = try? NSRegularExpression(pattern: "(<img [^>]*>)", options: .caseInsensitive),
                  let image = expression.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
                  let tagRange = Range(image.range(at: 1), in: input) else { return nil }
            let tag = String(input[tagRange])
            guard let expression = try? NSRegularExpression(pattern: #"src\s*=\s*\"([^\"]+)\""#, options: .caseInsensitive),
                  let source = expression.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                  let sourceRange = Range(source.range(at: 1), in: tag) else { return nil }
            return String(tag[sourceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

public enum RSSParserError: Error, LocalizedError, Sendable {
    case invalidXML
    case emptyBody(String)
    public var errorDescription: String? {
        switch self {
        case .invalidXML: "RSS XML解析失败"
        case .emptyBody(let source): "获取网页内容失败：\(source)"
        }
    }
}
