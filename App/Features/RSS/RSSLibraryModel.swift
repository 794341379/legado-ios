import Foundation
import SwiftUI

@MainActor
final class RSSLibraryModel: ObservableObject {
    @Published private(set) var sources: [RssSource] = []
    @Published private(set) var articles: [RssArticle] = []
    @Published private(set) var stars: [RssStar] = []
    @Published private(set) var records: [RssReadRecord] = []
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let sourceRepository: SQLiteRssSourceRepository
    private let articleRepository: SQLiteRssArticleRepository
    private let starRepository: SQLiteRssStarRepository
    private let recordRepository: SQLiteRssReadRecordRepository
    private let service: RSSService
    private let importer = RSSSourceImporter()
    private let database: LegadoDatabase
    private var nextURL: String?
    private var page = 1
    private var order: Int64 = 0

    init(database: LegadoDatabase, service: RSSService = .init()) {
        self.database = database
        sourceRepository = .init(database: database)
        articleRepository = .init(database: database)
        starRepository = .init(database: database)
        recordRepository = .init(database: database)
        self.service = service
    }

    static func live() -> RSSLibraryModel {
        let database = try! LegadoDatabase(url: LegadoDatabase.defaultURL())
        return .init(database: database)
    }

    func load() async {
        do {
            async let loadedSources = sourceRepository.all()
            async let loadedStars = starRepository.all()
            async let loadedRecords = recordRepository.all()
            (sources, stars, records) = try await (loadedSources, loadedStars, loadedRecords)
        } catch { errorMessage = error.localizedDescription }
    }

    func importFiles(_ urls: [URL]) async {
        await perform {
            var merged = self.sources
            for url in urls {
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let payload = try self.importer.decode(Data(contentsOf: url))
                merged = try self.importer.merge(payload.sources, into: merged)
                for remote in payload.subscriptionURLs { merged = try await self.importRemote(remote, existing: merged) }
            }
            try await self.sourceRepository.save(merged)
            self.sources = try await self.sourceRepository.all()
        }
    }

    func importText(_ text: String) async {
        await perform {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                self.sources = try await self.importRemote(trimmed, existing: self.sources)
            } else {
                let payload = try self.importer.decode(Data(trimmed.utf8))
                var merged = try self.importer.merge(payload.sources, into: self.sources)
                for remote in payload.subscriptionURLs { merged = try await self.importRemote(remote, existing: merged) }
                self.sources = merged
            }
            try await self.sourceRepository.save(self.sources)
        }
    }

    func applySilentSubscription(_ data: Data) async throws {
        let incoming = try importer.decode(data).sources
        var updated = sources
        for var source in incoming {
            if let index = updated.firstIndex(where: { $0.sourceUrl == source.sourceUrl }) {
                guard updated[index].lastUpdateTime < source.lastUpdateTime else { continue }
                source.sourceGroup = updated[index].sourceGroup
                updated[index] = source
            } else { updated.append(source) }
        }
        try await sourceRepository.save(updated)
        sources = try await sourceRepository.all()
    }

    func setEnabled(_ enabled: Bool, source: RssSource) async {
        do { try await sourceRepository.setEnabled(enabled, sourceURL: source.sourceUrl); sources = try await sourceRepository.all() }
        catch { errorMessage = error.localizedDescription }
    }
    func remove(_ source: RssSource) async {
        do { try await sourceRepository.remove(sourceURL: source.sourceUrl); sources = try await sourceRepository.all() }
        catch { errorMessage = error.localizedDescription }
    }

    func moveSources(from offsets: IndexSet, to destination: Int) async {
        var values = sources
        values.move(fromOffsets: offsets, toOffset: destination)
        for index in values.indices { values[index].customOrder = index }
        do { try await sourceRepository.save(values); sources = try await sourceRepository.all() }
        catch { errorMessage = error.localizedDescription }
    }

    func save(_ value: RssSource, replacing originalURL: String?) async -> Bool {
        let name = value.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = value.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !url.isEmpty else { errorMessage = "源名称和URL不能为空"; return false }
        do {
            var source = value; source.sourceName = name; source.sourceUrl = url
            let original = originalURL.flatMap { key in sources.first { $0.sourceUrl == key } }
            let encoder = JSONEncoder()
            let oldData = try encoder.encode(original)
            let newData = try encoder.encode(source)
            if oldData != newData { source.lastUpdateTime = Int64(Date().timeIntervalSince1970 * 1_000) }
            if let originalURL, originalURL != source.sourceUrl {
                try await starRepository.updateOrigin(from: originalURL, to: source.sourceUrl)
                try await articleRepository.updateOrigin(from: originalURL, to: source.sourceUrl)
                try await database.deleteSourceVariables(originalURL)
            }
            var values = sources.filter { $0.sourceUrl != originalURL && $0.sourceUrl != source.sourceUrl }
            values.append(source)
            try await sourceRepository.save(values)
            sources = try await sourceRepository.all()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func refresh(_ source: RssSource, sortName: String? = nil, sortURL: String? = nil, key: String? = nil) async {
        page = 1; order = Int64(Date().timeIntervalSince1970 * 1_000)
        let name = sortName ?? source.sourceName
        let url = sortURL ?? source.sortUrl?.nilIfBlank ?? source.sourceUrl
        await perform {
            let report = try await self.service.articles(sortName: name, sortURL: url, source: source, page: 1, key: key)
            var values = report.result.articles
            for index in values.indices { values[index].order = self.order; self.order -= 1 }
            try await self.articleRepository.put(values)
            if source.ruleNextPage?.isEmpty == false { try await self.articleRepository.clearOld(origin: source.sourceUrl, sort: name, before: self.order) }
            self.nextURL = report.result.nextURL
            self.articles = try await self.articleRepository.articles(origin: source.sourceUrl, sort: name)
        }
    }

    func loadMore(_ source: RssSource, sortName: String? = nil, key: String? = nil) async {
        guard let nextURL, !nextURL.isEmpty else { return }
        page += 1
        let name = sortName ?? source.sourceName
        await perform {
            let report = try await self.service.articles(sortName: name, sortURL: nextURL, source: source, page: self.page, key: key)
            var values = report.result.articles
            for index in values.indices { values[index].order = self.order; self.order -= 1 }
            try await self.articleRepository.append(values)
            self.nextURL = report.result.nextURL
            self.articles = try await self.articleRepository.articles(origin: source.sourceUrl, sort: name)
        }
    }

    func read(_ article: RssArticle) async {
        do {
            try await recordRepository.insertIgnoringExisting(article.record())
            records = try await recordRepository.all()
            if let index = articles.firstIndex(of: article) { articles[index].read = true }
        }
        catch { errorMessage = error.localizedDescription }
    }
    func readingMode(for article: RssArticle, source: RssSource) async -> RSSReadingMode {
        let policy = RSSReadingPolicy()
        if article.type == 0, article.description?.nilIfBlank != nil {
            return policy.mode(article: article, source: source)
        }
        guard let rule = source.ruleContent?.nilIfBlank else {
            return policy.mode(article: article, source: source)
        }
        do {
            let content = try await service.content(article: article, rule: rule, source: source)
            if article.type == 0 {
                var updated = article; updated.description = content
                try await articleRepository.put([updated])
                if var star = try await starRepository.star(origin: article.origin, link: article.link) {
                    star.description = content; try await starRepository.save(star); stars = try await starRepository.all()
                }
            }
            return policy.mode(article: article, source: source, resolvedContent: content)
        } catch {
            errorMessage = error.localizedDescription
            if article.type == 0 { return .html(content: "加载正文失败\n\(error.localizedDescription)", baseURL: nil) }
            return policy.mode(article: article, source: source)
        }
    }
    func toggleStar(_ article: RssArticle) async {
        do {
            if try await starRepository.star(origin: article.origin, link: article.link) != nil {
                try await starRepository.remove(origin: article.origin, link: article.link)
            } else { try await starRepository.save(article.star()) }
            stars = try await starRepository.all()
        } catch { errorMessage = error.localizedDescription }
    }
    func isStarred(_ article: RssArticle) -> Bool { stars.contains { $0.origin == article.origin && $0.link == article.link } }

    func removeStar(_ value: RssStar) async {
        do { try await starRepository.remove(origin: value.origin, link: value.link); stars = try await starRepository.all() }
        catch { errorMessage = error.localizedDescription }
    }

    func saveStar(_ value: RssStar) async {
        do { try await starRepository.save(value); stars = try await starRepository.all() }
        catch { errorMessage = error.localizedDescription }
    }

    func clearStars() async {
        do { try await starRepository.clear(); stars = [] }
        catch { errorMessage = error.localizedDescription }
    }

    func clearRecords() async {
        do { try await recordRepository.clear(); records = [] }
        catch { errorMessage = error.localizedDescription }
    }

    private func importRemote(_ value: String, existing: [RssSource]) async throws -> [RssSource] {
        let withoutUA = value.hasSuffix("#requestWithoutUA")
        let raw = withoutUA ? String(value.dropLast("#requestWithoutUA".count)) : value
        guard let url = URL(string: raw) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        if withoutUA { request.setValue("", forHTTPHeaderField: "User-Agent") }
        let (data, response) = try await URLSessionHTTPTransport.shared.download(for: request)
        guard (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) != false else { throw URLError(.badServerResponse) }
        let payload = try importer.decode(data)
        return try importer.merge(payload.sources, into: existing)
    }
    private func perform(_ operation: () async throws -> Void) async {
        isWorking = true; defer { isWorking = false }
        do { try await operation() } catch { errorMessage = error.localizedDescription }
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
