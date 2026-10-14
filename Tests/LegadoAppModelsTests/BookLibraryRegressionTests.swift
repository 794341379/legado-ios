import Foundation
import Testing
import LegadoCore
@testable import LegadoAppModels

@MainActor
struct BookLibraryRegressionTests {
    private let source = BookSource(bookSourceUrl: "https://source.test", bookSourceName: "测试源")

    private func fixture() -> (Book, [BookChapter]) {
        var book = Book(bookUrl: "https://source.test/book", name: "书", origin: source.bookSourceUrl)
        book.totalChapterNum = 2
        book.durChapterTitle = "第一章"
        let chapters = (0..<3).map {
            BookChapter(url: "https://source.test/\($0)", title: ["第一章", "第二章", "第三章"][$0], bookUrl: book.bookUrl, index: $0)
        }
        return (book, chapters)
    }

    @Test func directoryRefreshPreservesConcurrentReadingAndGroupChanges() async throws {
        let (book, chapters) = fixture()
        let repository = InMemoryBookRepository(books: [book])
        let loader = DelayedChapterLoader(chapters: chapters)
        let model = BookLibraryModel(
            repository: repository,
            updateCoordinator: .init(repository: InMemoryBookChapterRepository(), loader: loader)
        )
        await model.load()
        let update = Task { await model.checkForUpdates(sources: [source]) }
        await loader.waitForRequest()
        await model.updateProgress(for: book, chapter: chapters[1], position: 123)
        await model.setBook(book, groupIDs: [8])
        await loader.finish()
        await update.value

        let stored = try #require(model.books.first)
        #expect(stored.durChapterIndex == 1)
        #expect(stored.durChapterPos == 123)
        #expect(stored.group == 8)
        #expect(stored.totalChapterNum == 3)
        #expect(stored.latestChapterTitle == "第三章")
        #expect(try await repository.load() == model.books)
    }

    @Test func directoryRefreshDoesNotResurrectRemovedBooksOrDropNewBooks() async throws {
        let (book, chapters) = fixture()
        let repository = InMemoryBookRepository(books: [book])
        let loader = DelayedChapterLoader(chapters: chapters)
        let model = BookLibraryModel(
            repository: repository,
            updateCoordinator: .init(repository: InMemoryBookChapterRepository(), loader: loader),
            chapterRepository: InMemoryBookChapterRepository()
        )
        await model.load()
        let update = Task { await model.checkForUpdates(sources: [source]) }
        await loader.waitForRequest()
        await model.remove(bookURL: book.bookUrl)
        let added = Book(bookUrl: "local://new", name: "新增书")
        await model.addOrUpdate(added)
        await loader.finish()
        await update.value

        #expect(model.books == [added])
        #expect(try await repository.load() == [added])
    }

    @Test func overlappingShelfWritesKeepProgressAndGroupChanges() async throws {
        let (book, chapters) = fixture()
        let repository = SuspendedBookRepository(books: [book])
        let model = BookLibraryModel(repository: repository)
        await model.load()
        let progress = Task { await model.updateProgress(for: book, chapter: chapters[1], position: 42) }
        await repository.waitForSave()
        var groupStarted = false
        let group = Task {
            groupStarted = true
            await model.setBook(book, groupIDs: [4])
        }
        while !groupStarted { await Task.yield() }
        #expect(model.books.first?.group == 4)
        await repository.finishSave()
        await progress.value
        await group.value

        #expect(model.books.first?.durChapterPos == 42)
        #expect(model.books.first?.group == 4)
        #expect(try await repository.load() == model.books)
    }

    @Test func failedSaveRestoresLastPersistedShelf() async throws {
        let (book, _) = fixture()
        let repository = FailingBookRepository(books: [book])
        let model = BookLibraryModel(repository: repository)
        await model.load()
        await model.setBook(book, groupIDs: [4])
        #expect(model.books == [book])
        #expect(model.errorMessage != nil)
        #expect(try await repository.load() == [book])
    }
}

private actor DelayedChapterLoader: ChapterListLoading {
    let chapters: [BookChapter]
    private var requested = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(chapters: [BookChapter]) { self.chapters = chapters }
    func loadChapters(book: Book, source: BookSource, maxPages: Int) async -> ChapterListReport {
        requested = true
        await withCheckedContinuation { continuation = $0 }
        return .init(chapters: chapters)
    }
    func waitForRequest() async { while !requested { await Task.yield() } }
    func finish() { continuation?.resume(); continuation = nil }
}

private actor SuspendedBookRepository: BookRepository {
    private var books: [Book]
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(books: [Book]) { self.books = books }
    func load() -> [Book] { books }
    func save(_ books: [Book]) async {
        if !started {
            started = true
            await withCheckedContinuation { continuation = $0 }
        }
        self.books = books
    }
    func waitForSave() async { while !started { await Task.yield() } }
    func finishSave() { continuation?.resume(); continuation = nil }
}

private actor FailingBookRepository: BookRepository {
    let books: [Book]
    init(books: [Book]) { self.books = books }
    func load() -> [Book] { books }
    func save(_ books: [Book]) throws { throw CocoaError(.fileWriteOutOfSpace) }
}
