import Foundation

public struct SearchBook: Codable, Hashable, Identifiable, Sendable {
    public var bookURL: String
    public var origin: String
    public var originName: String
    public var type: Int
    public var name: String
    public var author: String
    public var kind: String?
    public var coverURL: String?
    public var intro: String?
    public var wordCount: String?
    public var latestChapterTitle: String?
    public var tocURL: String
    public var time: Int64
    public var originOrder: Int
    public var chapterWordCountText: String?
    public var chapterWordCount: Int
    public var respondTime: Int
    public var origins: Set<String>
    public var variables: [String: String]

    public var id: String { bookURL }
    public var variable: String? {
        get {
            guard !variables.isEmpty, let data = try? JSONEncoder().encode(variables) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        set {
            guard let newValue, let data = newValue.data(using: .utf8) else { variables = [:]; return }
            variables = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
    }

    public init(
        bookURL: String,
        origin: String,
        originName: String,
        type: Int,
        name: String,
        author: String = ""
    ) {
        self.bookURL = bookURL
        self.origin = origin
        self.originName = originName
        self.type = type
        self.name = name
        self.author = author
        tocURL = ""
        time = Int64(Date().timeIntervalSince1970 * 1_000)
        originOrder = 0
        chapterWordCountText = nil
        chapterWordCount = -1
        respondTime = -1
        origins = [origin]
        variables = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case bookUrl, origin, originName, type, name, author, kind, coverUrl, intro, wordCount
        case latestChapterTitle, tocUrl, time, variable, originOrder, chapterWordCountText
        case chapterWordCount, respondTime
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        bookURL = try value.decodeIfPresent(String.self, forKey: .bookUrl) ?? ""
        origin = try value.decodeIfPresent(String.self, forKey: .origin) ?? ""
        originName = try value.decodeIfPresent(String.self, forKey: .originName) ?? ""
        type = try value.decodeIfPresent(Int.self, forKey: .type) ?? 0
        name = try value.decodeIfPresent(String.self, forKey: .name) ?? ""
        author = try value.decodeIfPresent(String.self, forKey: .author) ?? ""
        kind = try value.decodeIfPresent(String.self, forKey: .kind)
        coverURL = try value.decodeIfPresent(String.self, forKey: .coverUrl)
        intro = try value.decodeIfPresent(String.self, forKey: .intro)
        wordCount = try value.decodeIfPresent(String.self, forKey: .wordCount)
        latestChapterTitle = try value.decodeIfPresent(String.self, forKey: .latestChapterTitle)
        tocURL = try value.decodeIfPresent(String.self, forKey: .tocUrl) ?? ""
        time = try value.decodeIfPresent(Int64.self, forKey: .time) ?? 0
        originOrder = try value.decodeIfPresent(Int.self, forKey: .originOrder) ?? 0
        chapterWordCountText = try value.decodeIfPresent(String.self, forKey: .chapterWordCountText)
        chapterWordCount = try value.decodeIfPresent(Int.self, forKey: .chapterWordCount) ?? -1
        respondTime = try value.decodeIfPresent(Int.self, forKey: .respondTime) ?? -1
        origins = [origin]
        let rawVariable = try value.decodeIfPresent(String.self, forKey: .variable)
        variables = rawVariable.flatMap { raw in
            try? JSONDecoder().decode([String: String].self, from: Data(raw.utf8))
        } ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.container(keyedBy: CodingKeys.self)
        try value.encode(bookURL, forKey: .bookUrl)
        try value.encode(origin, forKey: .origin)
        try value.encode(originName, forKey: .originName)
        try value.encode(type, forKey: .type)
        try value.encode(name, forKey: .name)
        try value.encode(author, forKey: .author)
        try value.encodeIfPresent(kind, forKey: .kind)
        try value.encodeIfPresent(coverURL, forKey: .coverUrl)
        try value.encodeIfPresent(intro, forKey: .intro)
        try value.encodeIfPresent(wordCount, forKey: .wordCount)
        try value.encodeIfPresent(latestChapterTitle, forKey: .latestChapterTitle)
        try value.encode(tocURL, forKey: .tocUrl)
        try value.encode(time, forKey: .time)
        try value.encodeIfPresent(variable, forKey: .variable)
        try value.encode(originOrder, forKey: .originOrder)
        try value.encodeIfPresent(chapterWordCountText, forKey: .chapterWordCountText)
        try value.encode(chapterWordCount, forKey: .chapterWordCount)
        try value.encode(respondTime, forKey: .respondTime)
    }
}
