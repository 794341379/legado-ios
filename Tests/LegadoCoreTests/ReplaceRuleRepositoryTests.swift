import Foundation
import Testing
@testable import LegadoCore

struct ReplaceRuleRepositoryTests {
    @Test func decodesOrderFieldAndDefaults() throws {
        let data = Data(#"{"id":9,"name":"广告","pattern":"ad","replacement":"","order":12}"#.utf8)
        let rule = try #require(ReplaceRuleImporter().decode(data).first)

        #expect(rule.id == 9)
        #expect(rule.sortOrder == 12)
        #expect(rule.scopeContent)
        #expect(rule.isEnabled)
        #expect(rule.isRegex)
        #expect(rule.timeoutMillisecond == 3_000)
    }

    @Test func mergesByIdentifierAndSorts() {
        var old = ReplaceRule(id: 1, name: "旧", pattern: "old")
        old.sortOrder = 10
        var replacement = ReplaceRule(id: 1, name: "新", pattern: "new")
        replacement.sortOrder = 3
        var first = ReplaceRule(id: 2, name: "先", pattern: "first")
        first.sortOrder = 1

        let merged = ReplaceRuleImporter().merge([replacement, first], into: [old])

        #expect(merged.map(\.id) == [2, 1])
        #expect(merged.last?.name == "新")
    }

    @Test func persistsRulesAtomically() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileReplaceRuleRepository(fileURL: directory.appending(path: "rules.json"))
        let rule = ReplaceRule(id: 3, name: "空行", pattern: "\\n{3,}", replacement: "\n\n")

        try await repository.save([rule])
        let restored = try await repository.load()

        #expect(restored == [rule])
    }
}
