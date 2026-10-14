import Foundation
import Testing
@testable import LegadoCore

struct BookRepositoryTests {
    @Test func persistsBooksAtomically() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "books.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileBookRepository(fileURL: fileURL)
        var book = Book(bookUrl: "https://example.test/book/1", name: "测试书", author: "作者", origin: "https://example.test")
        book.durChapterIndex = 3

        try await repository.save([book])
        let restored = try await repository.load()

        #expect(restored == [book])
        #expect(restored.first?.durChapterIndex == 3)
    }
}
