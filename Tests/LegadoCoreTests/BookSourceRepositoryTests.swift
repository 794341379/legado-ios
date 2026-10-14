import Foundation
import Testing
@testable import LegadoCore

struct BookSourceRepositoryTests {
    @Test func fileRepositoryPersistsAtomically() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileBookSourceRepository(fileURL: directory.appending(path: "sources.json"))
        let expected = [BookSource(bookSourceUrl: "https://saved.test", bookSourceName: "已保存")]

        try await repository.save(expected)
        let loaded = try await repository.load()

        #expect(loaded == expected)
    }

    @Test func groupOperationsSplitSeparatorsAndDeduplicate() {
        var source = BookSource(bookSourceUrl: "https://groups.test", bookSourceName: "分组源")
        source.bookSourceGroup = "文学, 科幻；文学;听书"

        #expect(source.groups == ["文学", "科幻", "听书"])
        #expect(source.hasGroup("科幻"))

        source.addGroups("悬疑，科幻")
        #expect(source.groups == ["文学", "科幻", "听书", "悬疑"])

        source.removeGroups("文学;听书")
        #expect(source.bookSourceGroup == "科幻,悬疑")
    }

    @Test func renamesAndDeletesGroupsWithoutLeavingEmptyText() {
        var source = BookSource(bookSourceUrl: "https://rename.test", bookSourceName: "重命名源")
        source.bookSourceGroup = "旧组,保留"

        source.replaceGroup("旧组", with: "新组")
        #expect(source.groups == ["保留", "新组"])
        source.replaceGroup("保留", with: nil)
        source.removeGroups("新组")

        #expect(source.groups.isEmpty)
        #expect(source.bookSourceGroup == nil)
    }
}
