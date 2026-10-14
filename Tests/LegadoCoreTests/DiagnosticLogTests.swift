import Foundation
import Testing
@testable import LegadoCore

struct DiagnosticLogTests {
    @Test func boundedJournalSurvivesRelaunchAndCanBeCleared() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiagnosticLog(directory: directory, maximumEntries: 2, isEnabled: { true })
        log.record(category: "test", message: "first")
        log.record(.warning, category: "test", message: "second")
        log.record(.error, category: "test", message: "third")
        let restored = DiagnosticLog(directory: directory, maximumEntries: 2, isEnabled: { true })
        #expect(restored.snapshot().map(\.message) == ["third", "second"])
        #expect(restored.export().contains("[ERROR] [test] third"))
        #expect(!restored.export().contains("first"))
        try restored.clear()
        #expect(restored.snapshot().isEmpty)
        #expect(DiagnosticLog(directory: directory).snapshot().isEmpty)
    }

    @Test func disabledLoggingAndSensitiveRequestFields() {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disabled = DiagnosticLog(directory: directory, isEnabled: { false })
        disabled.record(category: "JS", message: "secret")
        #expect(disabled.snapshot().isEmpty)
        let log = DiagnosticLog(directory: directory, isEnabled: { true })
        var request = URLRequest(url: URL(string: "https://user:pass@example.com/chapter?token=TOP_SECRET#private")!)
        request.setValue("Bearer PRIVATE_HEADER", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("PRIVATE_BODY".utf8)
        log.network(request, status: 200, startedAt: Date())
        log.record(category: "JS", message: "token=PRIVATE_TOKEN password=PRIVATE_PASS https://example.com/?key=PRIVATE_QUERY")
        log.record(category: "JS", message: "Authorization: Bearer PRIVATE_AUTH")
        log.record(category: "JS", message: #"{"password": "PRIVATE_JSON"}"#)
        let exported = log.export()
        for secret in ["TOP_SECRET", "private", "user:pass", "PRIVATE_HEADER", "PRIVATE_BODY", "PRIVATE_TOKEN", "PRIVATE_PASS", "PRIVATE_QUERY", "PRIVATE_AUTH", "PRIVATE_JSON"] {
            #expect(!exported.contains(secret))
        }
        #expect(exported.contains("https://example.com/chapter"))
    }
}
