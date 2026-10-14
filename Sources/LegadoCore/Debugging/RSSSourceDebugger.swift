import Foundation

public enum RSSDebugStage: String, Codable, CaseIterable, Sendable {
    case configuration, listRequest, listParse, contentRequest, contentParse

    public var title: String {
        switch self {
        case .configuration: "配置"
        case .listRequest: "列表请求"
        case .listParse: "列表解析"
        case .contentRequest: "正文请求"
        case .contentParse: "正文解析"
        }
    }
}

public struct RSSDebugStep: Codable, Hashable, Identifiable, Sendable {
    public var stage: RSSDebugStage
    public var status: SourceDebugStatus
    public var summary: String
    public var diagnostics: [RuleDiagnostic]
    public var id: RSSDebugStage { stage }
}

public struct RSSSourceDebugReport: Sendable {
    public var sourceURL: String
    public var input: String
    public var steps: [RSSDebugStep] = []
    public var listSource: String?
    public var contentSource: String?
    public var articles: [RssArticle] = []
    public var contentPreview: String?
    public var passed: Bool { !steps.contains { $0.status == .failed } && steps.contains { $0.stage == .listParse && $0.status != .skipped } }
}

public struct RSSSourceDebugger: Sendable {
    private let service: RSSService
    public init(service: RSSService = .init()) { self.service = service }

    public func run(source: RssSource, input: String) async -> RSSSourceDebugReport {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var report = RSSSourceDebugReport(sourceURL: source.sourceUrl, input: input)
        let listURL = resolvedListURL(source: source, input: input)
        let missing = source.sourceUrl.isEmpty || listURL.isEmpty || source.sourceName.isEmpty
        report.steps.append(.init(stage: .configuration, status: missing ? .failed : .passed, summary: missing ? "源名称、源URL或调试地址为空" : "使用地址：\(listURL)", diagnostics: []))
        guard !missing else { appendSkipped(after: .configuration, to: &report, reason: "配置不完整"); return report }

        do {
            let fetched = try await service.articlesDetailed(sortName: input, sortURL: listURL, source: source, page: 1, key: input.isEmpty ? nil : input)
            report.listSource = fetched.body
            report.steps.append(.init(stage: .listRequest, status: (200..<400).contains(fetched.statusCode) ? .passed : .warning, summary: "HTTP \(fetched.statusCode)；\(fetched.finalURL)", diagnostics: []))
            report.articles = fetched.report.result.articles
            report.steps.append(.init(stage: .listParse, status: report.articles.isEmpty ? .failed : (fetched.report.diagnostics.isEmpty ? .passed : .warning), summary: report.articles.isEmpty ? "没有解析到文章" : "解析到 \(report.articles.count) 篇文章", diagnostics: fetched.report.diagnostics))
            guard let article = report.articles.first, let rule = source.ruleContent, !rule.isEmpty else {
                report.steps.append(.init(stage: .contentRequest, status: .skipped, summary: "没有样本文章或未配置正文规则", diagnostics: []))
                report.steps.append(.init(stage: .contentParse, status: .skipped, summary: "正文将直接使用描述或网页", diagnostics: []))
                return report
            }
            let content = try await service.contentDetailed(article: article, rule: rule, source: source)
            report.contentSource = content.body
            report.steps.append(.init(stage: .contentRequest, status: (200..<400).contains(content.statusCode) ? .passed : .warning, summary: "HTTP \(content.statusCode)；\(content.finalURL)", diagnostics: []))
            let cleaned = content.content.trimmingCharacters(in: .whitespacesAndNewlines)
            report.contentPreview = cleaned.isEmpty ? nil : String(cleaned.prefix(400))
            report.steps.append(.init(stage: .contentParse, status: cleaned.isEmpty ? .failed : (content.diagnostics.isEmpty ? .passed : .warning), summary: cleaned.isEmpty ? "正文结果为空" : "正文结果 \(cleaned.count) 字", diagnostics: content.diagnostics))
        } catch {
            let reachedList = report.steps.contains { $0.stage == .listRequest }
            let stage: RSSDebugStage = reachedList ? .contentRequest : .listRequest
            report.steps.append(.init(stage: stage, status: .failed, summary: error.localizedDescription, diagnostics: []))
            appendSkipped(after: stage, to: &report, reason: "前一阶段失败")
        }
        return report
    }

    private func resolvedListURL(source: RssSource, input: String) -> String {
        if let separator = input.range(of: "::") { return String(input[separator.upperBound...]) }
        if !input.isEmpty, let search = source.searchUrl, !search.isEmpty { return search }
        return source.sourceUrl
    }

    private func appendSkipped(after stage: RSSDebugStage, to report: inout RSSSourceDebugReport, reason: String) {
        guard let index = RSSDebugStage.allCases.firstIndex(of: stage) else { return }
        let existing = Set(report.steps.map(\.stage))
        for value in RSSDebugStage.allCases.dropFirst(index + 1) where !existing.contains(value) {
            report.steps.append(.init(stage: value, status: .skipped, summary: reason, diagnostics: []))
        }
    }
}
