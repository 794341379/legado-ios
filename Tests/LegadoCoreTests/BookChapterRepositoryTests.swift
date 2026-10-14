import Foundation
import Testing
@testable import LegadoCore

struct BookChapterRepositoryTests {
    @Test func normalizesAndPersistsChaptersPerBook() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileBookChapterRepository(directory: directory)
        var chapter = BookChapter(url: "1", title: "第一章", bookUrl: "wrong", index: 9)
        chapter.wordCount = "1000"

        try await repository.save([chapter], bookURL: "book-a")
        let restored = try await repository.load(bookURL: "book-a")

        #expect(restored.first?.bookUrl == "book-a")
        #expect(restored.first?.index == 0)
        #expect(restored.first?.wordCount == "1000")
        #expect(try await repository.load(bookURL: "book-b").isEmpty)
    }

    @Test func removesOnlyRequestedBook() async throws {
        let repository = InMemoryBookChapterRepository()
        let a = BookChapter(url: "1", title: "A", bookUrl: "a", index: 0)
        let b = BookChapter(url: "1", title: "B", bookUrl: "b", index: 0)
        await repository.save([a], bookURL: "a")
        await repository.save([b], bookURL: "b")

        await repository.remove(bookURL: "a")

        #expect(await repository.load(bookURL: "a").isEmpty)
        #expect(await repository.load(bookURL: "b") == [b])
    }
}
