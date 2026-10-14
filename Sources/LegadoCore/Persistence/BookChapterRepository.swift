import CryptoKit
import Foundation

public protocol BookChapterRepository: Sendable {
    func load(bookURL: String) async throws -> [BookChapter]
    func save(_ chapters: [BookChapter], bookURL: String) async throws
    func remove(bookURL: String) async throws
}

public actor FileBookChapterRepository: BookChapterRepository {
    public static let maximumDocumentBytes = 24 * 1_024 * 1_024
    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    public static func live() -> FileBookChapterRepository {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Legado/Chapters", isDirectory: true)
        return FileBookChapterRepository(directory: directory)
    }

    public func load(bookURL: String) throws -> [BookChapter] {
        let url = fileURL(bookURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maximumDocumentBytes else {
            try? FileManager.default.removeItem(at: url)
            return []
        }
        return try JSONDecoder().decode([BookChapter].self, from: data).sorted { $0.index < $1.index }
    }

    public func save(_ chapters: [BookChapter], bookURL: String) throws {
        var normalized = chapters
        for index in normalized.indices {
            normalized[index].bookUrl = bookURL
            normalized[index].index = index
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(normalized)
        guard data.count <= Self.maximumDocumentBytes else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(bookURL), options: .atomic)
    }

    public func remove(bookURL: String) throws {
        let url = fileURL(bookURL)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func fileURL(_ bookURL: String) -> URL {
        let name = SHA256.hash(data: Data(bookURL.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(name).json")
    }
}

public actor InMemoryBookChapterRepository: BookChapterRepository {
    private var values: [String: [BookChapter]]
    public init(values: [String: [BookChapter]] = [:]) { self.values = values }
    public func load(bookURL: String) -> [BookChapter] { values[bookURL] ?? [] }
    public func save(_ chapters: [BookChapter], bookURL: String) { values[bookURL] = chapters }
    public func remove(bookURL: String) { values[bookURL] = nil }
}
