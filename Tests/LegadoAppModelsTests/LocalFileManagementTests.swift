import Foundation
import Testing
import LegadoCore
@testable import LegadoAppModels

@MainActor
struct LocalFileManagementTests {
    private func fixture(fails: Bool = false) async throws -> (URL, Book, BookLibraryModel) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("原文件.txt")
        try "第一章 开始\n正文".write(to: file, atomically: true, encoding: .utf8)
        var book = Book(bookUrl: file.absoluteString, name: "原书名", origin: "local")
        book.originName = file.lastPathComponent
        book.durChapterIndex = 2
        book.durChapterTitle = "第三章"
        book.durChapterPos = 42
        book.group = 8
        let repository: any BookRepository = fails ? FileOperationFailingRepository(books: [book]) : InMemoryBookRepository(books: [book])
        let model = BookLibraryModel(repository: repository, localDirectory: root, chapterRepository: InMemoryBookChapterRepository())
        await model.load()
        return (root, book, model)
    }

    @Test func renamingFileRetargetsShelfAndPreservesTitleAndReadingState() async throws {
        let (root, original, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await model.renameLocalFile(at: URL(string: original.bookUrl)!, to: "新文件")
        let book = try #require(model.books.first)
        #expect(book.bookUrl == root.appendingPathComponent("新文件.txt").absoluteString)
        #expect(book.originName == "新文件.txt")
        #expect(book.name == original.name)
        #expect(book.durChapterIndex == 2 && book.durChapterPos == 42 && book.group == 8)
        #expect(FileManager.default.fileExists(atPath: URL(string: book.bookUrl)!.path))
        #expect(!FileManager.default.fileExists(atPath: URL(string: original.bookUrl)!.path))
    }

    @Test func failedShelfSaveRestoresRenamedFileAndShelf() async throws {
        let (root, book, model) = try await fixture(fails: true)
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: (any Error).self) { try await model.renameLocalFile(at: URL(string: book.bookUrl)!, to: "新文件") }
        #expect(model.books == [book])
        #expect(FileManager.default.fileExists(atPath: URL(string: book.bookUrl)!.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("新文件.txt").path))
    }

    @Test func failedShelfSaveRestoresDeletedFileBytes() async throws {
        let (root, book, model) = try await fixture(fails: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = URL(string: book.bookUrl)!
        let data = try Data(contentsOf: file)
        await #expect(throws: (any Error).self) { try await model.deleteLocalFile(at: file) }
        #expect(model.books == [book])
        #expect(try Data(contentsOf: file) == data)
    }

    @Test func deletingFileAlsoRemovesShelfReference() async throws {
        let (root, book, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = URL(string: book.bookUrl)!
        try await model.deleteLocalFile(at: file)
        #expect(model.books.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try await model.localFiles.list().isEmpty)
    }

    @Test func mixedImportKeepsSuccessfulFilesAndReportsUnsupportedOnes() async throws {
        let (root, original, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("原文件.txt")
        let unsupported = root.appendingPathComponent("unsupported.pdf")
        try Data("pdf".utf8).write(to: unsupported)
        await model.importLocalFiles([source, unsupported, source])
        #expect(model.books.count == 3)
        #expect(model.books.first == original)
        #expect(model.errorMessage?.contains("unsupported.pdf") == true)
        #expect(try await model.localFiles.list().count == 3)
    }

    @Test func missingFileFromOldContainerCanBeRemovedFromShelf() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let missing = root.appendingPathComponent("old-container/missing.txt")
        let book = Book(bookUrl: missing.absoluteString, name: "丢失的书", origin: "local")
        let model = BookLibraryModel(repository: InMemoryBookRepository(books: [book]), localDirectory: root.appendingPathComponent("current-container"))
        await model.load()
        try await model.deleteLocalFile(at: missing)
        #expect(model.books.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func existingFileOutsideLibraryCannotBeDeletedThroughShelf() async throws {
        let (root, _, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let external = root.appendingPathComponent("原文件.txt")
        let bytes = try Data(contentsOf: external)
        let book = Book(bookUrl: external.absoluteString, name: "外部文件", origin: "local")
        let model = BookLibraryModel(repository: InMemoryBookRepository(books: [book]), localDirectory: root.appendingPathComponent("managed"))
        await model.load()
        await #expect(throws: LocalFileError.outsideLibrary) { try await model.deleteLocalFile(at: external) }
        #expect(model.books == [book])
        #expect(try Data(contentsOf: external) == bytes)
    }
}

private actor FileOperationFailingRepository: BookRepository {
    let books: [Book]
    init(books: [Book]) { self.books = books }
    func load() -> [Book] { books }
    func save(_ books: [Book]) throws { throw CocoaError(.fileWriteOutOfSpace) }
}
